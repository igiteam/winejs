# Python Script Runner

One-click runner for Python scripts with virtual environment support.

## Features

- Right-click any .py file → "▶️ Run .py"
- Automatic Python 3 interpreter detection
- Virtual environment detection (venv, .venv, env)
- Runs in VS Code terminal with proper working directory
- Editor title menu support

## Usage

- Right-click any .py file in explorer → "▶️ Run .py"
- Click "▶️ Run .py" in editor title when editing .py files
- Command Palette → "▶️ Run .py"

## What it does

1. Detects Python interpreter (python3 or virtual env)
2. Opens a terminal in the script's directory
3. Runs the script with python3 scriptname.py
4. Shows progress notifications

## Requirements

- VS Code 1.81.0 or higher
- Python 3.x installed
