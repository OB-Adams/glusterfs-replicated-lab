# Screenshots

This folder holds screenshots of real terminal output from the lab. No images have been added yet. This file is the capture checklist.

## Rules

- Capture genuine output from the running lab. Never mock up or edit output.
- Make the machine visible: keep the shell prompt (`root@gluster2:~#` and similar) in frame.
- Crop to the relevant output. Prefer a few clear images over many similar ones.
- Check each image for private addresses, tokens or personal information before committing.
- Use the exact file names below. The README refers to them.

## Checklist

| File | Machine | What to run | It should show | Capture now? |
|---|---|---|---|---|
| `01-brick-layout-lvm-xfs-selinux.png` | gluster1 | `lsblk`, `sudo lvs -a`, `df -hT /data/glusterfs/brick1`, `ls -Zd /data/glusterfs/brick1/vol` | Thin pool and thin LV, XFS mounted at the brick path, SELinux label on the brick directory | Yes |
| `02-pool-and-volume-status.png` | gluster1 | `sudo gluster pool list`, `sudo gluster volume info gv0`, `sudo gluster volume status gv0` | Three peers connected, replica 3 volume, three bricks online | Yes |
| `03-client-mount-and-replicas.png` | gluster4, then each server | `df -hT /mnt/gv0`, then `ls -l /data/glusterfs/brick1/vol` on each server | Client mount and identical files on every brick (use a split terminal or stitch three panes) | Yes |
| `04-drill1-heal-pending-and-recovered.png` | gluster2 | `sudo gluster volume heal gv0 info summary` during the outage and again after recovery | Pending entries on the surviving bricks, then the backlog falling to zero | Only by re-running drill 1 |
| `05-drill2-write-stall-latency.png` | gluster4 | `sort -k2 -rn ~/drill2a-latency.log \| head -3` and the same for `drill2b-latency.log` | The single long write in each run against normal writes of about 0.03 s | Yes, if the log files still exist |
| `06-drill3-client-quorum-lost-log.png` | gluster4 | `grep -n -E "Client-quorum is not met\|no read subvols\|first lookup on root failed" /var/log/glusterfs/mnt-gv0.log` | The quorum-lost message and the failed root lookup, with timestamps | Yes, if the log has not been rotated |
| `07-drill4-split-brain-eio-and-xattrs.png` | gluster4 and each server | `cat /mnt/gv0/drill4/victim.txt` (fresh mount), then `sudo getfattr -d -m . -e hex <brick path>/drill4/victim.txt` on each server | `Input/output error` and the conflicting `trusted.afr.gv0-client-N` blame attributes | Only by re-running drill 4 |
| `08-drill4-source-brick-resolution.png` | gluster1 | `bigger-file`, `latest-mtime`, then `source-brick` heal commands on the split-brain file, then `sudo gluster volume heal gv0 info split-brain` | Two refusals and the `Healed` message, then zero split-brain entries | Only by re-running drill 4 |

Screenshots 04, 07 and 08 need the original state, which no longer exists. The drills are repeatable, so rerun them and capture as you go. Use the `drill-writer.sh` script and the procedures in [../docs/failure-drills.md](../docs/failure-drills.md).

## Embedding in the README

After a file is added, replace its row's `To capture` status in the main README and add an image reference such as:

```markdown
![Pool and volume status](screenshots/02-pool-and-volume-status.png)
```

Add the image link only after the file exists, so GitHub does not show a broken image.
