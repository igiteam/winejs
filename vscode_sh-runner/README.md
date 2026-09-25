# Shell Script Runner

One-click runner for shell scripts with automatic chmod.

## Features

- Right-click any .sh file → "⚙️Run .sh"
- Automatic chmod +x before execution
- Runs in VS Code terminal with proper working directory
- Editor title menu support

## Usage

- Right-click any .sh file in explorer → "⚙️Run .sh"
- Click "⚙️Run .sh" in editor title when editing .sh files
- Command Palette → "⚙️Run .sh"

## What it does

1. Makes the script executable (chmod +x)
2. Opens a terminal in the script's directory
3. Runs the script with ./scriptname.sh
4. Shows progress notifications

## Requirements

- VS Code 1.81.0 or higher
- Unix-like system (Linux, macOS) for chmod support
