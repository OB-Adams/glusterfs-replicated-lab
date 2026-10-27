# Brick replacement

Milestone 2, step 2a: the brick on `gluster3` is destroyed, rebuilt at the same path, re-admitted to the volume with `reset-brick`, and repaired by the self-heal daemon. Steps 2b (`replace-brick` to a different path or host) and 2c (expansion and rebalance) come next. See [milestones.md](milestones.md).

Run on 2026-10-27. Every figure below comes from [evidence/drill5-session-gluster1.txt](evidence/drill5-session-gluster1.txt), [evidence/drill5-session-gluster2.txt](evidence/drill5-session-gluster2.txt), [evidence/drill5-session-gluster3.txt](evidence/drill5-session-gluster3.txt) and [evidence/drill5-logs.txt](evidence/drill5-logs.txt).

## Concepts

**Volume identity.** Each brick directory carries the extended attribute `trusted.glusterfs.volume-id`, which ties it to the volume. A freshly formatted brick does not have it, so Gluster will not silently accept it as part of `gv0`. The replacement commands exist so the operator can state that an empty brick is intentional.

**Two commands.** `gluster volume reset-brick` is for a brick kept at the same host and path after its disk has been wiped or reformatted; `start` releases it and `commit force` re-admits it. `gluster volume replace-brick ... commit force` swaps a brick for one at a different path or host, which is step 2b.

**How the data comes back.** To the replication layer (AFR), an empty brick looks like a replica that missed every write. The surviving bricks hold the records of what it is missing, and the self-heal daemon copies the tree onto it. The rebuilt brick is the heal sink and the surviving bricks are the sources, the same mechanism as drill 1 in [failure-drills.md](failure-drills.md).

## Procedure

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

## Timeline

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

## Findings

**The heal did not begin on its own.** Between the commit at 14:58:32 and `heal full` at 15:00:29, three polls just under two minutes apart all reported 91 entries pending on `gluster1` and `gluster2`, with no movement. The sweep started at the same second as the command. This establishes that the rebuild did not start within roughly two minutes of the commit, not that it would never have started; a longer wait was not tested.

**The rebuild took about 26 seconds.** The daemon log puts the full sweep on the rebuilt brick between 15:00:29.065 and 15:00:55.588, and the next poll at 15:00:59 showed the backlog at zero.

**The pending count rose before it fell.** Polls during the heal reported 89 entries, then 283 on `gluster1` and 263 on `gluster2`, then zero. The capture does not show why the count grows mid-sweep, so it is recorded as observed.

**The brick showed offline immediately after the commit.** `gluster volume status gv0` run straight after `commit force` listed `gluster3`'s brick with no TCP port and no PID. The heal and the digests below show it was serving afterwards; nothing in the capture pins down the moment it came up.

**An empty brick is enough.** The replacement directory was empty at 14:56, with only `.` and `..` present and the SELinux type `glusterd_brick_t`. Everything on it afterwards was placed there by the self-heal daemon.

## Verification

Both directories, compared on all three servers after the rebuild:

| Directory | Files | Digest | gluster1 | gluster2 | gluster3 |
|---|---|---|---|---|---|
| `drill5` (written before the wipe) | 151 | `2dadf1bb…ce891` | match | match | match |
| `drill5-during` (written while the brick was gone) | 100 | `f7dbbb3a…0e27b` | match | match | match |

`gluster3` is the rebuilt brick, so its agreement is the result that matters: both the data that predated the wipe and the data written during the outage came back byte-identical.

## References

- [Gluster documentation home](https://docs.gluster.org/)
- [Bug 1275884: replace-brick commit force refuses to work when it cannot resolve source brick](https://bugzilla.redhat.com/show_bug.cgi?id=1275884)
- [Bug 1507877: reset-brick commit force failed with glusterd_volume_brickinfo_get Returning -1](https://lists.gluster.org/pipermail/bugs/2017-October/094074.html)
