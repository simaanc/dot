#!/usr/bin/env bats
# Each @test runs in its own subshell by design, so per-test exports are intended.
# shellcheck disable=SC2030,SC2031
# Every test gets its own $HOME, dotfiles repo, and a bare "remote".
# Run with: bats test/   (DOT_BASH=/bin/bash bats test/ to test another bash)

setup() {
  ROOT=$(cd "$(mktemp -d)" && pwd -P)
  export HOME="$ROOT/home" XDG_CONFIG_HOME="$ROOT/home/.config"
  mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false
  REMOTE="$ROOT/remote.git"
  git init -q --bare "$REMOTE"
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  export DOT_DIR="$HOME/dotfiles"
  DOT_BIN="$BATS_TEST_DIRNAME/../bin/dot"
  cd "$HOME" || return
}

teardown() { rm -rf "$ROOT"; }

dot() { "${DOT_BASH:-bash}" "$DOT_BIN" "$@"; }

# Switch to a second machine that shares the same remote.
as_machine_b() {
  export HOME="$ROOT/home-b" XDG_CONFIG_HOME="$ROOT/home-b/.config" DOT_DIR="$ROOT/home-b/dotfiles"
  mkdir -p "$HOME"
  cp "$ROOT/home/.gitconfig" "$HOME/.gitconfig"
  cd "$HOME" || return
}
as_machine_a() {
  export HOME="$ROOT/home" XDG_CONFIG_HOME="$ROOT/home/.config" DOT_DIR="$ROOT/home/dotfiles"
  cd "$HOME" || return
}

init_with_remote() { dot init "$DOT_DIR" "$REMOTE" >/dev/null; }

is_link_into_repo() { [ -L "$HOME/$1" ] && [ "$(readlink "$HOME/$1")" = "$DOT_DIR/home/$1" ]; }

@test "add moves a file into the repo and leaves a symlink" {
  init_with_remote
  echo hello >.zshrc
  run dot add .zshrc
  [ "$status" -eq 0 ]
  [[ $output == *"added   .zshrc"* ]]
  is_link_into_repo .zshrc
  [ "$(cat .zshrc)" = hello ]
}

@test "add recurses into directories and handles spaces" {
  init_with_remote
  mkdir -p ".config/my app/sub"
  echo a >".config/my app/a b.conf"
  echo b >".config/my app/sub/c.conf"
  dot add ".config/my app"
  is_link_into_repo ".config/my app/a b.conf"
  is_link_into_repo ".config/my app/sub/c.conf"
}

@test "add skips symlinks and paths outside HOME" {
  init_with_remote
  echo x >real
  ln -s real alias
  run dot add alias /etc/hostname
  [ "$status" -eq 0 ]
  [[ $output == *"skip (not a regular file): alias"* ]]
  [[ $output == *"skip (outside \$HOME)"* ]]
  [ ! -e "$DOT_DIR/home/alias" ]
}

@test "add is idempotent" {
  init_with_remote
  echo x >.rc
  dot add .rc
  run dot add .rc
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "rm restores the real file and untracks it" {
  init_with_remote
  echo x >.rc
  dot add .rc
  dot rm .rc
  [ ! -L .rc ]
  [ "$(cat .rc)" = x ]
  [ ! -e "$DOT_DIR/home/.rc" ]
}

@test "rm keeps a file an app already rewrote" {
  init_with_remote
  echo old >.rc
  dot add .rc
  rm .rc && echo new >.rc
  dot rm .rc
  [ "$(cat .rc)" = new ]
}

@test "sync commits and pushes" {
  init_with_remote
  echo x >.rc
  dot add .rc
  dot sync
  [ "$(git -C "$REMOTE" log --oneline | wc -l | tr -d ' ')" -eq 1 ]
  [[ $(git -C "$REMOTE" log -1 --format=%s) == "sync "*": .rc" ]]
}

@test "sync adopts a file whose symlink an app replaced" {
  init_with_remote
  echo v1 >.rc
  dot add .rc
  dot sync
  rm .rc && echo v2 >.rc        # what an atomic-save editor does
  run dot status
  [[ $output == *"replaced    .rc"* ]]
  run dot sync
  [ "$status" -eq 0 ]
  [[ $output == *"adopted .rc"* ]]
  is_link_into_repo .rc
  [ "$(git -C "$REMOTE" show main:home/.rc)" = v2 ]
}

@test "sync with nothing to do is quiet and succeeds" {
  init_with_remote
  echo x >.rc
  dot add .rc
  dot sync
  run dot sync
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "clone sets up a second machine and links everything" {
  init_with_remote
  echo x >.rc
  dot add .rc
  dot sync
  as_machine_b
  echo local >.rc
  run dot clone "$REMOTE" "$DOT_DIR"
  [ "$status" -eq 0 ]
  is_link_into_repo .rc
  [ "$(cat .rc.dot-bak)" = local ]
}

@test "two machines: check reports the remote is ahead, sync pulls and links new files" {
  init_with_remote
  echo one >.rc
  dot add .rc
  dot sync
  as_machine_b
  dot clone "$REMOTE" "$DOT_DIR" >/dev/null

  as_machine_a
  echo two >.rc
  echo n >.new
  dot add .new
  dot sync

  as_machine_b
  dot git fetch -q
  run dot check
  [[ $output == *"1 new commit(s) on the remote"* ]]
  dot sync
  [ "$(cat .rc)" = two ]
  is_link_into_repo .new
  run dot check
  [ -z "$output" ]
}

@test "conflict stops sync and leaves local files alone" {
  init_with_remote
  echo base >.rc
  dot add .rc
  dot sync
  as_machine_b
  dot clone "$REMOTE" "$DOT_DIR" >/dev/null

  as_machine_a
  echo from-a >.rc
  dot sync

  as_machine_b
  echo from-b >.rc
  run dot sync
  [ "$status" -ne 0 ]
  [[ $output == *"conflict with the remote"* ]]
  [ "$(cat .rc)" = from-b ]
  [ ! -d "$DOT_DIR/.git/rebase-merge" ]
  [ ! -d "$DOT_DIR/.git/rebase-apply" ]
}

@test "link backs up whatever is in the way" {
  init_with_remote
  echo repo >.rc
  dot add .rc
  rm .rc && echo other >.rc
  run dot link
  [[ $output == *"backup  .rc -> .rc.dot-bak"* ]]
  is_link_into_repo .rc
  [ "$(cat .rc.dot-bak)" = other ]
}

@test "check reports unpushed changes" {
  init_with_remote
  echo x >.rc
  dot add .rc
  dot sync
  echo y >.rc
  run dot check
  [ "$status" -eq 0 ]
  [[ $output == *"local dotfile changes not pushed"* ]]
}

@test "check is silent and succeeds without a repo" {
  export DOT_DIR="$ROOT/nowhere"
  run dot check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check refreshes a stale fetch in the background" {
  init_with_remote
  echo x >.rc
  dot add .rc
  dot sync
  rm -f "$DOT_DIR/.git/FETCH_HEAD"
  dot check
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -e "$DOT_DIR/.git/FETCH_HEAD" ] && break
    sleep 0.3
  done
  [ -e "$DOT_DIR/.git/FETCH_HEAD" ]
}

@test "status reports missing links" {
  init_with_remote
  echo x >.rc
  dot add .rc
  rm .rc
  run dot status
  [[ $output == *"missing     .rc"* ]]
}

@test "init registers the repo so DOT_DIR is not needed" {
  dot init "$HOME/mydots" >/dev/null
  unset DOT_DIR
  run dot dir
  [ "$output" = "$HOME/mydots" ]
}

@test "setup adds the zsh hook once" {
  init_with_remote
  touch .zshrc
  dot setup --shell zsh --no-boot >/dev/null
  dot setup --shell zsh --no-boot >/dev/null
  [ "$(grep -c '# dot:check' .zshrc)" -eq 1 ]
}

@test "setup writes a fish conf.d hook" {
  init_with_remote
  dot setup --shell fish --no-boot >/dev/null
  grep -q 'dot check' "$XDG_CONFIG_HOME/fish/conf.d/dot.fish"
}

@test "setup puts dot on PATH via ~/.local/bin" {
  init_with_remote
  PATH="/usr/bin:/bin" dot setup --no-shell --no-boot >/dev/null
  [ -L "$HOME/.local/bin/dot" ]
}

@test "unknown command prints usage and exits 2" {
  run dot frobnicate
  [ "$status" -eq 2 ]
  [[ $output == *"dot add <path>"* ]]
}
