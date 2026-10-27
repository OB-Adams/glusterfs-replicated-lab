# Expansion and rebalance

Milestone 2, step 2c (drill 7). A second replica set is added to `gv0`, turning it from `1 x 3` into a distributed-replicated `2 x 3` volume. File placement is then traced through the hash layout on the bricks before the rebalance, after a rebalance that skipped files, and after a forced rebalance. See [milestones.md](milestones.md).

Run on 2026-10-27. Every figure below comes from [evidence/drill7-session-gluster1.txt](evidence/drill7-session-gluster1.txt), [evidence/drill7-session-gluster2.txt](evidence/drill7-session-gluster2.txt), [evidence/drill7-session-gluster3.txt](evidence/drill7-session-gluster3.txt), [evidence/drill7-session-gluster4.txt](evidence/drill7-session-gluster4.txt) and [evidence/drill7-logs.txt](evidence/drill7-logs.txt). Screenshots were taken during the run.

## Concepts

**Two layers in one volume.** A Gluster client graph has a distribute layer (DHT) above the replicate layer (AFR). Before this drill DHT had one child, `gv0-replicate-0`, so it had nothing to decide. `add-brick` gives it a second child, `gv0-replicate-1`. DHT now chooses which replica set holds each file, and AFR keeps three copies of that file inside the set.

**Brick order makes the sets.** With `replica 3`, every three bricks listed in `add-brick` form one new set, in the order given. Taking one brick from each server keeps the three copies on three machines.

**Placement is a hash, per directory.** DHT hashes a file's name, not its path, to a 32-bit value. Each directory has a layout that splits the range `00000000` to `ffffffff` between the replica sets, and a file goes to the set whose range contains its hash. No table records where each file is; any client works it out from the name and the directory's layout.

**The layout lives on the bricks.** Each copy of a directory carries `trusted.glusterfs.dht`, four 32-bit words: the layout's commit hash, the hash type, and the start and end of the range that brick's set owns for that directory.

**Rebalance.** `rebalance start` first rewrites every directory's layout across all sets (fix-layout), then moves each file whose hash now falls in another set's range. A rebalance process runs on every server, and `rebalance status` reports one line each.

**Link files.** When a file's name hashes to one set but its data sits on the other, DHT keeps a zero-byte pointer on the hashed set: mode `---------T`, with `trusted.glusterfs.dht.linkto` naming the set that holds the data. Lookups follow it.

**The free-space rule.** A rebalance skips a file if moving it would leave the destination set with less free space than the source. `rebalance start force` turns that check off.

## Layout

| Replica set | gluster1 | gluster2 | gluster3 |
|---|---|---|---|
| Set 1 (`gv0-replicate-0`) | `brick1` | `brick1` | `brick2` |
| Set 2 (`gv0-replicate-1`) | `brick2` | `brick2` | `brick1`, wiped and re-added |

`gluster3`'s bricks are the other way round from the other two servers because 2b moved its set 1 brick to the second disk. Each new brick is an 8 GB thin volume on the second 10 GB disk, `vg_gluster2`, built with the same recipe as in 2b.

## Procedure

1. **Baseline.** Three bricks online and the heal backlog at zero. On the client, write 300 files of 4 KiB into a new `drill7` directory and record the count and digest from the client and from each server's brick.
2. **Build the new bricks** on `gluster1` and `gluster2`: partition `/dev/vdc`, `vg_gluster2`, a 9 GB thin pool, an 8 GB thin volume `brick2`, XFS with 512-byte inodes, an fstab mount, the `vol` directory, and `restorecon`.
3. **Try `gluster3`'s old brick as it is** (`gluster3`):

   ```bash
   getfattr -n trusted.glusterfs.volume-id -e hex /data/glusterfs/brick1/vol
   gluster volume add-brick gv0 \
     gluster1:/data/glusterfs/brick2/vol \
     gluster2:/data/glusterfs/brick2/vol \
     gluster3:/data/glusterfs/brick1/vol
   ```

4. **Wipe it and expand.** `umount`, `mkfs.xfs -f -i size=512`, `mount`, `mkdir vol`, `restorecon`, then the same `add-brick`.
5. **Write before rebalancing.** On the client, 50 `late` files into the existing `drill7`, and 100 files into a new `drill7-newdir`. Read the layout attributes and count regular files per brick on `gluster1`, which has a brick in each set.
6. **Rebalance** with `gluster volume rebalance gv0 start`, then `status` until complete. Read the layouts and counts again.
7. **Find the cause of any skips** in `/var/log/glusterfs/gv0-rebalance.log`, then rebalance again with `start force`.
8. **Verify.** Layouts and counts, `pathinfo` from the client, the digest of the original 300 files from the client, and per-set digests on all three servers.

## Timeline

Times are UTC on 2026-10-27, from the session logs, `cmd_history.log` and the rebalance log.

| Time | Event |
|---|---|
| 22:26 | Baseline: three bricks online, heal backlog zero, `1 x 3 = 3`; `drill7` holds 300 files, digest `58adce45…ff57`, on all three servers |
| 22:31 to 22:32 | New `brick2` built on `gluster1` and `gluster2` |
| 22:34:26 | `add-brick` refused: `/data/glusterfs/brick1/vol is already part of a volume` |
| 22:35 | `gluster3`'s old brick wiped with `mkfs.xfs -f` and remounted empty |
| 22:36:07 | `add-brick` succeeds; `Distributed-Replicate`, `2 x 3 = 6`, six bricks online |
| 22:37:16 | 50 `late` files written into `drill7`, and `drill7-newdir` created with 100 files |
| 22:40:38 | `rebalance start` |
| 22:40:59.50 to 22:41:00.76 | 173 link files created on set 2 in `drill7` |
| 22:41:00 | Rebalance completed in 22 s on all three servers: 908 files moved, 320 skipped, 0 failures |
| 23:03:39 to 23:03:46 | Forced rebalance moves files, in both directions |
| 23:03 | Forced rebalance completed in 7 to 8 s: 339 files moved, 0 skipped, 0 failures |
| 23:25 | Closing check: six bricks online, zero heal entries, zero split-brain, rebalance task `completed` |

## Findings

**The old brick was refused by its volume ID.** `gluster3`'s `brick1/vol` still carried `trusted.glusterfs.volume-id=0x91f1a4916fdf4b32b8c8456973a6b649`, the same value as `gv0`'s volume ID `91f1a491-6fdf-4b32-b8c8-456973a6b649`. `add-brick` failed with `/data/glusterfs/brick1/vol is already part of a volume` and nothing changed. After `mkfs.xfs -f` the same command succeeded.

**`add-brick` left existing directories alone.** Before the rebalance, `drill7`, which existed before the expansion, had the full range `00000000` to `ffffffff` on set 1 and an all-zero layout on set 2, and all 350 of its files were on set 1. Set 2's copy of the directory was created at 22:37:16.470, 10 ms before the first `late` file, when the client first wrote into it. `drill7-newdir`, created after the expansion, was split from the start: set 2 `00000000` to `7ffffffe`, set 1 `7fffffff` to `ffffffff`, with its 100 files placed 55 and 45. Every layout still had commit hash `00000000`.

**The first rebalance fixed the layouts but skipped 320 files.** It reported `completed` with 0 failures on every server. It moved 281, 315 and 312 files (5.5 MB, 305.4 MB and 58.6 MB) and skipped 105, 108 and 107. `drill7` now had the split layout with commit hash `570942e4`, yet all 350 files were still on set 1.

**Every skip was the free-space rule.** Each server's rebalance log holds exactly as many `MSGID 109023` messages from `__dht_check_free_space` as that server skipped files: 105, 108 and 107. For `/drill7/f3.bin` (8 blocks of 512 bytes) the message gives the destination, `gv0-replicate-1`, 15,522,728 free blocks and the source, `gv0-replicate-0`, 16,040,816. The large files from earlier drills had already moved, which left set 2 with about 250 MiB less free space than set 1, so every small file processed after them was skipped.

**The skipped files were left reachable through link files.** Set 2 held 173 link files in `drill7`, 151 for `f` files and 22 for `late` files, created between 22:40:59.50 and 22:41:00.76. Each is a zero-byte `---------T` file whose `trusted.glusterfs.dht.linkto` is `gv0-replicate-0`. 173 is the number of `drill7`'s 350 names that hash into set 2's half. The data stayed on set 1, and clients reached it through the pointers.

**The forced rebalance placed every file by its hash.** `start force` moved 105, 127 and 107 files with 0 skipped and 0 failures. `drill7` then held 177 files on set 1 and 173 on set 2, with no link files left, and `drill7-newdir` was unchanged at 45 and 55. The layouts carried a new commit hash, `57096e02`.

**The second rebalance moved files back.** Of `gluster2`'s 127 moves in the forced pass, 53 were in `drill7` and 74 elsewhere. 13 of those went from set 2 back to set 1: 12 files in `drill3` and `/drill6/big.bin`, which is the 200.2 MB in `gluster2`'s total. `/drill3/f17.txt` and `/drill6/big.bin` had moved to set 2 in the first pass, at 22:40:49 and 22:40:58, and back to set 1 at 23:03:39 and 23:03:41. A file's name does not change, so the layouts of `drill3` and `drill6` must have changed between the passes. After the forced pass, `drill3` and `drill6` give set 1 the lower half of the range, while `drill7` gives it the upper half. Gluster 11.1 did not log the ranges it wrote, so the first pass's layout for those directories is not recorded.

**Placement can be read from the client.** `trusted.glusterfs.pathinfo` reports `drill7/f3.bin` on `gv0-replicate-1` (`gluster2` and `gluster1` `brick2`, `gluster3` `brick1`) and `drill7/f1.bin` on `gv0-replicate-0` (`gluster1` and `gluster2` `brick1`, `gluster3` `brick2`). `df` on the client reports 16G, one 8 GB brick per set, while each file still has three copies.

## Verification

The original 300 files, read from the client after both rebalances, digest to `58adce45…ff57`, the same value as the baseline. About half of them moved to set 2 between the two readings.

`drill7` per replica set, compared on all three servers after the forced rebalance:

| Set | Files | Digest | gluster1 | gluster2 | gluster3 |
|---|---|---|---|---|---|
| Set 1 | 177 | `c38046e9…4c9e1` | match (`brick1`) | match (`brick1`) | match (`brick2`) |
| Set 2 | 173 | `02540315…d8e6b` | match (`brick2`) | match (`brick2`) | match (`brick1`) |

The two sets hold 350 files between them, the 300 original files and the 50 `late` files, and the three copies in each set agree.

## Operational notes

- Read `rebalance status` for skipped files, not only for `completed`. A rebalance that skips files still reports success, and the skipped files are left behind link files.
- The reason for each skip is in `gv0-rebalance.log`. Here the free-space rule fired because large files moved first.
- `start force` overrides a check that exists to protect the new bricks from filling up. Check capacity before using it.
- A second rebalance is not a no-op for files already placed. Here it moved 200 MB back to the set they came from.
