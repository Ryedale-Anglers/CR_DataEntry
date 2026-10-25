# CR_DataEntry database backups: how it all works

*Timeshift (USB stick) deliberately doesn't cover the dumps on Fedora: they're in the home folder, which Timeshift excludes, and Proton Drive is the offsite copy (decided 22 Oct 2026).*

*Set up October 2026 on the Kubuntu laptop (HP 15s). Moved to Fedora 44 KDE on the same laptop on 22 Oct 2026. On Kubuntu the dump was a root system service writing to `/var/backups/cr-dataentry`. On Fedora all three jobs are systemd **user** units, so no `sudo` is needed and SELinux doesn't block them. The Kubuntu timers have been disabled.*

## Installing on a new machine

The unit files, scripts and an env template are in [`deploy/`](deploy/). To install them, run:

```bash
deploy/install.sh                       # copies scripts + units, enables timers and linger
nano ~/.config/cr-dataentry/backup.env  # set DB_URL (= CLOUD_DB_URL_POOLER from .env)
```

The live copies are the ones in `~/.local/bin` and `~/.config/systemd/user`. After changing those, copy the changes back to `deploy/`.

## Overview

The production Supabase (Postgres) database is backed up every day in two layers:

| Layer | What | Where | Kept for |
|---|---|---|---|
| 1. Local dump | `pg_dump` of the public and private schemas | `~/.local/share/cr-dataentry/backups/` on the laptop | 180 days (the script deletes older dumps) |
| 2. Offsite | Proton Drive CLI uploads each new dump | Proton Drive: **My files → Backups → cr-dataentry** | ~7 months (213 days) |

The dump and the upload are **not directly linked**. They share a folder and run 30 minutes apart.

```
13:00  cr-dataentry-etl.timer      (user)
         └─ run_etl_cron.sh ──► reservations ETL to Supabase

15:00  cr-dataentry-backup.timer   (user)
         └─ ~/.local/bin/cr-dataentry-backup.sh
              └─ pg_dump ──► ~/.local/share/cr-dataentry/backups/cr_dataentry_YYYYMMDD_HHMMSS.dump
                   (failure ──► cr-dataentry-backup-failed.service ──► KDE notification)

15:30  cr-dataentry-offsite.timer  (user)
         └─ ~/.local/bin/cr-dataentry-offsite.sh
              ├─ upload new dumps ──► Proton Drive /my-files/Backups/cr-dataentry
              ├─ trash Proton copies uploaded more than 213 days ago
              ├─ refresh the rclone mount so Dolphin sees the new files
              └─ fail if no dump in the last 26 hours
                   (any failure ──► cr-dataentry-offsite-failed.service ──► KDE notification)

```

All three timers have `Persistent=true`, and linger is enabled (`loginctl enable-linger`), so the jobs also run while you're logged out.

---

## 1. The dump: `cr-dataentry-backup`

- **Type:** a user service and timer pair. The script is `~/.local/bin/cr-dataentry-backup.sh` (repo copy: `deploy/bin/`).
- **Connection:** `DB_URL` comes from `~/.config/cr-dataentry/backup.env` (mode 600). It's the Supabase session pooler URL (port 5432), the same value as `CLOUD_DB_URL_POOLER` in the project `.env`.
- **Schedule:** daily at 15:00, plus a random delay of up to 10 minutes (`RandomizedDelaySec=10m`). The timer has `Persistent=true`, so a dump missed while the laptop was off runs at the next boot. Dumps usually finish between 15:03 and 15:10, leaving a margin before the 15:30 upload's 10-minute "still being written" cutoff.
- **Output:** `~/.local/share/cr-dataentry/backups/cr_dataentry_YYYYMMDD_HHMMSS.dump`, about 240 KB each. The directory can be overridden with `BACKUP_DIR`. The 70 Kubuntu dumps (from 30 July 2026) were copied there.
- **Local retention:** the script deletes dumps older than 180 days (`RETENTION_DAYS`). Deleting local dumps never affects the Proton copies.
- **Failure alert:** `OnFailure=cr-dataentry-backup-failed.service` shows a critical KDE notification.
- **Logs:** `journalctl --user -u cr-dataentry-backup`

## 2. The offsite upload: `cr-dataentry-offsite`

### Why it's a *user* service

The Proton Drive CLI stores its login session in the desktop keyring (KWallet, via libsecret). A system service can't read your unlocked KWallet, so the upload runs as a **systemd user unit** inside your login session.

For the same reason it can't be chained to the dump with `OnSuccess=`, because that only works between system units. A fixed 30-minute gap does the job instead.

### Files

| File | Purpose |
|---|---|
| `~/.local/bin/proton-drive` | The official Proton Drive CLI binary |
| `~/.local/bin/cr-dataentry-offsite.sh` | The upload and retention script |
| `~/.local/state/cr-dataentry-offsite/uploaded.tsv` | Log of uploaded files: `filename<TAB>upload-epoch` |
| `~/.config/systemd/user/cr-dataentry-offsite.service` | Oneshot unit that runs the script |
| `~/.config/systemd/user/cr-dataentry-offsite.timer` | Daily 15:30 trigger, `Persistent=true` |
| `~/.config/systemd/user/cr-dataentry-offsite-failed.service` | Desktop notification, triggered by `OnFailure=` when the upload unit fails |

### Behaviour

- **What gets uploaded:** only files not already listed in `uploaded.tsv`, so there's no re-uploading. This keeps within Proton's fair-use policy.
- **Files still being written:** anything modified in the last 10 minutes is skipped.
- **Upload failures:** if an upload fails, the script stops and the unit shows as failed. That file isn't recorded, so it's retried on the next run.
- **Name clashes:** uploads use `--file-conflict-strategy create-new-revision`, so the CLI never stops to prompt. A changed file becomes a new revision and identical files are skipped. Dump names are unique, so this is only a safety net.
- **Missing dumps:** after uploading and trashing, the script fails if no `cr_dataentry_*.dump` has been modified in the last 26 hours. This catches a broken 15:00 dump, which would otherwise look like a successful run with nothing to upload. After a few days with the laptop off, the catch-up run can raise one false alarm if it runs before the catch-up dump has finished. The next run clears it.
- **Failure alerts:** any failure of the unit (upload error, expired Proton login, closed KWallet, missing dump) triggers `cr-dataentry-offsite-failed.service`, which shows a critical KDE notification.
- **Retention:** Proton copies are moved to the **trash** (recoverable with `fs restore`) once they were *uploaded* more than `KEEP_DAYS=213` days ago. The age counts from the upload date, not the dump date.
- **Missed runs:** if the laptop is asleep, off, or logged out at 15:30, the job runs shortly after you next wake it or log in, because of `Persistent=true`. A locked screen doesn't stop it (see "Credentials: KWallet" below).

### The script

```bash
#!/usr/bin/env bash
set -euo pipefail

PD="$HOME/.local/bin/proton-drive"
SRC="${BACKUP_DIR:-$HOME/.local/share/cr-dataentry/backups}"
DEST=/my-files/Backups/cr-dataentry
KEEP_DAYS=213
STATE="$HOME/.local/state/cr-dataentry-offsite/uploaded.tsv"

mkdir -p "$(dirname "$STATE")"
touch "$STATE"
now=$(date +%s)
shopt -s nullglob

# 1. Upload dumps not yet uploaded
for f in "$SRC"/*; do
  [[ -f $f ]] || continue
  name=$(basename "$f")
  cut -f1 "$STATE" | grep -qxF "$name" && continue            # already uploaded
  (( now - $(stat -c %Y "$f") < 600 )) && continue            # still being written
  echo "Uploading $name"
  "$PD" filesystem upload -t --file-conflict-strategy create-new-revision "$f" "$DEST"
  printf '%s\t%s\n' "$name" "$now" >> "$STATE"
done

# 2. Trash remote copies older than KEEP_DAYS
cutoff=$(( now - KEEP_DAYS * 86400 ))
tmp=$(mktemp)
while IFS=$'\t' read -r name uploaded; do
  if (( uploaded < cutoff )); then
    echo "Trashing $name (older than $KEEP_DAYS days)"
    "$PD" filesystem trash "$DEST/$name" && continue          # forget it once trashed
  fi
  printf '%s\t%s\n' "$name" "$uploaded" >> "$tmp"             # otherwise keep tracking it
done < "$STATE"
mv "$tmp" "$STATE"

# 3. Make the rclone Dolphin mount forget its cached listing (optional)
rclone rc --url http://127.0.0.1:5572 vfs/forget dir=Backups/cr-dataentry >/dev/null 2>&1 || true

# 4. Fail if there's been no new dump in the last 26 hours
if [[ -z $(find "$SRC" -maxdepth 1 -name 'cr_dataentry_*.dump' -mmin -1560 -print -quit) ]]; then
  echo "ERROR: no dump created in the last 26 hours" >&2
  exit 1
fi
```

A copy of the script is kept in the repo as `deploy/bin/cr-dataentry-offsite.sh`. The live copy is the one in `~/.local/bin`, so copy any changes back to the repo.

### The units

`cr-dataentry-offsite.service`
```ini
[Unit]
Description=Upload CR_DataEntry dumps to Proton Drive
OnFailure=cr-dataentry-offsite-failed.service

[Service]
Type=oneshot
ExecStart=%h/.local/bin/cr-dataentry-offsite.sh
```

`cr-dataentry-offsite.timer`
```ini
[Unit]
Description=Daily Proton Drive upload after the 15:00 dump

[Timer]
OnCalendar=*-*-* 15:30
Persistent=true

[Install]
WantedBy=timers.target
```

`cr-dataentry-offsite-failed.service`
```ini
[Unit]
Description=Notify when the CR_DataEntry offsite backup fails

[Service]
Type=oneshot
ExecStart=/usr/bin/notify-send -u critical "CR_DataEntry backup failed" "Check: journalctl --user -u cr-dataentry-offsite"
```

The notification reaches the desktop because the user systemd manager has `DBUS_SESSION_BUS_ADDRESS` set. To test it: `systemctl --user start cr-dataentry-offsite-failed.service`.

---

## 3. Proton Drive CLI

- **Installed:** version 0.9.0 (5 Oct 2026), the official binary from <https://proton.me/download/drive/cli/index.html>, checked against its SHA-512 checksum.
- **Location:** `~/.local/bin/proton-drive`
- **Updating:** there's no apt repo. Download the new version, verify its checksum, then run `install -m 0755 proton-drive ~/.local/bin/proton-drive`.
- **Login:** `proton-drive auth login` signs in through the browser. The session is stored in KWallet. Don't share the login URL until the login has completed.
- **Paths:** `/my-files` is the root of your Drive.
- **Its own log:** `~/.local/state/proton-drive-cli/proton-drive.log`
- **Docs:** <https://proton.me/support/drive-cli> and <https://github.com/ProtonDriveApps/sdk/blob/main/cli/README.md>

Useful commands (short forms work, e.g. `fs` for `filesystem`):
```bash
proton-drive version
proton-drive fs list /my-files/Backups/cr-dataentry
proton-drive fs list /my-files/Backups/cr-dataentry | awk '{print $NF}' | sort   # names, oldest first
proton-drive fs download /my-files/Backups/cr-dataentry/<file>.dump ./
proton-drive fs restore /my-files/Backups/cr-dataentry/<file>.dump              # undo a trash
proton-drive fs upload --help
```

### Credentials: KWallet (decision: keep it)

The CLI's login session is stored in **KWallet** (the default `PROTON_DRIVE_CREDENTIALS_STORE=keychain`, via libsecret).

Proton's offsite-backup guide recommends `pass` for **cron and headless servers**, because desktop keyrings need an active desktop session. That doesn't apply here: the upload runs as a **systemd user service inside the login session**, so KWallet is available. This has been confirmed by successful 15:30 runs.

**Decision: stay on KWallet.** `pass` (the Unix password manager from passwordstore.org, which is *not* Proton Pass) stores secrets as GPG-encrypted files. Unattended use would need a GPG private key with no passphrase, or one cached for very long periods, which is weaker than KWallet on a laptop. Revisit only if uploads must run while logged out.

**KWallet settings to check:** in System Settings → Security & Privacy → KDE Wallet (or KWalletManager → Settings → Configure Wallet), make sure **"Close when screensaver starts"** and **"Close if unused for…"** are **off** (the defaults; checked 13 Oct 2026). If either is on, a locked or idle laptop would have its wallet closed at 15:30 and the upload would fail.

**When the 15:30 upload runs:**

| Laptop state | Upload runs? |
|---|---|
| Screen locked | Yes, as normal (provided KWallet stays open) |
| Asleep or suspended | No. It catches up shortly after waking |
| Logged out | No. It catches up at the next login |
| Switched off | No. It catches up at the next login |

The 15:00 dump is a system service, so it runs whether or not you're logged in, but not while the laptop is asleep or off. Its timer has `Persistent=true` (checked 13 Oct 2026), so a missed dump runs at the next boot.

## 4. The rclone Proton mount (Dolphin)

- `~/ProtonDrive` is mounted by `rclone-protondrive.service`, a user service. `~/OneDrive` is mounted by `rclone-onedrive.service`.
- The Proton mount uses `--dir-cache-time 72h --poll-interval 0`, so files added by **other clients**, such as the CLI or the web app, don't appear in Dolphin for up to 72 hours.
- **To refresh now:**
  ```bash
  rclone rc --url http://127.0.0.1:5572 vfs/forget
  # or
  systemctl --user restart rclone-protondrive.service
  ```
- **Cross-check that bypasses the mount:** `rclone ls proton:Backups/cr-dataentry`

---

## Checking it's working

```bash
# Is the timer scheduled?
systemctl --user list-timers | grep cr-dataentry

# Did today's dump run?
journalctl --user -u cr-dataentry-backup --since today
ls -l ~/.local/share/cr-dataentry/backups | tail -3

# Did the upload run?
journalctl --user -u cr-dataentry-offsite --since today
proton-drive fs list /my-files/Backups/cr-dataentry | awk '{print $NF}' | sort | tail -3

# Run the upload now, by hand
systemctl --user start cr-dataentry-offsite.service
```

## Restoring a dump from Proton

```bash
F=cr_dataentry_YYYYMMDD_HHMMSS.dump
proton-drive fs download /my-files/Backups/cr-dataentry/$F ./

# 1. Header and table of contents readable? (no database needed)
pg_restore --list $F | head

# 2. Byte-for-byte identical to the local original? (only while the local copy still exists)
cmp $F ~/.local/share/cr-dataentry/backups/$F && echo identical

# 3. Every data block readable and decompressible? (no database needed)
pg_restore -f /dev/null $F && echo "all data readable"

# then restore into the local Supabase: rac_reports.py option 6 ("Browse for a file"),
# or ./sync_prod_to_local.sh /full/path/to/$F
```

**Before restoring:** don't run `supabase db reset` first. The held-back migration `supabase/.migrations_on_hold/20260929120000_enforce_guest_dnf_rules_and_cascade_delete.sql` is applied to local by hand. A reset would remove it, so reapply it with `psql … -f` after any reset. The restore wipes local test data, including the `ZZ Test` member.

**To verify the restore,** compare row counts with the dump:
```bash
pg_restore -f - --data-only $F | awk '/^COPY /{t=$2;n=0;on=1;next} /^\\\.$/{if(on)print t,n;on=0;next} on{n++}'
# then: SELECT count(*) FROM <table>; in local for each one
```

- **`--list`** reads only the header and the table of contents: archive date, Postgres versions, and one line per object. Use it to check the file opened and the expected schemas and tables are there.
- **`cmp`** proves the round trip through Proton didn't change the file.
- **`-f /dev/null`** makes `pg_restore` turn the whole archive back into SQL, including all the data, and discard it. This catches corruption that `--list` misses.
- Dumps are made by `pg_dump` 18, so reading them needs `pg_restore` 18 or later, even though Supabase runs Postgres 17.
- **Restore log:** 13 Oct 2026: downloaded `cr_dataentry_20261012_150836.dump` from Proton. All three checks passed (194 entries, identical, all data readable). Restored into the local Supabase with `rac_reports.py` option 6. Row counts matched the dump for all 11 tables (for example 655 members, 5045 reservations, 5572 catch returns). **Full restore test passed.**

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `You need to login first` | The session was lost or a refresh failed. Run `proton-drive auth login`, then re-run the script. Check the CLI log for 401 or refresh errors. |
| Fails partway through a big catch-up | Possible throttling. Add `sleep 5` after the upload line for large backfills. |
| New files missing in Dolphin | The rclone 72h directory cache. See section 4. |
| `Illegal instruction` after a CLI update | Use the baseline or non-AVX2 Linux build. |
| Upload didn't run at 15:30 | You weren't logged in. It runs at the next login. Check `list-timers`. |
| Upload fails while the screen is locked | KWallet closed itself. Check the KWallet settings (see "Credentials: KWallet"). |
| `ERROR: no dump created in the last 26 hours` | The 15:00 dump failed or didn't run. Check `journalctl --user -u cr-dataentry-backup` and `systemctl --user list-timers \| grep cr-dataentry`. A single occurrence after the laptop has been off for days can be a false alarm (see "Behaviour"). |
| "CR_DataEntry backup failed" notification | The offsite unit failed. Run `journalctl --user -u cr-dataentry-offsite -n 50` to see why. |
| No notification appears on failure | Check `journalctl --user -u cr-dataentry-offsite-failed`, and test with `systemctl --user start cr-dataentry-offsite-failed.service`. |

## Next steps

These come from reviewing Proton's guide, [How to automate offsite encrypted backups with Proton Drive CLI](https://proton.me/business/blog/offsite-backup) (Oct 2026).

**Applied 13 Oct 2026** (now covered in section 2):

- [x] Set the file-conflict strategy explicitly (`create-new-revision`).
- [x] Fail when no new dump has appeared in the last 26 hours. This uses `find -mmin`. The draft version used `ls -t` on a glob, which misbehaves under the script's `nullglob` when no dump exists.
- [x] Desktop notification on failure (`OnFailure=cr-dataentry-offsite-failed.service`).
- [x] Confirmed the dump timer catches up: `cr-dataentry-backup.timer` has `Persistent=true`.
- [x] Tested the notification (13 Oct 2026). Because it's sent as critical, KDE keeps it on screen until you dismiss it.
- [x] Checked the KWallet settings (13 Oct 2026). Both auto-close options are off (the defaults). `~/.config/kwalletrc` has no `Close When Idle` or `Close on Screensaver` entries.

**Still to do:**

- [ ] **Test a restore monthly** (last: 13 Oct 2026, full restore passed; next: mid-November). Proton stresses testing restores, not just backups. Once a month, download a recent dump and run the checks in "Restoring a dump from Proton". Add a line to its restore log. Ideally, restore it into the local Supabase as well.
- [ ] **Stop the trash loop from reading the state file (before about May 2027, when trashing starts).** In step 2 of the script, `proton-drive fs trash` runs inside `while read … done < "$STATE"`, so it inherits `uploaded.tsv` as stdin. If the CLI ever reads stdin, for example to prompt, it swallows the remaining lines. Those dumps are then dropped from the state file and re-uploaded on the next run, because local dumps aren't pruned. Fix: add `</dev/null` to the trash command:
  ```bash
  "$PD" filesystem trash "$DEST/$name" </dev/null && continue
  ```

## Other to-dos

- [ ] One-off: during the first catch-up upload (8 Oct 2026), the CLI lost its session at the 25 August dump. Re-running resumed fine. Watch for a recurrence.
- [ ] Consider switching `trash` to `delete` once confident, as trashed files may count towards storage.
- [ ] Optionally add a second offsite copy to `OneDrive:` via rclone.

---

## Related: Timeshift USB stick (checked 8 Oct 2026)

- **The stick:** 128 GB USB stick, `/dev/sda1`, ext4, label "Backups". Timeshift in RSYNC mode, daily snapshots at about 17:00.
- **Health check:** `e2fsck -fn` was clean, with no kernel I/O errors.
- **Usage:** 64% space used, 25% inodes.
- **Exclusions added:** `/var/lib/flatpak/***`, `/var/lib/containerd/***` and `/var/lib/docker/***`. These were adding about 24 GB to snapshots. Config is in `/etc/timeshift/timeshift.json`.
- **Fedora (22 Oct 2026):** the Fedora Timeshift config started without these exclusions. The first Fedora snapshot filled the stick and failed, so add `/var/lib/containerd/***` and `/var/lib/flatpak/***` again under Settings → Filters. (`/var/lib/docker/*` is in Timeshift's built-in list.)
- **Home folder:** `/home/brian` (Fedora: `/home/brianpundyke`) is excluded by Timeshift (the default), so the home folder needs its own backup.
- **Checks:**
  ```bash
  sudo timeshift --list
  df -h /dev/sda1; df -i /dev/sda1
  sudo journalctl -k | grep -iE "sda|usb" | grep -vE "mounted filesystem|unmounting filesystem"
  # with the Timeshift app closed and the stick unmounted:
  sudo umount -A /dev/sda1 && sudo e2fsck -fn /dev/sda1
  ```
- **Quirk:** `lsblk` prints nothing straight to the terminal but works when piped, so use `lsblk | cat`.
