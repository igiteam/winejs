# ===============================================
# ICNS CREATION RECIPE - FULLY COMMENTED
# ===============================================

# STEP 1: DOWNLOAD THE IMAGE FROM URL
# ===============================================
# Define the URL where your icon lives (GitHub raw URL works great)
ICON_URL="https://raw.githubusercontent.com/igiteam/winejs/refs/heads/main/images/ssd-icon.png"

# Extract just the filename from the URL (e.g., "ssd-icon.png")
# ${ICON_URL##*.} gets everything after the last dot
# The extra stuff removes query parameters if they exist
ICON_FILE="appicon.${ICON_URL##*.}"
ICON_FILE="${ICON_FILE%\?*}"

# Download the image to /tmp (temporary directory)
# -s = silent mode (no progress bar)
# -L = follow redirects
curl -s -L "$ICON_URL" -o "/tmp/$ICON_FILE"

# STEP 2: VERIFY DOWNLOAD AND COPY TO PUBLIC FOLDER
# ===============================================
# Check if the file exists AND has content (not empty)
if [ -f "/tmp/$ICON_FILE" ] && [ -s "/tmp/$ICON_FILE" ]; then
    echo "✅ Icon downloaded successfully!"
    
    # Create a 'public' directory for our assets
    mkdir -p public
    
    # Copy the downloaded image to public/app_icon.png
    cp "/tmp/$ICON_FILE" "public/app_icon.png"

# STEP 3: CREATE ICONSET DIRECTORY
# ===============================================
    # An iconset is a folder containing all the different sizes macOS needs
    # macOS expects specific sizes: 16, 32, 64, 128, 256, 512, 1024
    # Each size also has a @2x (retina) version
    ICONSET_DIR="public/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"

# STEP 4: GENERATE ALL ICON SIZES USING SIPS
# ===============================================
    # sips = Scriptable Image Processing System (built into macOS)
    # -z = resize (width height)
    # Loop through all required sizes
    for SIZE in 16 32 64 128 256 512 1024; do
        # Generate regular size (1x) - e.g., icon_16x16.png
        sips -z $SIZE $SIZE "public/app_icon.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" 2>/dev/null || true
        
        # Generate retina size (2x) - e.g., icon_16x16@2x.png
        RETINA=$((SIZE * 2))
        sips -z $RETINA $RETINA "public/app_icon.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" 2>/dev/null || true
    done

# STEP 5: CONVERT ICONSET TO ICNS USING ICONUTIL
# ===============================================
    # iconutil = macOS tool that converts iconset folders to .icns files
    # -c icns = convert to icns format
    # -o = output file path
    if command -v iconutil &> /dev/null; then
        iconutil -c icns "$ICONSET_DIR" -o "public/app_icon.icns" 2>/dev/null
        echo "✅ Created .icns file"
    else
        # Fallback if iconutil isn't available (older macOS)
        cp "public/app_icon.png" "public/app_icon.icns"
    fi

# STEP 6: CLEANUP
# ===============================================
    # Remove the temporary iconset directory (we only need the .icns)
    rm -rf "$ICONSET_DIR"

# STEP 7: FALLBACK IF DOWNLOAD FAILED
# ===============================================
else
    echo "⚠ Download failed, creating fallback icon"
    mkdir -p public
    
    # Base64 encoded image - a simple placeholder icon
    # This is a tiny PNG encoded as text
    cat > public/app_icon.png.b64 << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAgAAAAIAAQMAAADOtgr5AAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAANQTFRFAAAAp3o92gAAABxJREFUeJztwTEBAAAAwqD1T20Hb6AAAAAAAAA+Bhw4AAG1cXrRAAAAAElFTkSuQmCC
EOF
    
    # Decode the base64 to create an actual PNG file
    # -D = decode base64
    base64 -D < public/app_icon.png.b64 > public/app_icon.png 2>/dev/null || {
        # If base64 decode fails, create a text file as last resort
        echo "💾" > public/app_icon.txt
    }
    
    # Copy PNG as ICNS (it won't be a real ICNS but will work as a placeholder)
    cp public/app_icon.png public/app_icon.icns 2>/dev/null
    echo -e "${GREEN}✅ Created fallback icon${NC}"
fi

# STEP 8: COPY ICON TO APP BUNDLE
# ===============================================
# When building your .app bundle, copy the icon to Resources/
# And update Info.plist to reference it

# Copy ICNS to app bundle Resources
if [ -f "public/app_icon.icns" ]; then
    cp "public/app_icon.icns" "$APP_BUNDLE/Contents/Resources/app_icon.icns"
    echo "✅ App icon added to bundle (ICNS)"
elif [ -f "public/app_icon.png" ]; then
    cp "public/app_icon.png" "$APP_BUNDLE/Contents/Resources/app_icon.png"
    echo "✅ App icon added to bundle (PNG)"
fi

# STEP 9: UPDATE INFOPLIST
# ===============================================
# Add CFBundleIconFile key to Info.plist so macOS knows which icon to use
# The value should match the filename without extension

cat > "Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Other keys here -->
    
    <!-- TELL MACOS WHICH ICON FILE TO USE -->
    <key>CFBundleIconFile</key>
    <string>app_icon</string>  <!-- Matches app_icon.icns -->
    
    <!-- More keys here -->
</dict>
</plist>
EOF

# What Each Tool Does:
# Tool	Purpose	macOS Version
# curl	Downloads the image from URL	All
# sips	Resizes images to exact sizes needed	All (built-in)
# iconutil	Converts iconset folder to .icns file	10.7+
# base64	Encodes/decodes base64 data	All
# Required Icon Sizes:
# Size	Use Case
# 16x16	Small icon in lists, menus
# 32x32	Medium icon in Finder
# 64x64	Finder icon (older macOS)
# 128x128	Finder icon (Retina)
# 256x256	Finder icon (Retina)
# 512x512	Finder icon (large)
# 1024x1024	App Store, high-res display