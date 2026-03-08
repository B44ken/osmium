use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use crate::ipc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionBind {
    pub event: String,
    pub command: String,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct SessionBindFile {
    binds: Vec<SessionBind>,
}

pub struct BindManager {
    binds: Vec<SessionBind>,
    path: PathBuf,
}

impl BindManager {
    pub fn new() -> Result<Self> {
        let path = ipc::session_binds_path()?;
        let binds = if path.exists() {
            let raw = fs::read_to_string(&path)
                .with_context(|| format!("failed to read {}", path.display()))?;
            serde_yaml::from_str::<SessionBindFile>(&raw)
                .unwrap_or_default()
                .binds
        } else {
            Vec::new()
        };

        Ok(Self { binds, path })
    }

    pub fn all(&self) -> &[SessionBind] {
        &self.binds
    }

    pub fn add_bind(&mut self, event: String, command: String) -> Result<()> {
        self.binds.push(SessionBind { event, command });
        self.persist()
    }

    pub fn commands_for_save(&self, path: &Path) -> Vec<String> {
        let full_path_event = format!("save:{}", path.display());
        let file_name_event = path
            .file_name()
            .map(|name| format!("save:{}", name.to_string_lossy()));

        self.binds
            .iter()
            .filter(|bind| {
                bind.event == full_path_event
                    || file_name_event
                        .as_deref()
                        .is_some_and(|candidate| bind.event == candidate)
            })
            .map(|bind| bind.command.clone())
            .collect()
    }

    pub fn cleanup(&self) {
        if self.path.exists() {
            let _ = fs::remove_file(&self.path);
        }
    }

    fn persist(&self) -> Result<()> {
        let data = SessionBindFile {
            binds: self.binds.clone(),
        };
        let yaml = serde_yaml::to_string(&data)?;
        fs::write(&self.path, yaml)
            .with_context(|| format!("failed to write {}", self.path.display()))?;
        Ok(())
    }
}
