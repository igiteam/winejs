# WineJS Packager for VS Code

Right-click any folder → Package Windows apps for WineJS platform.

## Features

- 📝 **App Name**: Auto-filled from folder name
- 🔍 **EXE Scanner**: Finds all executables, you pick the main one
- 🎨 **Icon Options**:
  - Extract real icons from EXE (with preview!)
  - Use external URL
  - Use default placeholder
- 📦 **ZIP Creation**: Packages entire app folder
- ☁️ **Spaces Upload**: Uploads to DigitalOcean Spaces (rtx/wine/)
- 📝 **Install Script**: Generates `install_appname.sh` with everything needed

## Installation

1. Run this installer script
2. Open VS Code
3. Right-click any Windows app folder → "WineJS: Package Windows App"

## Configuration

Set your DigitalOcean Spaces credentials in VS Code settings:
- `winejs.spaces.accessKey`
- `winejs.spaces.secretKey`
- `winejs.spaces.bucket`
- `winejs.spaces.endpoint`

## What Gets Generated

When you package an app, you get:
1. `AppName.zip` - The full app package
2. `install_AppName.sh` - Installation script for WineJS server

The install script does everything:
- Downloads from Spaces
- Creates directories
- Generates launch.sh
- Creates config.json
- Sets up docker-compose.yml
- Copies icon to translator

## Requirements

- DigitalOcean Spaces account (for cloud uploads)
- icoutils (for icon extraction): `brew install icoutils` or `apt-get install icoutils`
