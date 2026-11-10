# dot

Keep your dotfiles in a git repo, symlinked into `$HOME`, and synced across
machines. One bash script, no dependencies beyond git.

```console
$ dot add ~/.zshrc ~/.config/nvim
added   .zshrc
added   .config/nvim/init.lua
added   .config/nvim/lua/config/options.lua
$ dot sync
```

## Why another one

Symlink managers like stow and dotbot have a blind spot. Plenty of programs
save a file by writing a new copy and renaming it over the old one: editors,
theme switchers, settings GUIs. That replaces your symlink with a regular
file. From then on your repo quietly stops tracking that file.

`dot sync` checks every tracked path. When it finds a real file where its
symlink should be, it **adopts** it: it copies the new version into the repo,
puts the link back, and commits.

```console
$ dot sync
adopted .config/kitty/kitty.conf (an app replaced the link)
```

It also tells you when your dotfiles need attention, without slowing your prompt:

```console
dot: 2 new commit(s) on the remote, run: dot sync
dot: local dotfile changes not pushed, run: dot sync
```

That notice comes from the last fetch. A new fetch runs in the background,
at most every 10 minutes, so opening a terminal never waits on the network.

## Install

```sh
git clone https://github.com/simaanc/dot ~/.local/share/dot
~/.local/share/dot/bin/dot setup   # puts `dot` on PATH, adds the shell hook and login sync
```

You can clone it anywhere. `setup` links `~/.local/bin/dot` to the script.

## Quick start

**First machine:**

```sh
dot init ~/dotfiles git@github.com:you/dotfiles.git
dot add ~/.zshrc ~/.config/nvim ~/.config/kitty/kitty.conf
dot sync
dot setup
```

**Every other machine:**

```sh
dot clone git@github.com:you/dotfiles.git ~/dotfiles   # existing files are kept as *.dot-bak
dot setup
```

## Commands

| Command | What it does |
|---|---|
| `dot init [dir] [remote]` | create or register a dotfiles repo (default `~/dotfiles`) |
| `dot clone <url> [dir]` | clone on a new machine and link everything |
| `dot add <path>...` | move files or whole directories into the repo, leave symlinks |
| `dot rm <path>...` | stop tracking; the real file goes back in place |
| `dot sync` | adopt overwritten files, commit, `pull --rebase`, push |
| `dot check` | the one-line shell notice (silent when all is well) |
| `dot link` | create every symlink; anything in the way becomes `*.dot-bak` |
| `dot status` | broken or replaced links, plus `git status` |
| `dot setup` | shell hook and login sync (`--shell zsh\|bash\|fish`, `--no-shell`, `--no-boot`) |
| `dot git <args>` | run any git command in the repo |

## How it works

- Tracked files live in `<repo>/home/`, which mirrors `$HOME`, so
  `<repo>/home/.config/nvim/init.lua` is linked from `~/.config/nvim/init.lua`.
  The rest of the repo (a README, scripts) is yours.
- Only individual files are linked, never whole directories, so programs can
  keep writing caches and state next to your config.
- The repo is found through `$DOT_DIR`, then `~/.config/dot/dir` (written by
  `init` and `clone`), then `~/dotfiles`.
- `sync` commits first, then rebases onto the remote. If two machines changed
  the same file, it aborts the rebase, leaves your files as they were, and
  tells you. Nothing is overwritten.
- `setup` runs one sync shortly after boot or login: a systemd user timer on
  Linux, a launchd agent on macOS. It retries if the network isn't up yet.

## Compared to

| | dot | GNU stow | chezmoi | bare git repo |
|---|---|---|---|---|
| Files stay editable in place | yes (symlinks) | yes (symlinks) | no (copies, `chezmoi edit`) | yes |
| Survives apps replacing files | **adopts them** | silently untracked | needs `re-add` | yes |
| Sync and remote notice built in | yes | no | partial | no |
| Templates and secrets per machine | no | no | **yes** | no |
| Install | one bash file | package | binary | nothing |

If you need per-machine templates or encrypted secrets, use chezmoi. If you
want plain files with symlinks that stay correct, use dot.

## Requirements

bash 3.2 or newer (the stock macOS bash works) and git. Tested on Linux and macOS.

## Development

```sh
shellcheck bin/dot test/dot.bats
bats test/
DOT_BASH=/bin/bash bats test/   # test against another bash
scripts/ci-local                # run the checks and post them as commit statuses
```

## License

[GPL-3.0-or-later](LICENSE). Use it, change it, share it. If you distribute it, modified or not, it has to stay GPL with the source included.
