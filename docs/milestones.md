# Milestones

Status values: Planned, In progress, Blocked, Complete. A milestone is marked Complete only when its acceptance criteria were actually met in the lab.

| # | Milestone | Status |
|---|---|---|
| 1 | Replicated cluster and failure drills | Complete |
| 2 | Brick replacement, expansion and rebalance | Planned |
| 3 | Security and monitoring | Planned |
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

**Not verified.**

- Post-heal file counts and checksums for drill 1 were checked but the output was not archived.
- Timing measurements are single runs.
- Overshoot of the drill 2 stalls beyond the timeout is unexplained.
- Why `latest-mtime` reported no difference in drill 4 is unexplained.
- Behaviour was observed on one OS release and one Gluster version only.
- SELinux enforcing and firewalld running were configured as documented, but the output of `getenforce` and `firewall-cmd --state` was not recorded.
- Screenshots have not been captured yet.

**Completion criteria.** Documentation committed, evidence archived, screenshot checklist ready. Screenshots to be added as a follow-up commit.

## Milestone 2: brick replacement, expansion and rebalance (planned)

**Goal.** Replace a failed brick and heal it fully, then add a second brick per server to make the volume distributed-replicated and rebalance it.

**Acceptance criteria.**

- A wiped brick is replaced with `replace-brick` and heals to a checksum-identical state.
- The volume shows `2 x 3` after expansion and a rebalance completes.
- File placement is explained using the hash layout attributes on the bricks.

## Milestone 3: security and monitoring (planned)

**Goal.** TLS for management and I/O traffic, access restriction with `auth.allow`, and metrics with alerts on heal backlog and brick state.

**Acceptance criteria.**

- A client without a valid certificate cannot mount.
- A dashboard and at least two alert rules are exercised by a drill.

## Milestone 4: benchmark baseline (planned)

**Goal.** `fio` profiles for sequential, random 4k, mixed and small-file workloads, with the exact profiles stored in the repository so phase 2 can reuse them.

**Acceptance criteria.** Results recorded with the caveat that absolute numbers on shared virtual storage are not meaningful.

## Milestone 5: Ansible automation (planned)

**Goal.** An idempotent role that rebuilds the lab from fresh VMs.

**Acceptance criteria.** Second run reports no changes. The result passes the same verification commands as the manual build.

## Milestone 6: CephFS phase and comparison (planned)

**Goal.** Tear down the Gluster configuration, wipe the disks (LVM stack and partition table), deploy Ceph with cephadm on the same VMs, run the same drills and the same `fio` profiles, and write a comparison.

**Acceptance criteria.** A comparison document covering operational complexity, failure behaviour and measured results, with the limits of the test setup stated.
