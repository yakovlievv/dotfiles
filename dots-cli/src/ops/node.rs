use anyhow::Result;

use super::common::run_command;
use crate::context::Context;

pub fn run(ctx: &Context) -> Result<()> {
    ctx.logger.info("Installing Node.js (fnm 24)");
    run_command(ctx, "fnm", ["install", "24"])
}
