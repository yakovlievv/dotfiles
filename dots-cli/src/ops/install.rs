use anyhow::Result;

use crate::context::{Context, HostKind};

use super::common::run_command;

pub fn run(ctx: &Context) -> Result<()> {
    ctx.logger
        .info(format!("Installing packages for {}", ctx.host.label()));

    match ctx.host {
        HostKind::MacOs => install_macos(ctx)?,
        HostKind::ArchLinux => install_arch(ctx)?,
        HostKind::Linux => {
            ctx.logger
                .warn("Generic Linux install routine is not implemented");
        }
    }

    run_command(ctx, "bat", ["cache", "--build"])?;

    Ok(())
}

fn install_macos(ctx: &Context) -> Result<()> {
    const BREW_PACKAGES: &[&str] = &[
        "fnm",
        "bat",
        "fzf",
        "eza",
        "zoxide",
        "starship",
        "fastfetch",
    ];

    if BREW_PACKAGES.is_empty() {
        ctx.logger.warn("No Homebrew packages configured");
    } else {
        let mut args = vec!["install"];
        args.extend(BREW_PACKAGES);
        run_command(ctx, "brew", args)?;
    }

    Ok(())
}

fn install_arch(ctx: &Context) -> Result<()> {
    const PACMAN_PACKAGES: &[&str] = &[
        "ripgrep",
        "fd",
        "tmux",
        "neovim",
        "bat",
        "bat-extras",
        "wget",
        "fzf",
        "eza",
        "zoxide",
        "starship",
        "fastfetch",
        "less",
        "luarocks",
        "zsh-syntax-highlighting",
        "zsh-autosuggestions",
        "kitty",
        "zsh",
        "lazygit",
        "fnm",
    ];

    let mut args = vec!["pacman", "-Syu", "--noconfirm"];
    args.extend(PACMAN_PACKAGES);
    run_command(ctx, "sudo", args)?;

    Ok(())
}
