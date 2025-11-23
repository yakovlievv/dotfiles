use anyhow::Result;

use crate::context::Context;

use super::{home, install, node, rust_toolchain, shell, tpm};

pub fn run(ctx: &Context) -> Result<()> {
    ctx.logger
        .info(format!("Running full bootstrap on {}", ctx.host.label()));

    home::run(ctx)?;
    install::run(ctx)?;
    shell::run(ctx)?;
    node::run(ctx)?;
    rust_toolchain::run(ctx)?;
    tpm::run(ctx)?;

    Ok(())
}
