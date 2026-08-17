#!/bin/bash

# Installation script for Omarchy Favorite Folders
# Installs, enables, and updates the favorite folders bar widget.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="omarchy-favorite-folders"
TARGET_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  -e, --enable     Enable the widget on Omarchy bar after installation
  -r, --restart    Restart omarchy-shell immediately to apply changes
  -h, --help       Show this help message

Examples:
  ./install.sh --enable --restart
  omarchy plugin add https://github.com/MrDemonc/omarchy-favorite-folders --enable
EOF
}

ENABLE=0
RESTART=0

while (( $# > 0 )); do
  case "$1" in
    -e|--enable) ENABLE=1; shift ;;
    -r|--restart) RESTART=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

echo "==> Validating plugin..."
omarchy plugin validate "$SCRIPT_DIR"

echo "==> Copying files to $TARGET_DIR..."
mkdir -p "$TARGET_DIR"
cp -f "$SCRIPT_DIR/manifest.json" "$TARGET_DIR/"
cp -f "$SCRIPT_DIR/FavoriteFolders.qml" "$TARGET_DIR/"
cp -f "$SCRIPT_DIR/FoldersHelper.js" "$TARGET_DIR/"
cp -f "$SCRIPT_DIR/README.md" "$TARGET_DIR/" 2>/dev/null || true

echo "==> Requesting plugin rescan from omarchy-shell..."
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

if [[ $ENABLE -eq 1 ]]; then
  echo "==> Enabling widget in the bar layout..."
  if omarchy plugin enable "$PLUGIN_ID" --before omarchy.audio 2>/dev/null; then
    echo "    Plugin placed before omarchy.audio"
  elif omarchy plugin enable "$PLUGIN_ID" --section right 2>/dev/null; then
    echo "    Plugin placed in the right section of the bar"
  else
    omarchy plugin enable "$PLUGIN_ID" || true
  fi
fi

if [[ $RESTART -eq 1 || $ENABLE -eq 1 ]]; then
  echo "==> Restarting omarchy-shell..."
  rm -rf "$HOME/.cache/quickshell/qmlcache" 2>/dev/null || true
  omarchy restart shell || echo "Note: run 'omarchy restart shell' to reload the interface."
fi

echo
echo "✅ Installation completed successfully."
echo "   Plugin ID: $PLUGIN_ID"
echo "   To remove:  omarchy plugin remove $PLUGIN_ID"
