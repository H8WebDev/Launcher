#!/usr/bin/env bash
set -e

LAUNCHER_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCRIPT="$LAUNCHER_PATH/run"
BIN_DIR="$HOME/.local/bin"
LINK_PATH="$BIN_DIR/run"

echo "Installing H8 Launcher..."
echo

# Check that the run script exists:
if [ ! -f "$RUN_SCRIPT" ]; then
	echo "Error: run script was not found in:"
	echo " $LAUNCHER_PATH"
	exit 1
fi

# Check that Perl is available:
if ! command -v perl >/dev/null 2>&1; then
	echo "Error: Perl was not found in your PATH."
	echo "Please install Perl and try again."
	exit 1
fi

# Make the run script executable:
chmod +x "$RUN_SCRIPT"

# Create ~/.local/bin if it doesn't exist:
mkdir -p "$BIN_DIR"

# Create or update the symbolic link:
if [ -L "$LINK_PATH" ] || [ -e "$LINK_PATH" ]; then
	rm -f "$LINK_PATH"
fi
ln -s "$RUN_SCRIPT" "$LINK_PATH"

echo "H8 Launcher has been installed successfully."
echo
echo "The command is available at:"
echo "  $LINK_PATH"
echo

# Check whether ~/.local/bin is already in PATH:
case ":$PATH:" in
	*":$BIN_DIR:"*)
		echo "You can now run:"
		echo
		echo " run"
	;;
	*)
		echo "Note: $BIN_DIR is not currently in your PATH."
		echo
		echo "Add the following line to your shell configuration file:"
		echo
		echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
		echo
		echo "Then restart your terminal or reload your shell configuration."
	;;
esac
