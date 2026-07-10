# AllStarLink / ASL3 Node Backup Script

A small backup setup for AllStarLink ASL3 nodes (tested on Debian 12 / ASL3, including
appliance-style hardware such as thin clients using eMMC storage). It keeps versioned local
backups of your node's configuration and pushes them off-box to a second machine or NAS, so a
dead drive doesn't take your node configuration with it.

This isn't a knock on any particular hardware's reliability — it's cheap insurance regardless of
how durable the storage is, because hardware failure is only one of several ways a node's config
can disappear (bad update, fat-fingered edit, unclean shutdown corrupting the filesystem, wanting
to move to new hardware, etc.).

## What it backs up

- `/etc/allmon3` — Allmon3 config
- `/etc/asterisk` — rpt.conf, iax.conf, extensions.conf, manager.conf, and any SIP/PJSIP config
  for phones or private nodes. This is the directory that matters most: it holds your node's
  identity, registration secret, DTMF/CW settings, and any private-node/phone configuration.
- `/usr/share/asterisk/agi-bin`
- `/var/www/html`
- `/etc/allscan` (if present) — if you run [AllScan](https://github.com/davidgsd/AllScan), its own
  database (`allscan.db`) lives here, separate from the AllScan web app files under
  `/var/www/html/allscan/`. It holds your admin/user accounts, all Cfgs page settings, and
  `asdb.txt` if you use it for private-node descriptions. Easy to miss since the web files and the
  database live in two different places.
- `/var/lib/asterisk/astdb.sqlite3` (AstDB — node connection state, DTMF-set permissions, etc.),
  captured with `sqlite3 .backup` first so a live write mid-backup can't corrupt the copy
- Root's and your user's crontabs, plus a list of installed asl3/allmon3/asterisk packages —
  reference info for a rebuild, not strictly required to restore

## Requirements

- `rdiff-backup` and `sqlite3` installed (`sudo apt install -y rdiff-backup sqlite3`)
- A second machine or NAS reachable over SSH from the node (a LAN-only destination is fine)
- Passwordless SSH key auth from the node to that destination (see below)

## Setup

1. **Edit the script.** Open `backup-asterisk-node.sh` and set:
   ```
   REMOTE_HOST="user@your-backup-host"
   REMOTE_PATH="/path/on/remote/host/node-backups"
   ```
   `REMOTE_PATH` must already exist on the destination.

2. **Set up passwordless SSH.** Since the script runs the rsync step under `sudo`, generate a key
   for root and copy it to the destination account:
   ```
   sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
   sudo ssh-copy-id -i /root/.ssh/id_ed25519.pub user@your-backup-host
   sudo ssh user@your-backup-host 'echo ok'   # confirm it connects without a password prompt
   ```

3. **If your destination is a NAS with its own share-level permissions** (e.g. OpenMediaVault,
   Synology, TrueNAS), double check the share's ACL/privileges for that user — not just the
   Unix file permissions. On OpenMediaVault specifically, Storage > Shared Folders > (your
   share) > Privileges is a separate permission layer from the underlying filesystem
   permissions, and a share can show as empty over SMB even when the files exist on disk if
   that ACL isn't set to Read/Write for your user.

4. **Test it by hand first:**
   ```
   sudo bash backup-asterisk-node.sh
   ```
   Confirm the destination actually received the files before relying on it.

5. **Schedule it.** Weekly is plenty for a node that doesn't change often:
   ```
   sudo crontab -e
   ```
   ```
   0 3 * * 0 /path/to/backup-asterisk-node.sh >> /var/log/asl-backup.log 2>&1
   ```
   That runs every Sunday at 3 AM. Check the log after the first automatic run.

## Restoring onto new hardware

1. Do a fresh ASL3 install and get the node network-reachable.
2. Stop the `asterisk` and `allmon3` services.
3. Copy the backup set from your remote destination back onto the new machine.
4. Restore each rdiff-backup archive to its live location:
   ```
   sudo rdiff-backup --restore-as-of now <backup>/asterisk  /etc/asterisk
   sudo rdiff-backup --restore-as-of now <backup>/allmon3   /etc/allmon3
   sudo rdiff-backup --restore-as-of now <backup>/agi-bin   /usr/share/asterisk/agi-bin
   sudo rdiff-backup --restore-as-of now <backup>/html      /var/www/html
   sudo rdiff-backup --restore-as-of now <backup>/allscan   /etc/allscan   # if you use AllScan
   sudo rdiff-backup --restore-as-of now <backup>/astdb     /var/lib/asterisk
   ```
5. Check file ownership afterward (`ls -la`) — Asterisk expects some paths owned by
   `asterisk:asterisk`, and copies can occasionally land with different ownership.
6. Restart `asterisk` and `allmon3`, and confirm the node registers normally.

## Gotchas learned the hard way

- Edit the script with Unix line endings (LF only). Windows/CRLF line endings break bash parsing
  with cryptic errors like `invalid option name`. If that happens, fix with:
  `sed -i 's/\r$//' backup-asterisk-node.sh`
- `sqlite3` (the CLI tool used here) and `php-sqlite3` (a PHP extension some AllStarLink web
  tools use) are separate packages that share an underlying library — installing one doesn't
  affect the other.
- If a freshly-pushed backup folder shows up empty when browsing over a network share, it's
  often just a stale client-side cache — refresh or remount before assuming something's broken.

## License

MIT — see [LICENSE](./LICENSE). Use, adapt, and share freely.
