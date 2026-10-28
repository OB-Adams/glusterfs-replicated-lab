# Milestones

Status values: Planned, In progress, Blocked, Complete. A milestone is marked Complete only when its acceptance criteria were actually met in the lab.

| # | Milestone | Status |
|---|---|---|
| 1 | Replicated cluster and failure drills | Complete |
| 2 | Brick replacement, expansion and rebalance | Complete |
| 3 | Security and monitoring | In progress |
| 4 | Benchmark baseline | Planned |
| 5 | Ansible automation | Planned |
| 6 | CephFS phase and comparison | Planned |

## Milestone 1: replicated cluster and failure drills

**Goal.** A working replica 3 GlusterFS volume built by hand, with its failure behaviour observed and documented.

**Changes.** Four VMs, LVM thin and XFS bricks, trusted pool, volume `gv0`, FUSE client, four failure drills, helper scripts, documentation.

**Concepts covered.** Bricks and volumes, glusterd versus brick processes, client-side replication (AFR), client and server quorum, self-heal and the index of pending entries, `network.ping-timeout`, split-brain and its resolution policies.

**Acceptance criteria and result.**

| Criterion | Result |
|---|---|
| Three peers connected, `gv0` started with three bricks online | Met, reported by the author |
| Client mounts the volume and files appear identically on all bricks | Met, reported by the author |
| Node loss during writes is survived and healed automatically | Met, output in `docs/evidence/drill1-heal-summary.txt` |
| Hard-failure client stall measured with two timeout values | Met, single run each, output archived |
| Quorum loss behaviour recorded from the client log | Met, log excerpt archived |
| Split-brain created and resolved with CLI policies | Met, output archived |
| Documentation matches what was done | Reviewed against the pasted outputs |

**Completion criteria.** Documentation committed, evidence archived, screenshots captured and embedded in the README.

## Milestone 2: brick replacement, expansion and rebalance

**Goal.** Replace a failed brick and heal it fully, then add a second brick per server to make the volume distributed-replicated and rebalance it.

| Step | Description | Status |
|---|---|---|
| 2a | Rebuild a destroyed brick at the same path with `reset-brick` | Complete |
| 2b | Replace a brick at a different path or host with `replace-brick` | Complete |
| 2c | Add a second brick per server (2 x 3) and rebalance | Complete |

**Acceptance criteria.**

- 2a: a destroyed brick is re-admitted and heals to a checksum-identical state.
- 2b: a brick is replaced at a different path or host and heals to a checksum-identical state.
- 2c: the volume shows `2 x 3` after expansion, a rebalance completes, and file placement is explained using the hash layout attributes on the bricks.

**2a result (2026-10-27).** Met. Both `reset-brick` steps and `heal full` returned `SUCCESS`. The heal did not start in the two minutes between the commit and the command; once issued, the full sweep took about 26 seconds. Both directories came back with matching file counts and digests on all three servers, including the rebuilt one. Full write-up in [brick-replacement.md](brick-replacement.md).

**2b result (2026-10-27).** Met. `gluster3`'s brick was moved from `/data/glusterfs/brick1/vol` to `/data/glusterfs/brick2/vol` on a new 10 GB disk with `replace-brick ... commit force`, while a client wrote 400 files. The heal started by itself 20 ms after the new brick connected, with no heal command, and the self-heal daemon finished about 36 seconds later. All four test directories came back with matching file counts and digests on all three servers. The client had no failed writes and no stall: the slowest of the 400 writes took 0.028 s. The old brick was left with its data and volume ID intact. Full write-up in [brick-replacement.md](brick-replacement.md#2b-move-to-a-new-disk-with-replace-brick).

**2c result (2026-10-27).** Met. `add-brick` first refused `gluster3`'s old brick because it still carried `gv0`'s volume ID; after the brick was wiped, the volume became `Distributed-Replicate`, `2 x 3 = 6`. Before any rebalance, the existing `drill7` directory gave the new set no range and new files in it stayed on set 1, while a directory created after the expansion was split 45/55. The first rebalance completed but skipped 320 files on the free-space rule (`__dht_check_free_space`), leaving 173 of `drill7`'s files behind link files. `rebalance start force` then moved every file to its hashed set, giving `drill7` 177 and 173 files per set with no link files, and also moved 13 files from earlier drills back to set 1. The original files' digest from the client was unchanged, and each set's three copies matched on all three servers. Full write-up in [expansion.md](expansion.md).

## Milestone 3: security and monitoring (in progress)

**Goal.** TLS for management and I/O traffic, access restriction with `auth.allow`, and metrics with alerts on heal backlog and brick state.

| Step | Description | Status |
|---|---|---|
| 3a | Access restriction with `auth.allow`, and mutual TLS for management and I/O traffic | Complete |
| 3b | Metrics, a dashboard, and alerts on heal backlog and brick state | Planned |

**Acceptance criteria.**

- 3a: a client without a valid certificate cannot mount.
- 3b: a dashboard and at least two alert rules are exercised by a drill.

**3a result (2026-10-28).** Met. `auth.allow` refused the client once its address was removed, and also dropped its existing mount at once. With a lab CA, a certificate per machine, `secure-access`, `client.ssl`, `server.ssl` and `auth.ssl-allow`, both 24007 and the brick ports speak TLS. A client with no certificate could not fetch the volfile, a self-signed certificate was refused at the TLS handshake (`certificate verify failed`), and a lab-signed certificate for a name not on `auth.ssl-allow` was refused by every brick. The real client mounted over TLS with the `drill7` digest unchanged. On this build the certificates must be in `/etc/pki/tls`; with them in `/etc/ssl`, `glusterd` could not load them and `volume start` failed until they were moved. Full write-up in [security.md](security.md).

## Milestone 4: benchmark baseline (planned)

**Goal.** `fio` profiles for sequential, random 4k, mixed and small-file workloads, with the exact profiles stored in the repository so phase 2 can reuse them.

**Acceptance criteria.** Results recorded with the caveat that absolute numbers on shared virtual storage are not meaningful.

## Milestone 5: Ansible automation (planned)

**Goal.** An idempotent role that rebuilds the lab from fresh VMs.

**Acceptance criteria.** Second run reports no changes. The result passes the same verification commands as the manual build.

## Milestone 6: CephFS phase and comparison (planned)

**Goal.** Tear down the Gluster configuration, wipe the disks (LVM stack and partition table), deploy Ceph with cephadm on the same VMs, run the same drills and the same `fio` profiles, and write a comparison.

**Acceptance criteria.** A comparison document covering operational complexity, failure behaviour and measured results, with the limits of the test setup stated.
