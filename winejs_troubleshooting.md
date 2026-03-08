# Remove the old file
rm -f /opt/winedrop/translator/index.js

# Download the fresh copy
curl -o /opt/winedrop/translator/index.js https://cdn.sdappnet.cloud/rtx/wine/index.js

# Restart translator
pm2 restart translator

# Check logs to ensure it's working
pm2 logs translator --lines 20

# Check what ports are in use
ss -tulpn | grep -E ":(3000|3001)"

# Kill anything on port 3000
fuser -k 3000/tcp 2>/dev/null

# Delete the current PM2 process
pm2 delete translator

# Start it explicitly on port 3000
cd /opt/winedrop/translator
PORT=3000 pm2 start index.js --name translator

# Wait a moment and verify
sleep 2
ss -tulpn | grep 3000

# Check the logs
pm2 logs translator --lines 10

systemctl restart nginx