#!/bin/bash

# macOS App Packager - Auto-generated variables
export APP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
export APP_NAME="winex_x86_64"
export RESOURCES_DIR="$APP_PATH/Contents/Resources"
export SCRIPTS_DIR="$RESOURCES_DIR/Scripts"
export BUNDLE_ID="com.gabrielmajorski.winexx8664"
export APP_VERSION="1.0.0"


pkill -9 -U $(whoami) wineserver wine wine64 wine-preloader wine64-preloader && pgrep -U $(whoami) -f ".exe" | xargs kill -9 2>/dev/null