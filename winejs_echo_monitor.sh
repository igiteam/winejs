# You give me ANY bash script, and I'll give you back:
# ============= ECHO_MONITOR_HOOK =============
# [auto-generated progress patterns for YOUR specific script]

# It would:
# 1. Parse your script line by line
# 2. Extract all log messages, echo statements, and key commands
# 3. Generate pattern matches for each stage
# 4. Assign intelligent progress percentages
# 5. Add ping triggers at logical milestones
# 6. Output a ready-to-paste monitor hook

# ============= ECHO_MONITOR_PROGRESS_HOOK =============
# Runs in background and watches all output for patterns
# Add this at the VERY TOP of winejs.sh (right after #!/bin/bash)

# Create a named pipe for monitoring
ECHO_MONITOR_PROGRESS_HOOK=$(mktemp -u)
mkfifo "$ECHO_MONITOR_PROGRESS_HOOK"

# Redirect ALL output to both console and the monitor pipe
exec 3>&1 4>&2
exec > >(tee "$ECHO_MONITOR_PROGRESS_HOOK") 2>&1

# Start monitor in background
(
    while read -r line; do
        # Check each line against patterns from your actual script
        case "$line" in
            # CONFIGURATION STAGE (0-5%)
            *"Enter your MAIN domain"*)
                echo "PROGRESS:1:Waiting for domain input" >&3
                ;;
            *"Using domain:"*)
                echo "PROGRESS:2:Domain configured" >&3
                ;;
            *"Detected droplet IP:"*)
                echo "PROGRESS:3:IP detected" >&3
                ;;
            *"DNS is correctly configured"*)
                echo "PROGRESS:4:DNS verified" >&3
                echo "PING:success" >&3
                ;;
            *"Enter email for SSL"*)
                echo "PROGRESS:5:Waiting for email" >&3
                ;;
            *"Enter File-Server Download password"*)
                echo "PROGRESS:6:Waiting for password" >&3
                ;;
            *"Enter 4-digit PIN"*)
                echo "PROGRESS:7:Waiting for PIN" >&3
                ;;
            *"Allowed file extensions"*)
                echo "PROGRESS:8:Configuring extensions" >&3
                ;;
                
            # SYSTEM PREP (5-15%)
            *"Updating system packages"*)
                echo "PROGRESS:5:Starting system update" >&3
                ;;
            *"Installing required tools"*)
                echo "PROGRESS:10:Installing dependencies" >&3
                ;;
                
            # DOCKER (15-25%)
            *"Installing Docker"*)
                echo "PROGRESS:15:Setting up Docker" >&3
                ;;
            *"docker installed successfully"*)
                echo "PROGRESS:20:Docker ready" >&3
                echo "PING:docker" >&3
                ;;
            *"Installing docker-compose"*)
                echo "PROGRESS:22:Adding compose" >&3
                ;;
                
            # WIIMOTE (25-30%)
            *"Adding Nintendo Wiimote support"*)
                echo "PROGRESS:25:Wiimote setup" >&3
                ;;
            *"Wiimote support configured"*)
                echo "PROGRESS:28:Wiimote ready" >&3
                ;;
                
            # NODE/PM2 (30-35%)
            *"Installing Node.js 18 and PM2"*)
                echo "PROGRESS:30:Node.js setup" >&3
                ;;
                
            # SHARED STORAGE (35-40%)
            *"Creating shared storage directory"*)
                echo "PROGRESS:35:Setting up storage" >&3
                ;;
            *"Shared storage created"*)
                echo "PROGRESS:38:Storage ready" >&3
                ;;
                
            # KASMVNC BASE IMAGE (40-55%)
            *"Building KasmVNC base image"*)
                echo "PROGRESS:40:Building base image (this takes 2-3 minutes)" >&3
                ;;
            *"Step 1/"*)
                # Docker build steps - count them for progress
                step_num=$(echo "$line" | grep -o 'Step [0-9]*' | grep -o '[0-9]*')
                if [ -n "$step_num" ]; then
                    # Map step number to progress (roughly 40-55%)
                    prog=$((40 + (step_num * 15 / 30)))
                    echo "PROGRESS:$prog:Building image step $step_num" >&3
                fi
                ;;
            *"Successfully built"*)
                echo "PROGRESS:55:Base image complete" >&3
                echo "PING:build" >&3
                ;;
                
            # MILKSHAPE DOWNLOAD (55-65%)
            *"Installing MilkShape 3D"*)
                echo "PROGRESS:55:Downloading MilkShape" >&3
                ;;
            *"Downloading MilkShape"*)
                echo "PROGRESS:58:Downloading (this may take a moment)" >&3
                ;;
            *"Found executable:"*)
                echo "PROGRESS:62:MilkShape downloaded" >&3
                ;;
            *"Creating launch script"*)
                echo "PROGRESS:64:Configuring MilkShape" >&3
                ;;
                
            # KASMVNC INSTANCE (65-70%)
            *"Creating KasmVNC instance for MilkShape"*)
                echo "PROGRESS:65:Setting up container" >&3
                ;;
            *"Container started"*)
                echo "PROGRESS:68:Container running" >&3
                echo "PING:container" >&3
                ;;
                
            # FILESERVER (70-75%)
            *"Setting up FileServer for DOWNLOADS"*)
                echo "PROGRESS:70:Configuring download portal" >&3
                ;;
            *"FileServer running on port"*)
                echo "PROGRESS:73:Download portal ready" >&3
                ;;
                
            # DUMBDROP (75-80%)
            *"Setting up DumbDrop for UPLOADS"*)
                echo "PROGRESS:75:Configuring upload portal" >&3
                ;;
            *"DumbDrop running on port"*)
                echo "PROGRESS:78:Upload portal ready" >&3
                ;;
                
            # SSL (80-85%)
            *"Setting up SSL certificates"*)
                echo "PROGRESS:80:Requesting SSL certificate" >&3
                ;;
            *"Certificate saved"*)
                echo "PROGRESS:83:SSL ready" >&3
                echo "PING:ssl" >&3
                ;;
                
            # NGINX (85-90%)
            *"Creating nginx configuration"*)
                echo "PROGRESS:85:Configuring web server" >&3
                ;;
            *"nginx configuration file test is successful"*)
                echo "PROGRESS:88:Nginx configured" >&3
                ;;
                
            # HOME PAGE (90-92%)
            *"Creating Windows 10-style home page"*)
                echo "PROGRESS:90:Building dashboard" >&3
                ;;
            *"Windows 10-style home page created"*)
                echo "PROGRESS:92:Dashboard ready" >&3
                ;;
                
            # FINAL STEPS (92-98%)
            *"Creating monitoring script"*)
                echo "PROGRESS:93:Setting up monitoring" >&3
                ;;
            *"Patching KasmVNC"*)
                echo "PROGRESS:95:Applying final tweaks" >&3
                ;;
            *"Background script scheduled"*)
                echo "PROGRESS:97:Finalizing" >&3
                ;;
                
            # COMPLETE (100%)
            *"WINEJS SETUP COMPLETE"*)
                echo "PROGRESS:100:Installation complete!" >&3
                echo "PING:complete" >&3
                echo "PING:complete" >&3
                ;;
            *"Main domain: https://"*)
                # Extract domain from the line
                domain=$(echo "$line" | grep -o 'https://[^ ]*')
                echo "DOMAIN:$domain" >&3
                ;;
                
            # Password captures
            *"Upload: https://"*" (password:"*)
                echo "UPLOAD_INFO:$line" >&3
                ;;
            *"Download: https://"*" (password:"*)
                echo "DOWNLOAD_INFO:$line" >&3
                ;;
            *"MilkShape: https://"*" (VNC pass:"*)
                echo "MILKSHAPE_INFO:$line" >&3
                ;;
        esac
        
        # Also catch any percentage numbers in the wild (like docker build)
        if [[ "$line" =~ ([0-9]+)% ]]; then
            echo "PROGRESS:${BASH_REMATCH[1]}:${line:0:40}" >&3
        fi
    done < "$ECHO_MONITOR_PROGRESS_HOOK"
) &
ECHO_MONITOR_PROGRESS_HOOK_PID=$!

# Cleanup function to kill monitor on exit
cleanup_ECHO_MONITOR_PROGRESS_HOOK() {
    rm -f "$ECHO_MONITOR_PROGRESS_HOOK"
    kill $ECHO_MONITOR_PROGRESS_HOOK_PID 2>/dev/null
}
trap cleanup_ECHO_MONITOR_PROGRESS_HOOK EXIT

# ============= END ECHO_MONITOR_PROGRESS_HOOK =============


# What Makes This Powerful:
#     Zero manual work - just paste your script, get the hook
#     Perfect patterns - matches your exact log messages
#     Smart percentages - weights stages by complexity (Docker builds get more weight than simple mkdir)
#     Auto-detects - finds all your log "Something..." lines and turns them into triggers
#     Milestone detection - spots success messages and adds PINGs automatically

# The Future:
# # Instead of:
# "Hey can you help me add progress to my 2000-line script?"

# # You'd just:
# "Here's my script - generate the ECHO_MONITOR_HOOK for it"

# # And BOOM - instant progress tracking! 🚀

# This is actually brilliant because:
#     Every script has its own unique log messages
#     Manual pattern creation is tedious and error-prone
#     Your idea automates the boring part
#     Makes progress tracking ACCESSIBLE to everyone