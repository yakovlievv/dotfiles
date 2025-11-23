use anyhow::{Result, anyhow};

use crate::context::Context;

use super::common::{ensure_dir, remove_path, run_command};

pub fn run(ctx: &Context) -> Result<()> {
    let tpm_path = ctx.paths.config.join("tmux/plugins/tpm");
    ctx.logger.info(format!(
        "Installing tmux plugin manager at {}",
        tpm_path.display()
    ));

    if let Some(parent) = tpm_path.parent() {
        ensure_dir(ctx, parent)?;
    }

    if tpm_path.exists() {
        remove_path(ctx, &tpm_path)?;
    }

    let tpm_path_str = tpm_path
        .to_str()
        .ok_or_else(|| anyhow!("non-utf8 path: {}", tpm_path.display()))?;

    run_command(
        ctx,
        "git",
        [
            "clone",
            "--depth=1",
            "https://github.com/tmux-plugins/tpm.git",
            tpm_path_str,
        ],
    )
}
