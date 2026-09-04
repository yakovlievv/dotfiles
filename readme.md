## Install

```sh
source ./setup.sh
```
this script will symlink internal `/bin` directory to `~/bin` and add it to path, that is my whole library of scripts, after that you can open new shell and use scripts for installation:

```sh
home
```

`home` — OS-aware, symlinks paths from dotfiles. To modify what exact paths do you want symlinked go to the file and change the `MAC_LINKS` or `LINUX_LINKS` accordingly to your OS. Only those directories will be symlinked.

other install scripts are raw and unfinished

