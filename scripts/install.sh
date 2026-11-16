#!/bin/sh
# Installs Burrow from its latest GitHub release.
#   curl -fsSL https://github.com/Satasdin/Burrow/releases/latest/download/install.sh | sh
#   ... | sh -s -- --app     also installs the desktop application
#   ... | sh -s -- --add-to-path | --no-path    add the burrow folder to your PATH without asking, or leave it alone
# The app comes down through curl, which marks nothing as downloaded from the internet, so it opens without the
# "Open Anyway" step a browser download needs (Burrow isn't notarised by Apple).
set -eu

BASE="${BURROW_RELEASE_BASE:-https://github.com/Satasdin/Burrow/releases/latest/download}"
BIN_DIR="${BURROW_BIN_DIR:-$HOME/.local/bin}"
WITH_APP=0
PATH_CHOICE=ask
for arg in "$@"; do
  case "$arg" in
    --app) WITH_APP=1 ;;
    --add-to-path) PATH_CHOICE=yes ;;
    --no-path) PATH_CHOICE=no ;;
    *) echo "burrow: unknown option $arg" >&2; exit 2 ;;
  esac
done

fail() { echo "burrow: $1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this release is for macOS only."
[ "$(uname -m)" = "arm64" ] || fail "this release is for Apple silicon only."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "macOS 14 or later is required."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() {
  curl -fsSL "$BASE/$1" -o "$tmp/$1" || fail "could not download $1."
  expected="$(grep " $1\$" "$tmp/SHA256SUMS" | cut -d' ' -f1)"
  [ -n "$expected" ] || fail "no checksum for $1."
  actual="$(shasum -a 256 "$tmp/$1" | cut -d' ' -f1)"
  [ "$expected" = "$actual" ] || fail "the checksum of $1 does not match."
}

curl -fsSL "$BASE/SHA256SUMS" -o "$tmp/SHA256SUMS" || fail "could not reach the release."

fetch burrow-macos-arm64.tar.gz
mkdir -p "$BIN_DIR"
tar -xzf "$tmp/burrow-macos-arm64.tar.gz" -C "$tmp"
install -m 755 "$tmp/burrow" "$BIN_DIR/burrow"
echo "Installed $BIN_DIR/burrow"

if [ "$WITH_APP" = 1 ]; then
  fetch Burrow-macos-arm64.zip
  if [ -n "${BURROW_APP_DIR:-}" ]; then app_dir="$BURROW_APP_DIR"
  elif [ -w /Applications ]; then app_dir=/Applications
  else app_dir="$HOME/Applications"; fi
  mkdir -p "$app_dir"
  rm -rf "$app_dir/Burrow.app"
  ditto -x -k "$tmp/Burrow-macos-arm64.zip" "$app_dir"
  echo "Installed $app_dir/Burrow.app"
fi

# The folder burrow went into must be on PATH, or the shell answers "command not found: burrow" (a tester, 16 November).
on_path=0
case ":$PATH:" in *":$BIN_DIR:"*) on_path=1 ;; esac
shown_dir="$BIN_DIR"
case "$BIN_DIR" in "$HOME"/*) shown_dir="\$HOME${BIN_DIR#"$HOME"}" ;; esac
line="export PATH=\"$shown_dir:\$PATH\""
case "${SHELL:-/bin/zsh}" in
  */bash) rc="$HOME/.bash_profile" ;;
  */fish) rc=""; line="fish_add_path $BIN_DIR" ;;
  *) rc="$HOME/.zshrc" ;;
esac
added=0
if [ "$on_path" = 0 ] && [ -n "$rc" ] && grep -qsF "$line" "$rc"; then added=1; fi
if [ "$on_path" = 0 ] && [ "$added" = 0 ] && [ -n "$rc" ]; then
  answer=n
  if [ "$PATH_CHOICE" = yes ]; then answer=y
  elif [ "$PATH_CHOICE" = ask ] && [ -t 1 ] && (: </dev/tty) 2>/dev/null; then
    # Piped from curl, the script itself is on stdin, so the question is asked on the terminal.
    printf "\nburrow is in %s, which your shell doesn't look in yet.\nAdd it to your PATH in %s? [Y/n] " "$BIN_DIR" "$rc"
    read -r answer </dev/tty || answer=n
    [ -z "$answer" ] && answer=y
  fi
  case "$answer" in
    [Yy]*) printf '\n# Added by the Burrow installer\n%s\n' "$line" >> "$rc"; added=1; echo "Added to $rc:  $line" ;;
  esac
fi

echo
if [ "$on_path" = 1 ]; then
  echo "Done. Check it with:  burrow --version"
elif [ "$added" = 1 ]; then
  echo "Done. New terminal windows find burrow. In this one, run this first:"
  echo "  $line"
  echo "then check it with:  burrow --version"
else
  echo "Done, but your shell can't find burrow yet: $BIN_DIR is not on your PATH."
  if [ -n "$rc" ]; then
    echo "Add this line to $rc, then open a new terminal window:"
  else
    echo "Run this once:"
  fi
  echo "  $line"
  echo "Until then, run it by its full path:  $BIN_DIR/burrow --version"
fi
command -v ollama >/dev/null 2>&1 || echo "Burrow reads with local models through Ollama: https://ollama.com"
echo "Next:  ollama pull qwen3-embedding:0.6b  and a chat model, then  burrow vault new <folder>"
