# WineJS Desktop Packager for VS Code v3.0

**Right-click any Windows app folder → Create a native macOS desktop app that runs the Windows EXE through Wine.**

## ✨ New in v3.0

- 🚀 **NO TERMINAL WINDOW** - Apps run silently in the background!
- ⚡ **SYMLINK MODE** - Instant creation, no disk space wasted!
- 📦 **Install/Uninstall Scripts** - Professional installation experience
- 🎨 **Icon Extraction KEPT** - Still extract real icons from EXE files!
- 🖥️ **Better Dock Integration** - No bouncing icon!

## Features

- 📝 **App Name**: Auto-filled from folder name
- 🔍 **EXE Scanner**: Finds all executables, you pick the main one
- 🎨 **Icon Options**:
  - **Extract real icons from EXE** (kept from v2.0!)
  - Use external URL
  - Use default placeholder
- 🖥️ **Native macOS App**: Creates a proper .app bundle
- ⚡ **Symlink Mode**: Instant creation, no file copying (optional)
- 📌 **Desktop Shortcut**: Automatically placed on your Desktop
- 📁 **Applications Folder**: Copied to ~/Applications
- 🖱️ **Dock Integration**: Automatically added to Dock
- 🍷 **Wine Integration**: Smart Wine detection
- 🚫 **No Terminal**: Apps run silently in background

## Installation

1. Run this installer script
2. Open VS Code
3. Right-click any Windows app folder → "WineJS: Create macOS Desktop App (No Terminal)"

## Requirements

- **Wine** must be installed on your Mac
  - Install via Homebrew: `brew install --cask wine-stable`
  - Or download from: https://winehq.org
- **icoutils** for icon extraction: `brew install icoutils`

## What Gets Generated

When you package an app, you get:
1. **AppName.app** - Native macOS application bundle
2. Placed on your Desktop
3. Copied to ~/Applications
4. Added to your Dock automatically
5. **Install.command** - Reinstall script
6. **Uninstall.command** - Complete removal script

## Configuration

Settings in VS Code:
- `winejs.winePath`: Custom path to Wine binary
- `winejs.defaultCategory`: Default app category for Finder
- `winejs.useSymlink`: Use symlink instead of copy (default: true)

## How It Works

The launcher script (v3.0):
1. Finds Wine on your system (checks common locations)
2. Sets up a dedicated Wine prefix for the app
3. Changes to the app directory (symlink or copy)
4. **Launches with nohup - NO TERMINAL WINDOW!**
5. Exits immediately so Dock icon doesn't bounce

## Uninstalling

Run **Uninstall.command** in the project folder, or:
Simply drag the .app from Applications to Trash.
Optionally remove the Wine prefix: `rm -rf ~/.wine-AppName`

