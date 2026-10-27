# Screenshots

This folder holds screenshots of real terminal output from the lab. Each one is embedded in the [main README](../README.md#screenshots-and-evidence). This file records what each image shows and the commands behind it, so the set can be reproduced.

## Rules

- Capture genuine output from the running lab. Never mock up or edit output.
- Make the machine visible: keep the shell prompt (`root@gluster2:~#` and similar) in frame.
- Crop to the relevant output. Prefer a few clear images over many similar ones.
- Check each image for private addresses, tokens or personal information before committing.
- Use the exact file names below. The main README refers to them.

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

The procedures behind these drills are in [../docs/failure-drills.md](../docs/failure-drills.md).

## Adding another screenshot

Put the file in this folder, add a row above, then add an image reference in the main README:

```markdown
![Pool and volume status](screenshots/02-pool-and-volume-status.png)
```

Add the image link only after the file exists, so GitHub does not show a broken image.
