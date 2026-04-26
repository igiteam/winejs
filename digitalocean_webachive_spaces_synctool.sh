#!/bin/bash

# Web Archive Sync Tool - DigitalOcean Spaces Edition
# Syncs local archives to DigitalOcean Spaces with CDN cache clearing
# Run with: curl -o web-archive-sync.sh https://yourdomain.com/web-archive-sync.sh && chmod +x web-archive-sync.sh && sudo ./web-archive-sync.sh

set -e  # Exit on any error

# ============================================
# Configuration
# ============================================
PROJECT_NAME="web-archive-sync"
PROJECT_DIR="/opt/$PROJECT_NAME"
LOG_FILE="/var/log/$PROJECT_NAME/sync-$(date +%Y%m%d-%H%M%S).log"
ENV_FILE="/etc/$PROJECT_NAME/.env"
SYNC_DIRS=()  # Will be populated from .env
BACKUP_DIR="/var/backups/$PROJECT_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# Helper Functions
# ============================================
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        return 1
    fi
    return 0
}

# ============================================
# Load Environment Variables
# ============================================
load_env() {
    if [ -f "$ENV_FILE" ]; then
        log "Loading configuration from $ENV_FILE"
        source "$ENV_FILE"
    else
        error "Environment file $ENV_FILE not found! Please create it first."
    fi
    
    # Required variables check
    REQUIRED_VARS=("DO_SPACES_KEY" "DO_SPACES_SECRET" "DO_SPACES_BUCKET" "DO_SPACES_ENDPOINT" "DO_CDN_ENDPOINT" "DO_API_TOKEN" "SYNC_PATHS")
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required variable $var is not set in $ENV_FILE"
        fi
    done
    
    # Parse SYNC_PATHS into array
    IFS=',' read -ra SYNC_DIRS <<< "$SYNC_PATHS"
    
    log "Configuration loaded successfully"
    log "Sync paths: ${SYNC_DIRS[*]}"
    log "Bucket: $DO_SPACES_BUCKET"
    log "CDN: $DO_CDN_ENDPOINT"
}

# ============================================
# Create Environment Template
# ============================================
create_env_template() {
    local env_dir=$(dirname "$ENV_FILE")
    mkdir -p "$env_dir"
    
    if [ ! -f "$ENV_FILE" ]; then
        cat > "$ENV_FILE" << 'EOF'
# DigitalOcean Spaces Configuration
# Get these from: https://cloud.digitalocean.com/account/api/tokens
# Spaces: https://cloud.digitalocean.com/spaces

# Spaces Access Credentials
DO_SPACES_KEY="your_spaces_access_key_here"
DO_SPACES_SECRET="your_spaces_secret_key_here"
DO_SPACES_BUCKET="your-bucket-name"
DO_SPACES_ENDPOINT="https://nyc3.digitaloceanspaces.com"
DO_SPACES_REGION="us-east-1"  # or your region

# CDN Configuration (optional but recommended)
DO_CDN_ENDPOINT="https://your-cdn-endpoint.com"
DO_API_TOKEN="your_do_api_token_with_cdn_permissions"
DO_CDN_ID=""  # Will be auto-detected if empty

# Sync Configuration
# Comma-separated list of directories to sync
SYNC_PATHS="/var/www/html,/home/user/archives,/opt/data"

# Sync Settings
SYNC_DELETE_REMOTE=false  # Set to true to delete files in spaces that don't exist locally
SYNC_DRY_RUN=false        # Set to true to test without actually uploading
SYNC_PARALLEL=4           # Number of parallel uploads
SYNC_EXCLUDE_PATTERNS="*.tmp,*.log,.git,node_modules"  # Comma-separated patterns to exclude

# File Settings
MAKE_PUBLIC=true          # Make uploaded files publicly readable
CACHE_CONTROL="public, max-age=31536000"  # Cache control header
METADATA_PREFIX="x-amz-meta-"  # Metadata prefix

# Backup Settings
BACKUP_BEFORE_SYNC=true   # Create local backup before syncing
BACKUP_RETENTION_DAYS=30  # Days to keep backups
EOF
        chmod 600 "$ENV_FILE"
        log "Created environment template at $ENV_FILE"
        log "Please edit this file with your credentials before running again"
        exit 0
    fi
}

# ============================================
# Install Dependencies
# ============================================
install_dependencies() {
    section "Installing Dependencies"
    
    log "Updating package list..."
    apt-get update -y
    
    log "Installing required packages..."
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        git \
        wget \
        curl \
        zip \
        unzip \
        rsync \
        screen \
        tmux \
        pv \
        jq \
        bc \
        awscli \
        parallel
    
    # Install Python packages for S3 operations
    pip3 install --upgrade pip
    pip3 install boto3 requests python-dotenv
    
    log "✅ Dependencies installed"
}

# ============================================
# Setup Project Structure
# ============================================
setup_project() {
    section "Setting Up Project Structure"
    
    mkdir -p "$PROJECT_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
    
    # Create sync script
    cat > "$PROJECT_DIR/sync.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Web Archive Sync Tool - DigitalOcean Spaces Sync Script
"""

import os
import sys
import json
import hashlib
import logging
import argparse
from pathlib import Path
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Optional, Tuple

import boto3
from botocore.exceptions import ClientError
from botocore.config import Config
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/web-archive-sync/sync.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DigitalOceanSpacesSync:
    """DigitalOcean Spaces sync manager with CDN cache clearing"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.spaces_client = None
        self.cdn_endpoint = config.get('cdn_endpoint')
        self.api_token = config.get('api_token')
        self.cdn_id = config.get('cdn_id')
        self.bucket = config['bucket']
        
        # Initialize S3 client for Spaces
        self._init_spaces_client()
        
        # Auto-detect CDN ID if needed
        if self.cdn_endpoint and self.api_token and not self.cdn_id:
            self.cdn_id = self._detect_cdn_id()
            if self.cdn_id:
                logger.info(f"Auto-detected CDN ID: {self.cdn_id}")
    
    def _init_spaces_client(self):
        """Initialize DigitalOcean Spaces client"""
        session = boto3.session.Session()
        self.spaces_client = session.client(
            's3',
            region_name=self.config.get('region', 'us-east-1'),
            endpoint_url=self.config['endpoint'],
            aws_access_key_id=self.config['access_key'],
            aws_secret_access_key=self.config['secret_key'],
            config=Config(
                signature_version='s3v4',
                retries={'max_attempts': 3}
            )
        )
    
    def _detect_cdn_id(self) -> Optional[str]:
        """Auto-detect CDN endpoint ID from bucket"""
        try:
            response = requests.get(
                'https://api.digitalocean.com/v2/cdn/endpoints',
                headers={'Authorization': f'Bearer {self.api_token}'}
            )
            response.raise_for_status()
            data = response.json()
            
            for endpoint in data.get('endpoints', []):
                if endpoint.get('origin', '').startswith(self.bucket + '.'):
                    return endpoint.get('id')
            return None
        except Exception as e:
            logger.warning(f"Failed to detect CDN ID: {e}")
            return None
    
    def clear_cdn_cache(self, paths: List[str]) -> bool:
        """Clear CDN cache for specific paths"""
        if not self.api_token or not self.cdn_id:
            logger.warning("CDN credentials not configured, skipping cache clear")
            return False
        
        try:
            # DigitalOcean CDN cache purge API
            response = requests.delete(
                f'https://api.digitalocean.com/v2/cdn/endpoints/{self.cdn_id}/cache',
                headers={
                    'Authorization': f'Bearer {self.api_token}',
                    'Content-Type': 'application/json'
                },
                json={'files': paths}
            )
            
            if response.status_code in [200, 204]:
                logger.info(f"✅ CDN cache cleared for {len(paths)} paths")
                return True
            else:
                logger.warning(f"CDN cache clear failed: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"Error clearing CDN cache: {e}")
            return False
    
    def get_file_hash(self, filepath: Path) -> str:
        """Calculate MD5 hash of file"""
        hash_md5 = hashlib.md5()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    
    def file_exists_in_spaces(self, key: str, local_hash: str) -> bool:
        """Check if file exists in Spaces and has matching hash"""
        try:
            response = self.spaces_client.head_object(
                Bucket=self.bucket,
                Key=key
            )
            
            # Check ETag matches
            etag = response.get('ETag', '').strip('"')
            return etag == local_hash
            
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                return False
            else:
                logger.error(f"Error checking file {key}: {e}")
                return False
    
    def upload_file(self, local_path: Path, remote_key: str, dry_run: bool = False) -> Tuple[bool, str]:
        """Upload single file to Spaces"""
        if dry_run:
            logger.info(f"[DRY RUN] Would upload: {local_path} -> {remote_key}")
            return True, "dry_run"
        
        try:
            # Get file hash for ETag
            file_hash = self.get_file_hash(local_path)
            
            # Check if file already exists and matches
            if self.file_exists_in_spaces(remote_key, file_hash):
                logger.debug(f"File unchanged, skipping: {remote_key}")
                return True, "skipped"
            
            # Prepare upload arguments
            extra_args = {
                'ACL': 'public-read' if self.config.get('make_public', True) else 'private',
                'CacheControl': self.config.get('cache_control', 'public, max-age=31536000'),
                'Metadata': {
                    'uploaded-by': 'web-archive-sync',
                    'uploaded-at': datetime.utcnow().isoformat(),
                    'original-path': str(local_path)
                }
            }
            
            # Set content type based on extension
            ext = local_path.suffix.lower()
            content_types = {
                '.html': 'text/html',
                '.css': 'text/css',
                '.js': 'application/javascript',
                '.json': 'application/json',
                '.png': 'image/png',
                '.jpg': 'image/jpeg',
                '.jpeg': 'image/jpeg',
                '.gif': 'image/gif',
                '.svg': 'image/svg+xml',
                '.pdf': 'application/pdf',
                '.zip': 'application/zip',
                '.mp4': 'video/mp4',
                '.mp3': 'audio/mpeg'
            }
            extra_args['ContentType'] = content_types.get(ext, 'application/octet-stream')
            
            # Upload file
            with open(local_path, 'rb') as f:
                self.spaces_client.upload_fileobj(
                    f,
                    self.bucket,
                    remote_key,
                    ExtraArgs=extra_args
                )
            
            logger.info(f"✅ Uploaded: {remote_key}")
            return True, "uploaded"
            
        except Exception as e:
            logger.error(f"Failed to upload {remote_key}: {e}")
            return False, str(e)
    
    def sync_directory(self, local_dir: Path, remote_prefix: str, dry_run: bool = False) -> Dict:
        """Sync entire directory to Spaces"""
        stats = {
            'total': 0,
            'uploaded': 0,
            'skipped': 0,
            'failed': 0,
            'failed_files': []
        }
        
        # Collect all files to sync
        files_to_sync = []
        exclude_patterns = self.config.get('exclude_patterns', [])
        
        for filepath in local_dir.rglob('*'):
            if not filepath.is_file():
                continue
            
            # Check exclude patterns
            should_exclude = False
            for pattern in exclude_patterns:
                if pattern in str(filepath):
                    should_exclude = True
                    break
            
            if should_exclude:
                continue
            
            # Calculate remote key
            relative_path = filepath.relative_to(local_dir)
            remote_key = f"{remote_prefix}/{relative_path}" if remote_prefix else str(relative_path)
            remote_key = remote_key.replace('\\', '/')  # Normalize path
            
            files_to_sync.append((filepath, remote_key))
            stats['total'] += 1
        
        logger.info(f"Found {stats['total']} files to sync")
        
        # Sync files with parallel uploads
        max_workers = self.config.get('parallel_uploads', 4)
        uploaded_paths = []
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(self.upload_file, filepath, remote_key, dry_run): (filepath, remote_key)
                for filepath, remote_key in files_to_sync
            }
            
            for future in as_completed(futures):
                filepath, remote_key = futures[future]
                try:
                    success, result = future.result()
                    if success:
                        if result == 'uploaded':
                            stats['uploaded'] += 1
                            uploaded_paths.append(remote_key)
                        elif result == 'skipped':
                            stats['skipped'] += 1
                    else:
                        stats['failed'] += 1
                        stats['failed_files'].append(str(filepath))
                except Exception as e:
                    logger.error(f"Upload failed for {filepath}: {e}")
                    stats['failed'] += 1
                    stats['failed_files'].append(str(filepath))
        
        # Clear CDN cache for uploaded files
        if uploaded_paths and not dry_run:
            logger.info(f"Clearing CDN cache for {len(uploaded_paths)} files...")
            self.clear_cdn_cache(uploaded_paths)
        
        return stats
    
    def delete_remote_files(self, remote_prefix: str, local_files: set, dry_run: bool = False) -> List[str]:
        """Delete files from Spaces that don't exist locally"""
        deleted_files = []
        
        try:
            # List all files in remote prefix
            paginator = self.spaces_client.get_paginator('list_objects_v2')
            pages = paginator.paginate(Bucket=self.bucket, Prefix=remote_prefix)
            
            for page in pages:
                if 'Contents' not in page:
                    continue
                
                for obj in page['Contents']:
                    remote_key = obj['Key']
                    
                    # Extract local path from remote key
                    local_path = remote_key.replace(remote_prefix + '/', '')
                    if local_path not in local_files:
                        if dry_run:
                            logger.info(f"[DRY RUN] Would delete: {remote_key}")
                        else:
                            self.spaces_client.delete_object(Bucket=self.bucket, Key=remote_key)
                            logger.info(f"🗑️ Deleted: {remote_key}")
                        deleted_files.append(remote_key)
            
            # Clear CDN cache for deleted files
            if deleted_files and not dry_run:
                self.clear_cdn_cache(deleted_files)
                
        except Exception as e:
            logger.error(f"Error during remote cleanup: {e}")
        
        return deleted_files

def main():
    parser = argparse.ArgumentParser(description='Web Archive Sync Tool')
    parser.add_argument('--dry-run', action='store_true', help='Simulate sync without uploading')
    parser.add_argument('--delete-remote', action='store_true', help='Delete remote files not in local')
    parser.add_argument('--path', help='Specific path to sync (overrides config)')
    parser.add_argument('--parallel', type=int, help='Number of parallel uploads')
    
    args = parser.parse_args()
    
    # Load configuration from environment
    config = {
        'access_key': os.getenv('DO_SPACES_KEY'),
        'secret_key': os.getenv('DO_SPACES_SECRET'),
        'bucket': os.getenv('DO_SPACES_BUCKET'),
        'endpoint': os.getenv('DO_SPACES_ENDPOINT'),
        'region': os.getenv('DO_SPACES_REGION', 'us-east-1'),
        'cdn_endpoint': os.getenv('DO_CDN_ENDPOINT'),
        'api_token': os.getenv('DO_API_TOKEN'),
        'cdn_id': os.getenv('DO_CDN_ID'),
        'make_public': os.getenv('MAKE_PUBLIC', 'true').lower() == 'true',
        'cache_control': os.getenv('CACHE_CONTROL', 'public, max-age=31536000'),
        'parallel_uploads': int(os.getenv('SYNC_PARALLEL', '4')),
        'exclude_patterns': os.getenv('SYNC_EXCLUDE_PATTERNS', '').split(',')
    }
    
    # Validate required config
    if not all([config['access_key'], config['secret_key'], config['bucket'], config['endpoint']]):
        logger.error("Missing required configuration. Check environment variables.")
        sys.exit(1)
    
    # Get sync paths
    sync_paths = args.path.split(',') if args.path else os.getenv('SYNC_PATHS', '').split(',')
    sync_paths = [p.strip() for p in sync_paths if p.strip()]
    
    if not sync_paths:
        logger.error("No sync paths specified")
        sys.exit(1)
    
    # Override parallel if specified
    if args.parallel:
        config['parallel_uploads'] = args.parallel
    
    # Initialize sync client
    sync_client = DigitalOceanSpacesSync(config)
    
    # Sync each directory
    total_stats = {
        'total': 0,
        'uploaded': 0,
        'skipped': 0,
        'failed': 0
    }
    
    for sync_path in sync_paths:
        local_dir = Path(sync_path)
        if not local_dir.exists():
            logger.warning(f"Path does not exist: {sync_path}")
            continue
        
        # Use basename as remote prefix, or custom mapping
        remote_prefix = os.getenv(f'REMOTE_PREFIX_{sync_path.replace("/", "_")}', local_dir.name)
        
        logger.info(f"\n{'='*60}")
        logger.info(f"Syncing: {local_dir} -> {remote_prefix}")
        logger.info(f"{'='*60}")
        
        # Sync directory
        stats = sync_client.sync_directory(local_dir, remote_prefix, args.dry_run)
        
        # Delete remote files if requested
        if args.delete_remote and not args.dry_run:
            # Collect local files
            local_files = set()
            for filepath in local_dir.rglob('*'):
                if filepath.is_file():
                    relative = filepath.relative_to(local_dir)
                    local_files.add(str(relative))
            
            # Delete remote files not in local
            deleted = sync_client.delete_remote_files(remote_prefix, local_files, args.dry_run)
            logger.info(f"Deleted {len(deleted)} remote files")
        
        # Update totals
        for key in total_stats:
            total_stats[key] += stats.get(key, 0)
        
        logger.info(f"\nStats for {sync_path}:")
        logger.info(f"  Total: {stats['total']}")
        logger.info(f"  Uploaded: {stats['uploaded']}")
        logger.info(f"  Skipped: {stats['skipped']}")
        logger.info(f"  Failed: {stats['failed']}")
        
        if stats['failed_files']:
            logger.warning(f"Failed files: {stats['failed_files'][:10]}")
    
    # Summary
    logger.info(f"\n{'='*60}")
    logger.info("SYNC COMPLETE")
    logger.info(f"{'='*60}")
    logger.info(f"Total files processed: {total_stats['total']}")
    logger.info(f"Files uploaded: {total_stats['uploaded']}")
    logger.info(f"Files skipped: {total_stats['skipped']}")
    logger.info(f"Files failed: {total_stats['failed']}")
    
    # Return exit code based on failures
    sys.exit(0 if total_stats['failed'] == 0 else 1)

if __name__ == '__main__':
    main()
PYEOF
    
    chmod +x "$PROJECT_DIR/sync.py"
    
    # Create cron job script
    cat > "$PROJECT_DIR/cron-sync.sh" << 'CRONEOF'
#!/bin/bash
# Cron job for automatic sync
# Add to crontab: 0 2 * * * /opt/web-archive-sync/cron-sync.sh >> /var/log/web-archive-sync/cron.log 2>&1

export $(cat /etc/web-archive-sync/.env | xargs)
cd /opt/web-archive-sync
python3 sync.py >> /var/log/web-archive-sync/cron.log 2>&1
CRONEOF
    
    chmod +x "$PROJECT_DIR/cron-sync.sh"
    
    # Create status script
    cat > /usr/local/bin/archive-sync-status << 'STATUSEOF'
#!/bin/bash
echo "=== Web Archive Sync Status ==="
echo ""
echo "Last sync log:"
tail -20 /var/log/web-archive-sync/sync.log
echo ""
echo "Recent errors:"
grep ERROR /var/log/web-archive-sync/sync.log | tail -5
echo ""
echo "Space usage:"
du -sh /var/www/html/* 2>/dev/null || echo "No web directories found"
echo ""
echo "Backups:"
ls -lh /var/backups/web-archive-sync/ 2>/dev/null | tail -5
STATUSEOF
    
    chmod +x /usr/local/bin/archive-sync-status
    
    log "✅ Project structure created at $PROJECT_DIR"
}

# ============================================
# Create Backup
# ============================================
create_backup() {
    if [ "$BACKUP_BEFORE_SYNC" != "true" ]; then
        return
    fi
    
    section "Creating Local Backup"
    
    BACKUP_NAME="pre-sync-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
    
    # Create list of paths to backup
    BACKUP_PATHS=""
    for path in "${SYNC_DIRS[@]}"; do
        if [ -e "$path" ]; then
            BACKUP_PATHS="$BACKUP_PATHS $path"
        fi
    done
    
    if [ -n "$BACKUP_PATHS" ]; then
        log "Creating backup: $BACKUP_PATH"
        tar -czf "$BACKUP_PATH" $BACKUP_PATHS 2>/dev/null || warning "Backup failed for some paths"
        log "✅ Backup created: $BACKUP_NAME"
        
        # Clean old backups
        find "$BACKUP_DIR" -name "pre-sync-backup-*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
        log "Cleaned backups older than $BACKUP_RETENTION_DAYS days"
    else
        warning "No valid paths to backup"
    fi
}

# ============================================
# Run Sync
# ============================================
run_sync() {
    section "Running Archive Sync"
    
    cd "$PROJECT_DIR"
    
    # Build sync command
    SYNC_CMD="python3 sync.py"
    
    if [ "$SYNC_DRY_RUN" = "true" ]; then
        SYNC_CMD="$SYNC_CMD --dry-run"
        log "DRY RUN MODE - No files will be uploaded"
    fi
    
    if [ "$SYNC_DELETE_REMOTE" = "true" ]; then
        SYNC_CMD="$SYNC_CMD --delete-remote"
        log "Delete remote files mode enabled"
    fi
    
    # Set environment
    export DO_SPACES_KEY DO_SPACES_SECRET DO_SPACES_BUCKET DO_SPACES_ENDPOINT
    export DO_SPACES_REGION DO_CDN_ENDPOINT DO_API_TOKEN DO_CDN_ID
    export SYNC_PARALLEL SYNC_EXCLUDE_PATTERNS MAKE_PUBLIC CACHE_CONTROL
    
    # Run sync
    log "Starting sync process..."
    log "Command: $SYNC_CMD"
    
    if $SYNC_CMD; then
        log "✅ Sync completed successfully"
        
        # Generate sync report
        cat > "$PROJECT_DIR/sync-report-$(date +%Y%m%d-%H%M%S).txt" << REPORT
Web Archive Sync Report
Date: $(date)
Sync Mode: $([ "$SYNC_DRY_RUN" = "true" ] && echo "DRY RUN" || echo "LIVE")
Delete Remote: $SYNC_DELETE_REMOTE
Parallel Uploads: $SYNC_PARALLEL

Paths Synced:
$(printf '%s\n' "${SYNC_DIRS[@]}")

CDN: $DO_CDN_ENDPOINT
Bucket: $DO_SPACES_BUCKET
REPORT
        log "Sync report saved"
    else
        error "Sync failed with errors"
    fi
}

# ============================================
# Test Connection
# ============================================
test_connection() {
    section "Testing DigitalOcean Spaces Connection"
    
    cd "$PROJECT_DIR"
    
    # Simple test upload
    TEST_FILE="/tmp/test-upload-$(date +%s).txt"
    echo "Test file created at $(date)" > "$TEST_FILE"
    
    export DO_SPACES_KEY DO_SPACES_SECRET DO_SPACES_BUCKET DO_SPACES_ENDPOINT
    
    log "Testing upload to Spaces..."
    if python3 -c "
import boto3
import os

try:
    session = boto3.session.Session()
    client = session.client(
        's3',
        region_name='${DO_SPACES_REGION:-us-east-1}',
        endpoint_url='$DO_SPACES_ENDPOINT',
        aws_access_key_id='$DO_SPACES_KEY',
        aws_secret_access_key='$DO_SPACES_SECRET'
    )
    
    # Test upload
    with open('$TEST_FILE', 'rb') as f:
        client.upload_fileobj(f, '$DO_SPACES_BUCKET', 'test-connection.txt')
    
    # Test listing
    response = client.list_objects_v2(Bucket='$DO_SPACES_BUCKET', MaxKeys=1)
    print('Connection successful')
    
except Exception as e:
    print(f'Connection failed: {e}')
    exit(1)
"; then
        log "✅ Spaces connection successful"
        
        # Test CDN if configured
        if [ -n "$DO_CDN_ENDPOINT" ] && [ -n "$DO_API_TOKEN" ]; then
            log "Testing CDN connection..."
            if curl -s -f -I "$DO_CDN_ENDPOINT/test-connection.txt" > /dev/null; then
                log "✅ CDN connection successful"
            else
                warning "CDN endpoint not accessible"
            fi
        fi
    else
        error "Spaces connection failed"
    fi
    
    rm -f "$TEST_FILE"
}

# ============================================
# Main Script
# ============================================
clear
echo ""
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║      Web Archive Sync Tool - DigitalOcean Spaces Edition     ║"
echo "║                                                               ║"
echo "║      Features:                                                ║"
echo "║      • Sync multiple directories to Spaces                    ║"
echo "║      • CDN cache auto-clearing                                ║"
echo "║      • Parallel uploads for speed                             ║"
echo "║      • File change detection (skip unchanged)                 ║"
echo "║      • Backup before sync                                     ║"
echo "║      • Cron job automation                                    ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (use sudo)"
fi

# Parse arguments
case "$1" in
    --setup)
        install_dependencies
        setup_project
        create_env_template
        ;;
    --test)
        load_env
        test_connection
        ;;
    --sync)
        load_env
        create_backup
        run_sync
        ;;
    --cron)
        load_env
        run_sync
        ;;
    --status)
        /usr/local/bin/archive-sync-status
        ;;
    --configure)
        ${EDITOR:-nano} "$ENV_FILE"
        ;;
    *)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --setup      Install dependencies and setup project"
        echo "  --test       Test Spaces and CDN connection"
        echo "  --sync       Run sync (respects .env settings)"
        echo "  --cron       Run sync for cron jobs"
        echo "  --status     Show sync status"
        echo "  --configure  Edit configuration file"
        echo ""
        echo "First run: $0 --setup"
        echo "Then edit: $0 --configure"
        echo "Then test: $0 --test"
        echo "Then sync: $0 --sync"
        ;;
esac

# ============================================
# Usage Examples
# ============================================
# 
# 1. Initial setup:
#    sudo ./web-archive-sync.sh --setup
# 
# 2. Edit configuration:
#    sudo ./web-archive-sync.sh --configure
# 
# 3. Test connection:
#    sudo ./web-archive-sync.sh --test
# 
# 4. Run sync:
#    sudo ./web-archive-sync.sh --sync
# 
# 5. Setup automatic sync (crontab -e):
#    0 2 * * * /opt/web-archive-sync/cron-sync.sh
# 
# 6. Check status:
#    archive-sync-status
# 
# Environment variables in /etc/web-archive-sync/.env:
# - DO_SPACES_KEY: Your Spaces access key
# - DO_SPACES_SECRET: Your Spaces secret key
# - DO_SPACES_BUCKET: Your bucket name
# - DO_SPACES_ENDPOINT: Spaces endpoint (e.g., https://nyc3.digitaloceanspaces.com)
# - DO_CDN_ENDPOINT: Your CDN endpoint URL
# - DO_API_TOKEN: DigitalOcean API token (for CDN cache clearing)
# - SYNC_PATHS: Comma-separated list of directories to sync
# - SYNC_PARALLEL: Number of parallel uploads (default: 4)
# - SYNC_EXCLUDE_PATTERNS: Patterns to exclude (comma-separated)
# 
# ============================================

# Key Features:
#     Environment Variables Management
#         All sensitive data stored in /etc/web-archive-sync/.env
#         Auto-loads variables for the sync process
#         Template creation with --setup
#     DigitalOcean Spaces Integration
#         Full S3-compatible API support via boto3
#         Parallel uploads for speed
#         File change detection (skip unchanged files)
#         ETag-based verification
#     CDN Cache Clearing
#         Auto-detects CDN ID from bucket
#         Purges cache for uploaded/deleted files
#         Uses DigitalOcean API for cache invalidation
#     Sync Features
#         Multiple directory sync support
#         Exclude patterns for unwanted files
#         Dry-run mode for testing
#         Delete remote files option
#         Backup before sync
#     Operational Tools
#         Connection testing
#         Status reporting
#         Cron job automation
#         Detailed logging

# Setup Instructions:
#     Initial Setup:
#     sudo ./web-archive-sync.sh --setup

#     Configure Credentials:
#     sudo ./web-archive-sync.sh --configure
#
#     Edit the file with your:
#         Spaces Access Key/Secret
#         Bucket name
#         CDN endpoint
#         API token (with CDN permissions)
#         Paths to sync

#     Test Connection:
#     sudo ./web-archive-sync.sh --test

#     Run Sync:
#     sudo ./web-archive-sync.sh --sync

#     Auto-Sync via Cron:
#     crontab -e
#     # Add: 0 2 * * * /opt/web-archive-sync/cron-sync.sh

# Configuration File Example:
# # /etc/web-archive-sync/.env
# DO_SPACES_KEY="your_access_key"
# DO_SPACES_SECRET="your_secret_key"
# DO_SPACES_BUCKET="your-bucket"
# DO_SPACES_ENDPOINT="https://nyc3.digitaloceanspaces.com"
# DO_CDN_ENDPOINT="https://your-cdn.com"
# DO_API_TOKEN="your_api_token_with_cdn_permissions"
# SYNC_PATHS="/var/www/html,/home/user/archives"
# SYNC_PARALLEL="4"
# SYNC_EXCLUDE_PATTERNS="*.tmp,.git,node_modules"

# This provides a complete web archive sync solution with DigitalOcean Spaces integration!