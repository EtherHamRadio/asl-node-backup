#!/bin/bash
set -euo pipefail

# ============================================================
# ASL3 / AllStarLink node backup
#
# Keeps versioned local backups (via rdiff-backup) of your node's
# configuration, then pushes them off-box over SSH to a second
# machine or NAS, so a dead SD card / eMMC / drive doesn't take
# your node configuration down with it.
#
# EDIT THESE TWO LINES FOR YOUR SETUP:
# ============================================================
REMOTE_HOST="user@your-backup-host"       # SSH user@host of your NAS or second machine
REMOTE_PATH="/path/on/remote/host/node-backups"   # destination dir there (must exist)

BACKUP_DIR="/etc/backups"

# ------------------------------------------------------------
# 1. Local versioned backups (rdiff-backup keeps history so you
#    can roll back to any prior run, not just the latest)
# ------------------------------------------------------------
sudo rdiff-backup /etc/allmon3 "$BACKUP_DIR/allmon3"
sudo rdiff-backup /etc/asterisk "$BACKUP_DIR/asterisk"
sudo rdiff-backup /usr/share/asterisk/agi-bin "$BACKUP_DIR/agi-bin"
sudo rdiff-backup /var/www/html "$BACKUP_DIR/html"

# If you use AllScan (davidgsd/AllScan), its own database (accounts, Cfgs
# settings, and any /etc/allscan/asdb.txt private-node descriptions) lives
# here, separate from the AllScan web files already covered by /var/www/html.
if [ -d /etc/allscan ]; then
    sudo rdiff-backup /etc/allscan "$BACKUP_DIR/allscan"
fi

# ------------------------------------------------------------
# 2. AstDB — take a consistent sqlite snapshot, then version it.
#    rdiff-backup only backs up directories, not single files, so
#    the snapshot is written into its own folder first.
#    CONFIRM THE PATH ON YOUR SYSTEM: sudo find /var/lib/asterisk -iname '*astdb*'
#    Requires the `sqlite3` CLI package (apt install sqlite3).
# ------------------------------------------------------------
ASTDB_SRC="/var/lib/asterisk/astdb.sqlite3"
if [ -f "$ASTDB_SRC" ]; then
    sudo mkdir -p /tmp/astdb_snapshot
    sudo sqlite3 "$ASTDB_SRC" ".backup '/tmp/astdb_snapshot/astdb.sqlite3'"
    sudo rdiff-backup /tmp/astdb_snapshot "$BACKUP_DIR/astdb"
    sudo rm -rf /tmp/astdb_snapshot
else
    echo "WARNING: astdb not found at $ASTDB_SRC — update ASTDB_SRC in this script" >&2
fi

# ------------------------------------------------------------
# 3. Crontabs + installed package list (handy reference on a rebuild)
# ------------------------------------------------------------
sudo mkdir -p "$BACKUP_DIR/system"
sudo crontab -l 2>/dev/null > "$BACKUP_DIR/system/root-crontab.txt" || true
crontab -l 2>/dev/null > "$BACKUP_DIR/system/user-crontab.txt" || true
dpkg -l | grep -E 'asl3|allmon3|asterisk' > "$BACKUP_DIR/system/asl-packages.txt"

# ------------------------------------------------------------
# 4. Push the whole backup repo off this box.
#    Requires passwordless SSH key auth to REMOTE_HOST — see the
#    README for setup steps.
# ------------------------------------------------------------
sudo rsync -a --delete "$BACKUP_DIR"/ "$REMOTE_HOST:$REMOTE_PATH"/
