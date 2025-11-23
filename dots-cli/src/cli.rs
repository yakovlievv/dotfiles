use std::path::PathBuf;

use clap::{CommandFactory, Parser, ValueHint};

#[derive(Debug, Parser)]
#[command(
    name = "dots",
    about = "Manage and bootstrap yakovlievv's dotfiles",
    version,
    disable_help_flag = true
)]
pub struct Cli {
    #[arg(long = "help", action = clap::ArgAction::SetTrue, help = "Print help information")]
    pub help_requested: bool,

    #[arg(
        short = 'h',
        long = "home",
        help = "Create home directory layout and symlink configs"
    )]
    pub home: bool,

    #[arg(
        short = 'i',
        long = "install",
        help = "Install required packages and tooling"
    )]
    pub install: bool,

    #[arg(
        short = 'b',
        long = "bootstrap",
        help = "Run the full bootstrap routine (home + install + shell)"
    )]
    pub bootstrap: bool,

    #[arg(short = 's', long = "shell", help = "Set zsh as the default shell")]
    pub shell: bool,

    #[arg(long = "node", help = "Install Node.js 24 via fnm")]
    pub node: bool,

    #[arg(long = "rust", help = "Install the Rust toolchain via rustup")]
    pub rust: bool,

    #[arg(long = "tpm", help = "Install the tmux plugin manager")]
    pub tpm: bool,

    #[arg(
        long = "dry-run",
        help = "Print intended actions without executing them"
    )]
    pub dry_run: bool,

    #[arg(short = 'v', long = "verbose", help = "Enable verbose output")]
    pub verbose: bool,

    #[arg(
        long = "root",
        value_name = "DIR",
        value_hint = ValueHint::DirPath,
        help = "Path to the dotfiles repository root"
    )]
    pub root: Option<PathBuf>,

    #[arg(
        long = "shell-path",
        value_name = "PATH",
        help = "Override the target shell path (defaults to /usr/bin/zsh)"
    )]
    pub shell_path: Option<PathBuf>,
}

pub fn print_help() {
    let mut command = Cli::command();
    command.print_help().expect("failed to print help");
    println!();
}

pub(crate) fn default_root() -> PathBuf {
    std::env::var_os("DOTFILES_ROOT")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join("dots")))
        .unwrap_or_else(|| PathBuf::from("."))
}
