use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::thread;
use std::time::Duration;

use anyhow::{Context, Result};
use crossbeam_channel::Sender;
use directories::BaseDirs;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AppCommand {
    OpenTerminal { cwd: Option<PathBuf> },
    OpenEditor { path: PathBuf },
    OpenBrowser { url: String },
    AddBind { event: String, command: String },
}

pub fn osm_dir() -> Result<PathBuf> {
    let base_dirs = BaseDirs::new().context("failed to locate home directory")?;
    let dir = base_dirs.home_dir().join(".osm");
    fs::create_dir_all(&dir).context("failed to create ~/.osm")?;
    Ok(dir)
}

pub fn socket_path() -> Result<PathBuf> {
    Ok(osm_dir()?.join("osmium.sock"))
}

pub fn session_binds_path() -> Result<PathBuf> {
    Ok(osm_dir()?.join("session-binds.yaml"))
}

pub fn send_command(command: &AppCommand) -> Result<bool> {
    let socket_path = socket_path()?;

    match UnixStream::connect(&socket_path) {
        Ok(mut stream) => {
            let payload = serde_json::to_vec(command)?;
            stream.write_all(&payload)?;
            stream.write_all(b"\n")?;
            Ok(true)
        }
        Err(error)
            if matches!(
                error.kind(),
                std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
            ) =>
        {
            if socket_path.exists() {
                let _ = fs::remove_file(&socket_path);
            }
            Ok(false)
        }
        Err(error) => Err(error).context("failed to contact running osmium instance"),
    }
}

pub struct CommandServer {
    shutdown: Arc<AtomicBool>,
    socket_path: PathBuf,
    thread: Option<thread::JoinHandle<()>>,
}

impl CommandServer {
    pub fn start(sender: Sender<AppCommand>) -> Result<Self> {
        let socket_path = socket_path()?;
        if socket_path.exists() {
            let _ = fs::remove_file(&socket_path);
        }

        let listener = UnixListener::bind(&socket_path)
            .with_context(|| format!("failed to bind {}", socket_path.display()))?;
        listener
            .set_nonblocking(true)
            .context("failed to configure command socket")?;

        let shutdown = Arc::new(AtomicBool::new(false));
        let shutdown_flag = shutdown.clone();
        let thread = thread::spawn(move || {
            while !shutdown_flag.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        if let Err(error) = handle_stream(stream, &sender) {
                            eprintln!("osmium command socket error: {error:#}");
                        }
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(40));
                    }
                    Err(error) => {
                        eprintln!("osmium listener error: {error}");
                        thread::sleep(Duration::from_millis(100));
                    }
                }
            }
        });

        Ok(Self {
            shutdown,
            socket_path,
            thread: Some(thread),
        })
    }
}

impl Drop for CommandServer {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        let _ = UnixStream::connect(&self.socket_path);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        if self.socket_path.exists() {
            let _ = fs::remove_file(&self.socket_path);
        }
    }
}

fn handle_stream(stream: UnixStream, sender: &Sender<AppCommand>) -> Result<()> {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();

    loop {
        line.clear();
        let bytes = reader.read_line(&mut line)?;
        if bytes == 0 {
            break;
        }

        let command = serde_json::from_str::<AppCommand>(line.trim())?;
        sender
            .send(command)
            .context("failed to enqueue app command")?;
    }

    Ok(())
}
