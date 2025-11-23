mod cli;
mod context;
mod logging;
mod ops;

use anyhow::Result;
use clap::Parser;

fn main() -> Result<()> {
    let cli = cli::Cli::parse();

    if cli.help_requested {
        cli::print_help();
        return Ok(());
    }

    let context = context::Context::new(&cli)?;
    ops::run(&cli, &context)
}
