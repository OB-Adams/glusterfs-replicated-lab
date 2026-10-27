# Screenshots

This folder holds screenshots of real terminal output from the lab. Each one is embedded in the [main README](../README.md#screenshots-and-evidence). This file records what each image shows and the commands behind it, so the set can be reproduced.

## Rules

- Capture genuine output from the running lab. Never mock up or edit output.
- Make the machine visible: keep the shell prompt (`root@gluster2:~#` and similar) in frame.
- Crop to the relevant output. Prefer a few clear images over many similar ones.
- Check each image for private addresses, tokens or personal information before committing.
- Use the exact file names below. The main README refers to them.
- Where a command sequence is long or its output scrolls, the commands may be re-run afterwards in a clean terminal to capture a readable image. Screenshots 09 and 10 were captured that way, so their timestamps and counters differ from the session logs in `../docs/evidence`, which remain the record of the drill itself.
- Screenshots 13 to 16 come from a repeat of drill 6, run after the recorded run had been reversed, to capture clean images. The repeat skipped the client writer, and a `heal full` was run during it, which the recorded run did not need. Its timestamps differ from the drill 6 session logs, which remain the record of the drill.

## The set

| File | Machine | What was run | What it shows |
|---|---|---|---|
| `01-brick-layout-lvm-xfs-selinux.png` | gluster1 | `lsblk`, `sudo lvs -a`, `df -hT /data/glusterfs/brick1`, `ls -Zd /data/glusterfs/brick1/vol` | Thin pool and thin LV, XFS mounted at the brick path, SELinux label on the brick directory |
| `02-pool-and-volume-status.png` | gluster1 | `sudo gluster pool list`, `sudo gluster volume info gv0`, `sudo gluster volume status gv0` | Three peers connected, replica 3 volume, three bricks online |
| `03-client-mount-and-replicas.png` | gluster4, then each server | `df -hT /mnt/gv0`, then `ls -l /data/glusterfs/brick1/vol` on each server | Client mount and identical files on every brick |
| `04-drill1-heal-pending.png` | gluster2 | `sudo gluster volume heal gv0 info summary` during the outage | Entries pending heal on the surviving bricks, stopped node unreachable |
| `04-drill1-heal-recovered.png` | gluster2 | `sudo gluster volume heal gv0 info summary` after recovery | The backlog repaired after the node returned |
| `05-drill2-write-stall-latency.png` | gluster4 | `sort -k2 -rn ~/drill2a-latency.log \| head -3` and the same for `drill2b-latency.log` | The single long write in each run against normal writes of about 0.03 s |
| `06-drill3-client-quorum-lost-log.png` | gluster4 | `grep -n -E "Client-quorum is not met\|no read subvols\|first lookup on root failed" /var/log/glusterfs/mnt-gv0.log` | The quorum-lost message and the failed root lookup, with timestamps |
| `07-drill4-split-brain-eio.png` | gluster4 | `cat /mnt/gv0/drill4/victim.txt` from a fresh mount | `Input/output error` on the split-brain file |
| `07-drill4-split-brain-xattrs.png` | each server | `sudo getfattr -d -m . -e hex <brick path>/drill4/victim.txt` | The conflicting `trusted.afr.gv0-client-N` blame attributes |
| `08-drill4-source-brick-resolution.png` | gluster1 | `bigger-file`, `latest-mtime`, then `source-brick` heal commands on the split-brain file | Two refusals and the `Healed` message |
| `09-drill5-brick-rebuilt-empty.png` | gluster3 | `lvcreate`, `mkfs.xfs`, `mount`, `mkdir`, `restorecon`, then `lvs vg_gluster`, `df -hT`, `ls -la` and `ls -Zd` on the brick | The replacement brick before it is re-admitted: new thin LV, XFS mounted, empty `vol` directory with the `glusterd_brick_t` label |
| `10-drill5-heal-progress.png` | gluster3 | `sudo gluster volume heal gv0 full`, then `sudo gluster volume heal gv0 info summary` twice | Entries pending on the two source bricks and none on the rebuilt one, then zero everywhere |
| `11-drill5-digests-match.png` | each server | `./scripts/compare-bricks.sh` on `drill5` and `drill5-during` | 151 files and 100 files, each with the same digest on all three servers |
| `12-drill5-reset-brick-logs.png` | gluster3 | `grep -iE "reset-brick\|heal" /var/log/glusterfs/cmd_history.log \| tail -3` and `sudo grep -i "full sweep" /var/log/glusterfs/glustershd.log \| tail -2` | The `reset-brick` and `heal full` commands with their results, and the full sweep on the rebuilt brick |
| `13-drill6-new-brick-ready.png` | gluster3 | `findmnt /data/glusterfs/brick2`, `ls -laZ /data/glusterfs/brick2/vol`, `sudo getfattr -d -m . -e hex /data/glusterfs/brick2/vol`, `sudo lvs vg_gluster2` | The new brick before the commit: XFS on the second disk, empty `vol` directory with the `glusterd_brick_t` label and no Gluster attributes |
| `14-drill6-replace-brick-commit.png` | gluster3 | `sudo gluster volume replace-brick gv0 gluster3:/data/glusterfs/brick1/vol gluster3:/data/glusterfs/brick2/vol commit force`, `sudo gluster volume info gv0`, `sudo gluster volume status gv0`, `sudo grep replace-brick /var/log/glusterfs/cmd_history.log \| tail -1` | The commit succeeding, `Brick3` on the new path and online, and the commit time |
| `15-drill6-heal-from-shd-log.png` | gluster1 | `sudo grep -E "Connected, attached.*client-2\|full entry selfheal on 00000000-0000-0000-0000-000000000001" /var/log/glusterfs/glustershd.log \| tail -3` | The new brick attaching, then the heal of the root directory starting by itself a tenth of a second later and completing |
| `16-drill6-digests-match.png` | each server | `./scripts/compare-bricks.sh` on `drill5`, `drill5-during`, `drill6` and `drill6-during` | 151, 100, 151 and 400 files, each with the same digest on all three servers |

The procedures are in [../docs/failure-drills.md](../docs/failure-drills.md) for drills 1 to 4 and [../docs/brick-replacement.md](../docs/brick-replacement.md) for drills 5 and 6.

## Adding another screenshot

Put the file in this folder, add a row above, then add an image reference in the main README:

```markdown
![Pool and volume status](screenshots/02-pool-and-volume-status.png)
```

Add the image link only after the file exists, so GitHub does not show a broken image.
