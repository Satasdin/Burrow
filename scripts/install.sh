#!/bin/sh
# Installs CAMR from its latest GitHub release.
#   curl -fsSL https://github.com/Satasdin/CAMR/releases/latest/download/install.sh | sh
#   ... | sh -s -- --app     also installs the desktop application
#   ... | sh -s -- --add-to-path | --no-path    add the camr folder to your PATH without asking, or leave it alone
# The app comes down through curl, which marks nothing as downloaded from the internet, so it opens without the
# "Open Anyway" step a browser download needs (CAMR isn't notarised by Apple).
set -eu

BASE="${CAMR_RELEASE_BASE:-https://github.com/Satasdin/CAMR/releases/latest/download}"
BIN_DIR="${CAMR_BIN_DIR:-$HOME/.local/bin}"
WITH_APP=0
PATH_CHOICE=ask
for arg in "$@"; do
  case "$arg" in
    --app) WITH_APP=1 ;;
    --add-to-path) PATH_CHOICE=yes ;;
    --no-path) PATH_CHOICE=no ;;
    *) echo "camr: unknown option $arg" >&2; exit 2 ;;
  esac
done

fail() { echo "camr: $1" >&2; exit 1; }

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

fetch camr-macos-arm64.tar.gz
mkdir -p "$BIN_DIR"
tar -xzf "$tmp/camr-macos-arm64.tar.gz" -C "$tmp"
install -m 755 "$tmp/camr" "$BIN_DIR/camr"
echo "Installed $BIN_DIR/camr"
# CAMR was called Burrow until 1.4 (D-124). Programs, hooks and settings made then run `burrow`, so that name stays,
# as a link to camr: an older burrow there is replaced by it.
rm -f "$BIN_DIR/burrow"
ln -s camr "$BIN_DIR/burrow"
echo "Linked $BIN_DIR/burrow to camr, so setups made before the rename keep working"

if [ "$WITH_APP" = 1 ]; then
  fetch CAMR-macos-arm64.zip
  if [ -n "${CAMR_APP_DIR:-}" ]; then app_dir="$CAMR_APP_DIR"
  elif [ -w /Applications ]; then app_dir=/Applications
  else app_dir="$HOME/Applications"; fi
  mkdir -p "$app_dir"
  rm -rf "$app_dir/CAMR.app"
  ditto -x -k "$tmp/CAMR-macos-arm64.zip" "$app_dir"
  echo "Installed $app_dir/CAMR.app"
  # The app before the rename, so there aren't two (D-124).
  if [ -d "$app_dir/Burrow.app" ]; then
    rm -rf "$app_dir/Burrow.app"
    echo "Removed $app_dir/Burrow.app: CAMR.app replaces it, with your vaults and settings"
  fi
fi

# The folder camr went into must be on PATH, or the shell answers "command not found: camr" (a tester, 16 November).
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
    printf "\ncamr is in %s, which your shell doesn't look in yet.\nAdd it to your PATH in %s? [Y/n] " "$BIN_DIR" "$rc"
    read -r answer </dev/tty || answer=n
    [ -z "$answer" ] && answer=y
  fi
  case "$answer" in
    [Yy]*) printf '\n# Added by the CAMR installer\n%s\n' "$line" >> "$rc"; added=1; echo "Added to $rc:  $line" ;;
  esac
fi

echo
if [ "$on_path" = 1 ]; then
  echo "Done. Check it with:  camr --version"
elif [ "$added" = 1 ]; then
  echo "Done. New terminal windows find camr. In this one, run this first:"
  echo "  $line"
  echo "then check it with:  camr --version"
else
  echo "Done, but your shell can't find camr yet: $BIN_DIR is not on your PATH."
  if [ -n "$rc" ]; then
    echo "Add this line to $rc, then open a new terminal window:"
  else
    echo "Run this once:"
  fi
  echo "  $line"
  echo "Until then, run it by its full path:  $BIN_DIR/camr --version"
fi
command -v ollama >/dev/null 2>&1 || echo "CAMR reads with local models through Ollama: https://ollama.com"
echo "Next:  ollama pull qwen3-embedding:0.6b  and a chat model, then  camr vault new <folder>"
