# Failure drills

Four drills run against the replica 3 volume `gv0`. Each section states the goal, how it was run, what was actually observed, and what remains unexplained. Raw output is in [evidence/](evidence).

Conventions: `gluster1` to `gluster3` are servers, `gluster4` is the client with the volume mounted at `/mnt/gv0`. Brick index in logs and attributes: `gv0-client-0` is gluster1, `client-1` is gluster2, `client-2` is gluster3.

Test environment details (OS release, Gluster version) are recorded in the README. All behaviour below applies to that version only.

## Drill 1: graceful node loss and self-heal

**Goal.** Show that a replica 3 volume keeps accepting writes with one node down, and that the returned node is repaired without manual action.

**Procedure.**

1. Baseline: all bricks online, `gluster volume heal gv0 info summary` shows no entries.
2. On the client, start a writer creating a small file every 0.5 seconds (see `scripts/drill-writer.sh`).
3. Power off `gluster3` cleanly while the writer runs.
4. Check the state from a surviving node.
5. Start `gluster3` again and watch the heal backlog fall.

**Observed.**

- The writer did not stop. With 2 of 3 bricks reachable, quorum was satisfied.
- During the outage, `gluster1` and `gluster2` each listed 273 pending entries and `gluster3` reported `Transport endpoint is not connected`. No entries were in split-brain. The surviving bricks hold the pending marks, which is why they report the entries and the returned brick does not.
- After `gluster3` returned, the backlog fell to 30 and 27 entries (one reported as possibly healing), then to zero. The self-heal daemon needed no commands.
- Post-heal verification (file counts and checksums across the bricks) was reported as matching. That output was not archived, so it is not in the evidence folder.

Evidence: [drill1-heal-summary.txt](evidence/drill1-heal-summary.txt).

**Concept.** The client writes to all bricks. A brick that misses a write leaves its peers with non-zero `trusted.afr.gv0-client-N` attributes. The self-heal daemon walks an index of such files on the bricks and copies the data to the stale one.

**Note on maintenance.** Stopping `glusterd` does not stop brick processes. Taking a node out of service properly means stopping the brick process (`glusterfsd`) as well.

## Drill 2: hard failure and `network.ping-timeout`

**Goal.** Measure what a client experiences when a node disappears without closing its connections.

**Procedure.**

1. Run the latency-recording writer on the client against a new directory.
2. Force-stop `gluster3` from the hypervisor (not a shutdown inside the guest).
3. Find the longest single write in the log.
4. Set `gluster volume set gv0 network.ping-timeout 10`, repeat in a new directory, then reset the option to its default.

**Observed.**

| Run | `network.ping-timeout` | Longest write | Typical write |
|---|---|---|---|
| drill2a | 42 s (default) | 70.323 s | 0.027 to 0.028 s |
| drill2b | 10 s | 13.215 s | 0.028 to 0.029 s |

- In each run exactly one write was slow. After the client dropped the dead brick, writes returned to normal speed.
- A shorter timeout shortened the stall.
- **Unexplained:** both stalls were longer than the configured timeout. A likely contributor is that the client checks liveness periodically rather than at the instant of silence, but that does not account for the size of the overshoot, and it was not verified. Each setting was measured once. Repeat several times before drawing conclusions.

Evidence: [drill2-write-latency.txt](evidence/drill2-write-latency.txt).

**Trade-off.** A low timeout shortens client stalls but makes the client more likely to declare a brick dead on a transient network problem. Reconnecting is costly because file descriptors and locks must be re-established. The default is deliberately conservative.

## Drill 3: quorum loss

**Goal.** See what happens when only one of three bricks remains.

**Procedure.**

1. Run a writer that logs success or failure for each file.
2. Shut down `gluster3`, wait, then shut down `gluster2`, both gracefully.
3. Inspect the client log, try reading, then try to mount again.
4. Start `gluster2` first, remount, then start `gluster3` and wait for the heal backlog to reach zero.

**Observed (client log).**

- 22:24:51: `gv0-client-2` disconnected. Nothing visible changed.
- 22:25:18: `gv0-client-1` disconnected and AFR logged `Client-quorum is not met`.
- From 22:25:19: every `STAT()` and `LOOKUP()` failed with `Transport endpoint is not connected`, and AFR logged `no read subvols for /`. Reads failed as well as writes.
- A new mount attempt with only `gluster1` up failed. The log shows the brick connecting, then `first lookup on root failed (Transport endpoint is not connected)`, then the mount unmounting itself.
- After `gluster2` was started, mounting worked and reads worked.

**Compared with the documentation.** The Gluster documentation describes a replica set that loses client quorum as becoming read-only. On the version tested here, the whole mount stopped responding. The log lines above are the evidence. The difference has not been investigated further, so treat it as the behaviour of this version, not a general statement.

Evidence: [drill3-client-quorum-log.txt](evidence/drill3-client-quorum-log.txt).

**Why it matters.** A lone brick cannot know whether it missed writes made while it was isolated. Serving it could return stale data silently. Majority quorum is the mechanism that prevents two isolated halves from both accepting writes.

## Drill 4: split-brain creation and resolution

**Goal.** Create a real split-brain on a throwaway file and resolve it with each Gluster policy.

This drill disables the protections that normally prevent split-brain. Run it only on a throwaway file in a lab.

**Procedure.**

1. Set `cluster.quorum-type none` and turn off the self-heal daemon and the client-side heal options.
2. Create `/drill4/victim.txt` and confirm it is on all bricks.
3. Hold `gluster2` and `gluster3` down by stopping `glusterd` and killing `glusterfsd` on each. Write version A from the client, which reaches only `gluster1`.
4. Stop `gluster1` the same way, start `glusterd` on `gluster2`, and write version B, which reaches only `gluster2`.
5. Start `gluster1` and `gluster3` again. Capture the xattrs and file contents from each brick.
6. Resolve with the CLI policies, then restore the settings.

**Observed.**

- With peers down, `glusterd` on `gluster2` did not start its brick: `gluster volume status` showed the brick offline. `gluster volume start gv0 force` was needed. The cause was not established.
- After the nodes were back, the client that had written version B still read version B. After unmounting and mounting again, reading the file gave `Input/output error`. A mount with a warm cache can hide a split-brain.
- Policy results on the second, controlled run:
  - `bigger-file`: `No bigger file` (both versions had the same length).
  - `latest-mtime`: `No difference in mtime`. This surprised me, and the reason was not investigated.
  - `source-brick gluster1:/data/glusterfs/brick1/vol /drill4/victim.txt`: `Healed`.
- In the first attempt, manual heals reported `File not in split-brain`. That attempt was made after quorum and self-heal settings had been restored. When the test was redone with the manual resolution run first, the file was reported as split-brain and the policies behaved as above. The documented rule that comes out of this: capture evidence and resolve split-brain before changing cluster settings.

Evidence: [drill4-split-brain-resolution.txt](evidence/drill4-split-brain-resolution.txt), [drill4-gluster2-brick-offline.txt](evidence/drill4-gluster2-brick-offline.txt).

**Operator practice.** Before resolving, copy each brick's version of the file somewhere safe. Resolution overwrites the losing copy. Deciding which version is correct is a decision about the application's data, which Gluster cannot make.

**Reference.** [Resolving split-brain](https://docs.gluster.org/en/latest/Troubleshooting/resolving-splitbrain/) lists the policies and the heal info commands used.

## Related and not yet done

Destroying a brick and rebuilding it in place with `reset-brick`, and the full heal that follows, is drill 5 in [brick-replacement.md](brick-replacement.md). Moving a brick to a new disk with `replace-brick` is drill 6 in the same document. Adding a second replica set, rebalancing and examining file placement is drill 7 in [expansion.md](expansion.md).

Still to do:

- Repeating the timing measurements several times.
- Re-running the drills with TLS enabled.
