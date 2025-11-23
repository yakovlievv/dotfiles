use anyhow::{Result, anyhow};

use crate::context::Context;

use super::common::run_command;

pub fn run(ctx: &Context) -> Result<()> {
    let shell_path = ctx
        .shell_path
        .to_str()
        .ok_or_else(|| anyhow!("non-utf8 shell path: {}", ctx.shell_path.display()))?;

    ctx.logger
        .info(format!("Setting default shell to {}", shell_path));

    run_command(ctx, "chsh", ["-s", shell_path])
}
