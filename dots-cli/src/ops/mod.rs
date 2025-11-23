mod bootstrap;
mod common;
mod home;
mod install;
mod node;
mod rust_toolchain;
mod shell;
mod tpm;

use anyhow::{Result, bail};

use crate::{cli::Cli, context::Context};

pub fn run(cli: &Cli, ctx: &Context) -> Result<()> {
    let mut executed = false;

    if cli.bootstrap {
        executed = true;
        bootstrap::run(ctx)?;
    } else {
        if cli.home {
            executed = true;
            home::run(ctx)?;
        }
        if cli.install {
            executed = true;
            install::run(ctx)?;
        }
        if cli.shell {
            executed = true;
            shell::run(ctx)?;
        }
        if cli.node {
            executed = true;
            node::run(ctx)?;
        }
        if cli.rust {
            executed = true;
            rust_toolchain::run(ctx)?;
        }
        if cli.tpm {
            executed = true;
            tpm::run(ctx)?;
        }
    }

    if !executed {
        crate::cli::print_help();
        ctx.logger
            .error("No operation specified; see --help for usage");
        bail!("no operation specified; see --help for usage");
    }

    Ok(())
}
