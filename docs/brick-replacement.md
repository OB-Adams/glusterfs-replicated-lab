# Brick replacement

Milestone 2, steps 2a and 2b. In 2a, the brick on `gluster3` is destroyed, rebuilt at the same path, re-admitted to the volume with `reset-brick`, and repaired by the self-heal daemon. In 2b, the same brick is moved to a new disk at a different path with `replace-brick` while a client keeps writing. Step 2c (expansion and rebalance) is in [expansion.md](expansion.md). See [milestones.md](milestones.md).

## Concepts

**Volume identity.** Each brick directory carries the extended attribute `trusted.glusterfs.volume-id`, which ties it to the volume. A freshly formatted brick does not have it, so Gluster will not silently accept it as part of `gv0`. The replacement commands exist so the operator can state that an empty brick is intentional.

**Two commands.** `gluster volume reset-brick` is for a brick kept at the same host and path after its disk has been wiped or reformatted; `start` releases it and `commit force` re-admits it. `gluster volume replace-brick ... commit force` swaps a brick for one at a different path or host. Older releases could migrate data before the swap; that mode was removed, which is why `commit force` is the only form left. Neither command copies any data.

**Position in the replica set.** Both commands keep the brick's position in the volume. The third brick is always the third, so its client translator stays `gv0-client-2` whichever path it points at. After `replace-brick`, glusterd regenerates the volfiles and every mounted client loads a new graph that points `gv0-client-2` at the new path. This is a "graph switch", and the client log records it.

**How the data comes back.** To the replication layer (AFR), an empty brick looks like a replica that missed every write. The surviving bricks hold the records of what it is missing, and the self-heal daemon copies the tree onto it. Healing the root directory's entries creates every file and directory beneath it on the empty brick, and each of those is then healed in turn. The rebuilt brick is the heal sink and the surviving bricks are the sources, the same mechanism as drill 1 in [failure-drills.md](failure-drills.md).

**What starts a heal.** The self-heal daemon processes its index of pending entries on three triggers: a periodic crawl every `cluster.heal-timeout` seconds (600 by default), a brick connecting to the daemon, and an explicit `gluster volume heal`. `heal full` skips the index and walks the whole tree on every brick.

**The old brick.** `replace-brick` stops the old brick process and removes it from the volume, but leaves its data, its `.glusterfs` directory and its volume ID in place. Gluster will not take that path into a volume again until it is cleaned.

## 2a: rebuild at the same path with `reset-brick`

Run on 2026-10-27. Every figure in this section comes from [evidence/drill5-session-gluster1.txt](evidence/drill5-session-gluster1.txt), [evidence/drill5-session-gluster2.txt](evidence/drill5-session-gluster2.txt), [evidence/drill5-session-gluster3.txt](evidence/drill5-session-gluster3.txt) and [evidence/drill5-logs.txt](evidence/drill5-logs.txt).

### Procedure

Sizes match the [build guide](build-guide.md). The replacement thin LV keeps the original size, and the `/etc/fstab` entry is left in place so a plain `mount` works.

1. **Baseline.** Confirm all bricks online and the heal backlog at zero with `scripts/check-cluster.sh`. Write the test data on the client, then record the file count and digest on each server with `scripts/compare-bricks.sh`.
2. **Release and destroy the brick (gluster3).**

   ```bash
   sudo gluster volume reset-brick gv0 gluster3:/data/glusterfs/brick1/vol start
   sudo umount /data/glusterfs/brick1
   sudo lvremove -y vg_gluster/brick1
   ```

   The path must match the brick as registered in `gluster volume info gv0`, including the `vol` subdirectory.

3. **Write while the brick is gone.** From the client, create a second directory of files. Writes continue because 2 of 3 bricks are reachable.
4. **Build the replacement (gluster3).**

   ```bash
   sudo lvcreate -V 8G --thin -n brick1 vg_gluster/thinpool
   sudo mkfs.xfs -i size=512 /dev/vg_gluster/brick1
   sudo mount /data/glusterfs/brick1
   sudo mkdir /data/glusterfs/brick1/vol
   sudo restorecon -Rv /data/glusterfs
   ```

5. **Re-admit it.**

   ```bash
   sudo gluster volume reset-brick gv0 gluster3:/data/glusterfs/brick1/vol gluster3:/data/glusterfs/brick1/vol commit force
   ```

6. **Watch, then trigger.** Poll `gluster volume heal gv0 info summary`. If the backlog does not move, run `sudo gluster volume heal gv0 full`.
7. **Verify.** Compare the file count and digest on all three servers for both directories.

### Timeline

Times are UTC on 2026-10-27, taken from the session logs and from Gluster's own logs.

| Time | Event |
|---|---|
| 14:52:20 | Baseline: three bricks online, heal backlog zero, `cluster.quorum-type auto` |
| 14:54:59 | `reset-brick ... start` returns `SUCCESS`; brick unmounted and the LV removed |
| 14:56 | Replacement thin LV, XFS and empty `vol` directory in place, relabelled for SELinux |
| 14:58:32 | `reset-brick ... commit force` returns `SUCCESS` |
| 14:59:03, 14:59:33, 15:00:04 | Three polls, each showing 91 entries pending on both source bricks. No change. |
| 15:00:29 | `heal full` returns `SUCCESS`; the daemon log records a full sweep starting on `gv0-client-2` |
| 15:00:55 | The daemon log records the sweep finished, about 26 seconds later |
| 15:00:59 | Poll shows zero entries pending on every brick |

### Findings

**The heal did not begin on its own.** Between the commit at 14:58:32 and `heal full` at 15:00:29, three polls just under two minutes apart all reported 91 entries pending on `gluster1` and `gluster2`, with no movement. The sweep started at the same second as the command. This establishes that the rebuild did not start within roughly two minutes of the commit, not that it would never have started; a longer wait was not tested.

**The rebuild took about 26 seconds.** The daemon log puts the full sweep on the rebuilt brick between 15:00:29.065 and 15:00:55.588, and the next poll at 15:00:59 showed the backlog at zero.

**The pending count rose before it fell.** Polls during the heal reported 89 entries, then 283 on `gluster1` and 263 on `gluster2`, then zero. The capture does not show why the count grows mid-sweep, so it is recorded as observed.

**The brick showed offline immediately after the commit.** `gluster volume status gv0` run straight after `commit force` listed `gluster3`'s brick with no TCP port and no PID. The heal and the digests below show it was serving afterwards; nothing in the capture pins down the moment it came up.

**An empty brick is enough.** The replacement directory was empty at 14:56, with only `.` and `..` present and the SELinux type `glusterd_brick_t`. Everything on it afterwards was placed there by the self-heal daemon.

### Verification

Both directories, compared on all three servers after the rebuild:

| Directory | Files | Digest | gluster1 | gluster2 | gluster3 |
|---|---|---|---|---|---|
| `drill5` (written before the wipe) | 151 | `2dadf1bb…ce891` | match | match | match |
| `drill5-during` (written while the brick was gone) | 100 | `f7dbbb3a…0e27b` | match | match | match |

`gluster3` is the rebuilt brick, so its agreement is the result that matters: both the data that predated the wipe and the data written during the outage came back byte-identical.

## 2b: move to a new disk with `replace-brick`

Run on 2026-10-27. Every figure in this section comes from [evidence/drill6-session-gluster1.txt](evidence/drill6-session-gluster1.txt), [evidence/drill6-session-gluster2.txt](evidence/drill6-session-gluster2.txt), [evidence/drill6-session-gluster3.txt](evidence/drill6-session-gluster3.txt), [evidence/drill6-session-gluster4.txt](evidence/drill6-session-gluster4.txt) and [evidence/drill6-logs.txt](evidence/drill6-logs.txt).

### Why a second disk

`vg_gluster` holds a 9 GB thin pool that already carries the 8 GB `brick1`, and only about 1 GB of the volume group is free. A second 8 GB thin volume in that pool would overcommit it, which the [build guide](build-guide.md) rules out. Each server therefore received a second 10 GB virtual disk, `/dev/vdc`, with its own volume group. That also keeps one brick per disk, so a failed disk takes out one brick and nothing else. Only `gluster3`'s new disk is used in this step; the others are for 2c.

### Procedure

1. **Add the disks.** Unmount the client, power off the four VMs, add a 10 GB VirtIO drive to `gluster1`, `gluster2` and `gluster3` in UTM, and boot them. On each server, `lsblk -f` must show `vdb1` still as `LVM2_member` and `vdc` with no filesystem and no partitions. Remount the client and wait for `scripts/check-cluster.sh` to show three bricks online and no heal backlog.
2. **Baseline.** On `gluster1`, record the volume, `cluster.heal-timeout` and `cluster.self-heal-daemon`. On the client, write a new `drill6` directory: 150 small files across three subdirectories and one 200 MB file. Record the file count and digest of `drill5`, `drill5-during` and `drill6` on each server.
3. **Build the new brick (gluster3).** The same recipe as `brick1`, on the new disk:

   ```bash
   sudo parted -s /dev/vdc mklabel gpt mkpart brick2 0% 100% set 1 lvm on
   sudo pvcreate /dev/vdc1
   sudo vgcreate vg_gluster2 /dev/vdc1
   sudo lvcreate -L 9G --thinpool thinpool vg_gluster2
   sudo lvcreate -V 8G --thin -n brick2 vg_gluster2/thinpool
   sudo mkfs.xfs -i size=512 /dev/vg_gluster2/brick2
   sudo mkdir -p /data/glusterfs/brick2
   echo '/dev/vg_gluster2/brick2 /data/glusterfs/brick2 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
   sudo systemctl daemon-reload
   sudo mount /data/glusterfs/brick2
   sudo mkdir /data/glusterfs/brick2/vol
   sudo restorecon -Rv /data/glusterfs/brick2
   ```

   The existing SELinux rule `"/data/glusterfs(/.*)?"` already covers the new path, so `restorecon` is enough. Before going further, confirm with `findmnt` that the new filesystem is mounted. `force` relaxes glusterd's checks on the new brick path, so if the mount were missing, the brick would be created on the root disk.

4. **Start a writer on the client.** `scripts/drill-writer.sh /mnt/gv0/drill6-during 400 0.5`, which runs for about four minutes.
5. **Replace the brick (gluster3).**

   ```bash
   sudo gluster volume replace-brick gv0 \
     gluster3:/data/glusterfs/brick1/vol \
     gluster3:/data/glusterfs/brick2/vol commit force
   ```

6. **Watch without intervening.** Poll `gluster volume heal gv0 info summary` for up to 11 minutes, past one `heal-timeout` interval, before running any heal command.
7. **Verify.** Compare all four directories on all three servers, check the writer for failures, and inspect the old brick.

### Timeline

Times are UTC on 2026-10-27. Times with fractions of a second come from Gluster's logs, the rest from the session logs.

| Time | Event |
|---|---|
| 19:25:04 | Baseline: three bricks online, heal backlog zero, `heal-timeout` 600 (default), self-heal daemon on |
| 19:25:21 | `drill6` written on the client: 151 files |
| 19:25:37 to 19:25:54 | `drill5`, `drill5-during` and `drill6` have the same counts and digests on all three servers |
| 19:26:23 to 19:27:18 | New brick built on `/dev/vdc`; `vol` empty apart from its SELinux label |
| 19:27:40 | Writer starts on the client |
| 19:28:10 | `replace-brick ... commit force` returns success |
| 19:28:10.5 | The client and the self-heal daemons on `gluster1` and `gluster2` see the old brick's connection close |
| 19:28:13 | `volume status` lists `Brick3: gluster3:/data/glusterfs/brick2/vol` offline, with no port |
| 19:28:13.73 | The client and both source daemons attach `gv0-client-2` to `/data/glusterfs/brick2/vol` on port 50497 |
| 19:28:13.75 | `gluster2`'s daemon starts an entry heal of the root directory; `gluster1`'s heals the root's metadata |
| 19:28:14.07 | The client switches to the new graph |
| 19:28:15.64 | `gluster3`'s daemon connects to the new brick, after a failed port lookup at 19:28:12.6 |
| 19:28:29 | `volume status` shows the new brick online, port 50497 |
| 19:28:50.17 | `gluster2`'s daemon logs its last completed heal |
| 19:29:25 to 19:31:56 | Six polls, every brick at zero entries |
| 19:31:37 | Writer finished: 400 files, no failures |
| 19:32:00 to 19:32:04 | All four directories have the same counts and digests on all three servers |
| 19:33:08 | Closing check: three bricks online, zero entries, zero split-brain |

### Findings

**The heal started by itself, 20 ms after the new brick connected.** No heal command was run at any point. Both source daemons attached to the new brick at 19:28:13.73, and by 19:28:13.75 `gluster2`'s daemon was healing the root directory's entries. The 600-second `heal-timeout` crawl played no part; the trigger was the brick connecting. In 2a the backlog sat for two minutes until `heal full`. This run does not show why the two steps behaved differently, so the difference is recorded as observed.

**The whole volume was copied in about 36 seconds.** From the root heal at 19:28:13.75 to the last completed heal at 19:28:50.17, `gluster2`'s daemon performed 1,843 data heals, 1,856 metadata heals and 14 directory entry heals. `gluster1`'s daemon healed the root directory's metadata and nothing more, and `gluster3`'s did no healing. Afterwards the new thin volume held 6.88% data against 6.86% for the old one.

**The heal finished before the first poll.** The polls started at 19:29:25, about 35 seconds after the last heal, so all six show zero. The heal's timing comes from the daemon log, and its result from the digests below.

**The client did not stall.** All 400 writes succeeded. The slowest took 0.028 s, against an average of 0.015 s, and the writes around the commit and the graph switch (files 40 to 75) all finished within 0.023 s. Compare drill 2, where a hard node failure stalled writes for 70.3 s. There the server vanished without closing its connections, so the client had to wait out `network.ping-timeout`. Here glusterd stopped the old brick process cleanly, the client saw its connection close at once, and kept writing to the two remaining bricks, which still meet quorum, until the new brick attached about 3.2 seconds later.

**The new brick came up within seconds.** `volume status` taken straight after the commit showed it offline with no port, as in 2a. The logs date its first client connection to 19:28:13.73, and the next `volume status` at 19:28:29 showed it online.

**The self-heal daemons were restarted.** Their PIDs on all three servers differ between the baseline at 19:25:04 and the first status after the commit at 19:28:13. The commit is the only change to the volume in that window.

**One `setattr` to the new brick failed during the root heal.** It was logged at 19:28:13.95 with `Invalid argument`, just before the root directory's entry heal completed. The heal carried on, and the digests match.

**The old brick was left intact.** After the commit, `gluster3` runs one brick process, for `brick2`. `/data/glusterfs/brick1/vol` still holds every directory from earlier drills, and both paths carry the same `trusted.glusterfs.volume-id`, `0x91f1a491…`, the same value as the volume ID in `gluster volume info`. That is why the old path cannot be reused in 2c until it is cleaned.

### Verification

All four directories, compared on all three servers after the replacement:

| Directory | Files | Digest | gluster1 | gluster2 | gluster3 (`brick2`) |
|---|---|---|---|---|---|
| `drill5` (from 2a) | 151 | `2dadf1bb…ce891` | match | match | match |
| `drill5-during` (from 2a) | 100 | `f7dbbb3a…0e27b` | match | match | match |
| `drill6` (written before the replacement) | 151 | `824aa046…e791c` | match | match | match |
| `drill6-during` (written across the replacement) | 400 | `160a99f4…79533` | match | match | match |

The first three directories also match the baseline taken before the commit. `gluster3`'s new brick started empty, so everything on it was put there by the self-heal daemon or written by the client after it attached.

## References

- [Gluster documentation home](https://docs.gluster.org/)
- [Bug 1275884: replace-brick commit force refuses to work when it cannot resolve source brick](https://bugzilla.redhat.com/show_bug.cgi?id=1275884)
- [Bug 1507877: reset-brick commit force failed with glusterd_volume_brickinfo_get Returning -1](https://lists.gluster.org/pipermail/bugs/2017-October/094074.html)
