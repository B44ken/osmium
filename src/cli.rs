use std::env;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

use crate::ipc::AppCommand;

#[derive(Debug, Parser)]
#[command(
    name = "osm",
    version,
    about = "Tabbed terminal, editor, and browser shell"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,
}

#[derive(Debug, Subcommand)]
pub enum Commands {
    Edit { path: PathBuf },
    Web { url: String },
    Bind { trigger: String, command: String },
}

#[derive(Debug)]
pub struct LaunchPlan {
    pub dispatch: AppCommand,
    pub startup_commands: Vec<AppCommand>,
}

pub fn build_launch_plan(cli: Cli) -> Result<LaunchPlan> {
    let cwd = env::current_dir().context("failed to detect current directory")?;
    let default_terminal = AppCommand::OpenTerminal {
        cwd: Some(cwd.clone()),
    };

    let plan = match cli.command {
        None => LaunchPlan {
            dispatch: default_terminal.clone(),
            startup_commands: vec![default_terminal],
        },
        Some(Commands::Edit { path }) => {
            let resolved = resolve_path(&cwd, &path);
            LaunchPlan {
                dispatch: AppCommand::OpenEditor {
                    path: resolved.clone(),
                },
                startup_commands: vec![AppCommand::OpenEditor { path: resolved }],
            }
        }
        Some(Commands::Web { url }) => {
            let normalized = normalize_url(&url);
            LaunchPlan {
                dispatch: AppCommand::OpenBrowser {
                    url: normalized.clone(),
                },
                startup_commands: vec![AppCommand::OpenBrowser { url: normalized }],
            }
        }
        Some(Commands::Bind { trigger, command }) => LaunchPlan {
            dispatch: AppCommand::AddBind {
                event: trigger.clone(),
                command: command.clone(),
            },
            startup_commands: vec![
                default_terminal,
                AppCommand::AddBind {
                    event: trigger,
                    command,
                },
            ],
        },
    };

    Ok(plan)
}

fn resolve_path(cwd: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        cwd.join(path)
    }
}

fn normalize_url(url: &str) -> String {
    if url.contains("://") {
        url.to_owned()
    } else {
        format!("https://{url}")
    }
}
