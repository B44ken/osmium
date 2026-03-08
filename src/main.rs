mod app;
mod binds;
mod cli;
mod ipc;
mod terminal;

use anyhow::Result;
use clap::Parser;
use std::time::Instant;

fn main() -> Result<()> {
    let process_started = Instant::now();
    let cli = cli::Cli::parse();
    let launch_plan = cli::build_launch_plan(cli)?;

    if ipc::send_command(&launch_plan.dispatch)? {
        return Ok(());
    }

    app::run(launch_plan.startup_commands, process_started)
}
