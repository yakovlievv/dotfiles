use std::process::Command;

use anyhow::{Context as AnyhowContext, Result, anyhow};

use crate::context::Context;

pub fn run(ctx: &Context) -> Result<()> {
    ctx.logger.info("Installing Rust toolchain (rustup)");
    ctx.logger.action("download and run rustup installer");

    if ctx.dry_run {
        return Ok(());
    }

    let status = Command::new("sh")
        .arg("-c")
        .arg("curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y")
        .env("RUSTUP_INIT_SKIP_PATH_CHECK", "yes")
        .status()
        .with_context(|| "failed to run rustup installer")?;

    if status.success() {
        Ok(())
    } else {
        Err(anyhow!("rustup installer exited with status {}", status))
    }
}
