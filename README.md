# glusterfs-replicated-lab

A hands-on GlusterFS lab: a three-node replica 3 volume built from scratch on Linux VMs and taken through nine recorded drills. They cover failure (graceful node loss, hard failure, quorum loss and split-brain), brick rebuild and replacement, expansion to a distributed-replicated volume with rebalancing, mutual TLS with certificate-based client authorisation, and Prometheus and Grafana monitoring with alerts. Every drill has captured evidence and operational notes. A `fio` benchmark baseline, with the job files kept in the repository, measures the volume against the raw filesystem under it.

This is phase 1 of a storage study. Phase 2 will rebuild the same VMs as a CephFS cluster and compare the two systems under the same tests.

## Project status

| Item | Status |
|---|---|
| Milestone 1: replicated cluster and failure drills | Complete |
| Milestone 2a: brick rebuild with `reset-brick` | Complete |
| Milestone 2b: `replace-brick` to a new disk | Complete |
| Milestone 2c: expansion to 2 x 3 and rebalance | Complete |
| Milestone 3a: `auth.allow` and mutual TLS | Complete |
| Milestone 3b: monitoring and alerts | Complete |
| Milestone 4: `fio` benchmark baseline | Complete |
| Raw evidence (command output and log excerpts) | Added in [docs/evidence](docs/evidence) |
| Screenshots | Added in [screenshots/](screenshots) (see [Screenshots and evidence](#screenshots-and-evidence)) |
| Ansible automation of the build | Planned |
| CephFS phase and comparison | Planned |

The full tracker is in [docs/milestones.md](docs/milestones.md). Anything not listed as complete is not implemented.

## Key results

| Drill | What happened |
|---|---|
| 1. Graceful node loss | Writes continued with 2 of 3 bricks; the 273-entry heal backlog cleared on return with no commands |
| 2. Hard failure | The worst client write stall was 70.3 s at the default `network.ping-timeout` of 42 s, and 13.2 s at 10 s; normal writes took about 28 ms |
| 3. Quorum loss | With 2 of 3 nodes down the mount became unusable for reads too, not read-only as the documentation describes |
| 4. Split-brain | `bigger-file` and `latest-mtime` both refused; resolved by choosing a source brick |
| 5. Brick rebuild | A destroyed brick re-admitted with `reset-brick` healed in about 26 s, with matching digests on all three servers |
| 6. Brick move | `replace-brick` to a new disk healed the whole volume in about 36 s, with no stall for a writing client |
| 7. Expansion | After `add-brick` to 2 x 3, the first rebalance skipped 320 files on its free-space check; a forced rebalance moved them |
| 8. Mutual TLS | Clients with no certificate, a self-signed one, or a valid certificate for an unlisted name were refused at three different layers |
| 9. Monitoring | A crashed brick raised a brick-down alert in about 1 minute and a heal-backlog alert in about 2.5 minutes; both resolved on recovery |

| Benchmark | Through Gluster | Raw XFS under a brick |
|---|---|---|
| Random 4 KiB read / write | 12,260 / 3,278 IOPS | 154,184 / 133,920 IOPS |
| Sequential 1 MiB read / write | 847 / 199 MiB/s | 21,703 / 18,804 MiB/s |
| Small files created | 322 per second | 31,128 per second |

Medians of three runs with 64 requests in flight. The raw figures run largely at the speed of the host's memory, so only the comparisons mean anything; see [docs/benchmark.md](docs/benchmark.md).

## A note on GlusterFS today

Upstream GlusterFS development has slowed and Red Hat's commercial Gluster Storage product has reached the end of its support lifecycle. Check the current state at the [project roadmap](https://www.gluster.org/roadmap/) before relying on it. This lab is about understanding how a replicated distributed filesystem behaves (quorum, self-heal, split-brain) and how to operate one. It is not a recommendation to start new production deployments on Gluster. Phase 2 exists to compare it with Ceph.

## Objectives

- Build a replicated Gluster volume manually so every layer is understood: disks, LVM, XFS, bricks, trusted pool, volume, client mount.
- Observe real failure behaviour instead of describing it from documentation.
- Record what was measured, what surprised me, and what remains unexplained.
- Keep procedures reproducible, then automate them in a later milestone.

## Features implemented

- Three-server trusted storage pool with one volume (`gv0`), replica 3, distributed over two replica sets since milestone 2c.
- Bricks on LVM thin volumes formatted XFS with 512-byte inodes, mounted by `/etc/fstab`, labelled for SELinux.
- FUSE client on a separate VM with backup volfile servers.
- Four failure drills with real output: graceful node loss and self-heal, hard failure and `network.ping-timeout`, quorum loss, split-brain creation and resolution.
- A brick rebuild drill: the brick on one server destroyed, rebuilt empty at the same path, re-admitted with `reset-brick`, and repaired by the self-heal daemon.
- A brick move drill: the brick on one server moved to a new disk with `replace-brick` while a client keeps writing, then filled by the self-heal daemon.
- An expansion drill: a second replica set added with `add-brick`, file placement traced through the hash layout on the bricks, a rebalance that skipped files on the free-space rule, and a forced rebalance.
- Access control and encryption: client addresses restricted with `auth.allow`, and mutual TLS with a lab certificate authority on both the management and data planes, with clients authorised by certificate name.
- Monitoring: brick, heal and peer metrics from each server through `node_exporter`, Prometheus and Grafana on the client VM with a provisioned dashboard, and five alert rules, two of them exercised by crashing a brick.
- A benchmark baseline: six `fio` profiles (sequential, random 4 KiB, mixed, small files) run three times each through the client and on the raw filesystem under a brick, with a runner and a summary script that phase 2 reuses unchanged.
- Helper scripts for health checks, latency-measuring writers and brick comparison.

## Architecture

```mermaid
flowchart LR
    subgraph clientvm["Client VM"]
        C["gluster4<br/>FUSE client<br/>mounted at /mnt/gv0"]
    end
    subgraph pool["Trusted storage pool: volume gv0, 2 x 3"]
        N1["gluster1<br/>glusterd + 2 bricks"]
        N2["gluster2<br/>glusterd + 2 bricks"]
        N3["gluster3<br/>glusterd + 2 bricks"]
    end
    C -->|"24007/tcp: volfile fetched at mount"| N1
    C -->|"brick ports: data to every brick"| N1
    C -->|"brick ports: data to every brick"| N2
    C -->|"brick ports: data to every brick"| N3
    N1 <-->|"24007/tcp: management"| N2
    N2 <-->|"24007/tcp: management"| N3
    N1 <-->|"24007/tcp: management"| N3
```

More diagrams (write path, availability states, monitoring) are in [docs/architecture.md](docs/architecture.md).

### How it works

- Each server runs `glusterd`, the management daemon. It listens on 24007/tcp and keeps the pool configuration in sync. It does not carry file data.
- Each brick has its own `glusterfsd` process on its own port (allocated from 49152 upward by default). These serve the data.
- The FUSE client contacts one server to download the volume description (volfile), then talks to all three bricks directly. Replication is performed by the client: every write goes to all three bricks, so client bandwidth for writes is roughly three times the data size.
- With replica 3, client-side quorum (`cluster.quorum-type auto`) requires 2 of 3 bricks to be reachable.
- When a brick misses a write, the other bricks record that fact in extended attributes (`trusted.afr.gv0-client-N`). The self-heal daemon uses those records to repair the brick when it returns.

## Technology stack and design decisions

| Choice | Reason |
|---|---|
| Replica 3 | A majority always exists with one failure, so quorum can prevent split-brain. Two-way replicas without an arbiter cannot do this safely. |
| XFS with `-i size=512` | Gluster stores much of its state in extended attributes, and the larger inode keeps them inline. XFS is the filesystem Gluster is tested and documented against. |
| LVM thin pool under each brick | Gluster volume snapshots rely on LVM thin provisioning. Also lets the brick grow later. |
| Brick in a subdirectory (`.../brick1/vol`) | If the LV fails to mount, the subdirectory is missing and Gluster refuses to start the brick, instead of silently writing to the root disk. |
| SELinux enforcing, firewalld enabled | Lab shortcuts such as disabling them hide the configuration needed in a real system. |
| Native FUSE client | Connects to all bricks directly and handles failover, unlike a single-server NFS export. |

## Repository structure

```text
glusterfs-replicated-lab/
├── README.md
├── LICENSE
├── .gitignore
├── benchmarks/
│   ├── README.md
│   ├── run-bench.sh
│   ├── summarize.py
│   └── fio/
│       ├── mixed-70-30.fio
│       ├── rand-read-4k.fio
│       ├── rand-write-4k.fio
│       ├── seq-read.fio
│       ├── seq-write.fio
│       └── small-files.fio
├── docs/
│   ├── architecture.md
│   ├── benchmark.md
│   ├── brick-replacement.md
│   ├── build-guide.md
│   ├── expansion.md
│   ├── failure-drills.md
│   ├── milestones.md
│   ├── monitoring.md
│   ├── security.md
│   ├── troubleshooting.md
│   └── evidence/
│       ├── benchmark/
│       │   ├── results.md
│       │   ├── gluster-fuse/   (18 fio JSON files)
│       │   └── raw-xfs/        (18 fio JSON files)
│       ├── benchmark-session-gluster1.txt
│       ├── benchmark-session-gluster4.txt
│       ├── drill1-heal-summary.txt
│       ├── drill2-write-latency.txt
│       ├── drill3-client-quorum-log.txt
│       ├── drill4-gluster2-brick-offline.txt
│       ├── drill4-split-brain-resolution.txt
│       ├── drill5-logs.txt
│       ├── drill5-session-gluster1.txt
│       ├── drill5-session-gluster2.txt
│       ├── drill5-session-gluster3.txt
│       ├── drill6-logs.txt
│       ├── drill6-session-gluster1.txt
│       ├── drill6-session-gluster2.txt
│       ├── drill6-session-gluster3.txt
│       ├── drill6-session-gluster4.txt
│       ├── drill7-logs.txt
│       ├── drill7-session-gluster1.txt
│       ├── drill7-session-gluster2.txt
│       ├── drill7-session-gluster3.txt
│       ├── drill7-session-gluster4.txt
│       ├── drill8-logs.txt
│       ├── drill9-alerts.txt
│       ├── drill9-logs.txt
│       ├── drill9-session-gluster1.txt
│       ├── drill9-session-gluster2.txt
│       ├── drill9-session-gluster3.txt
│       └── drill9-session-gluster4.txt
├── monitoring/
│   ├── README.md
│   ├── grafana/
│   │   ├── dashboards/gluster-gv0.json
│   │   └── provisioning/
│   │       ├── dashboards/gluster.yml
│   │       └── datasources/prometheus.yml
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── rules/gluster.yml
│   └── systemd/
│       ├── gluster-metrics.service
│       ├── gluster-metrics.timer
│       └── node_exporter.service
├── scripts/
│   ├── check-cluster.sh
│   ├── compare-bricks.sh
│   ├── drill-writer.sh
│   └── gluster-metrics.sh
└── screenshots/
    ├── README.md
    ├── 01-brick-layout-lvm-xfs-selinux.png
    ├── 02-pool-and-volume-status.png
    ├── 03-client-mount-and-replicas.png
    ├── 04-drill1-heal-pending.png
    ├── 04-drill1-heal-recovered.png
    ├── 05-drill2-write-stall-latency.png
    ├── 06-drill3-client-quorum-lost-log.png
    ├── 07-drill4-split-brain-eio.png
    ├── 07-drill4-split-brain-xattrs.png
    ├── 08-drill4-source-brick-resolution.png
    ├── 09-drill5-brick-rebuilt-empty.png
    ├── 10-drill5-heal-progress.png
    ├── 11-drill5-digests-match.png
    ├── 12-drill5-reset-brick-logs.png
    ├── 13-drill6-new-brick-ready.png
    ├── 14-drill6-replace-brick-commit.png
    ├── 15-drill6-heal-from-shd-log.png
    ├── 16-drill6-digests-match.png
    ├── 17-drill7-old-brick-refused.png
    ├── 18-drill7-volume-expanded.png
    ├── 19-drill7-layout-before-rebalance.png
    ├── 20-drill7-rebalance-skipped.png
    ├── 21-drill7-layout-after-rebalance.png
    ├── 22-drill7-skip-and-link-file.png
    ├── 23-drill7-rebalance-force-completed.png
    ├── 24-drill7-layout-after-force.png
    ├── 25-drill7-client-placement.png
    ├── 26-drill7-set-digests.png
    ├── 27-drill8-auth-allow-refused.png
    ├── 28-drill8-certificates.png
    ├── 29-drill8-tls-enabled.png
    ├── 30-drill8-tls-on-the-wire.png
    ├── 31-drill8-no-certificate-refused.png
    ├── 32-drill8-rogue-certificate-refused.png
    ├── 33-drill8-wrong-cn-refused.png
    ├── 34-drill8-valid-mount.png
    ├── 35-drill9-gluster-metrics.png
    ├── 36-drill9-prometheus-targets.png
    ├── 37-drill9-alert-rules.png
    ├── 38-drill9-dashboard-healthy.png
    ├── 39-drill9-brick-killed.png
    ├── 40-drill9-alerts-firing.png
    ├── 41-drill9-dashboard-incident.png
    ├── 42-drill9-brick-recovered.png
    ├── 43-drill9-dashboard-recovered.png
    ├── 44-drill9-set-digests.png
    ├── 45-bench-direct-io-check.png
    ├── 46-bench-raw-run.png
    ├── 47-bench-gluster-run.png
    └── 48-bench-results.png
```

## Prerequisites

- A hypervisor (this lab used UTM on an Apple Silicon Mac with virtualized aarch64 guests).
- Four Linux VMs: three storage servers and one client. This lab used 4 GB RAM each.
- Two extra virtual disks on each server, one per brick. The first build uses one; the second was added for milestones 2b and 2c.
- Hostnames resolvable on every VM (this lab used `/etc/hosts`) and working time synchronisation (chrony).
- Outbound internet access on the VMs to install packages.

## Environment

| Item | Value |
|---|---|
| Hypervisor | UTM, virtualization mode (not emulation) |
| Guest architecture | aarch64 |
| Guest OS | CentOS Stream 9 |
| GlusterFS version | 11.1 |
| Servers | `gluster1`, `gluster2`, `gluster3` |
| Client | `gluster4` |

The behaviour recorded in the drills applies to this OS release and Gluster version only.

## Configuration and variables

| Name | Value used |
|---|---|
| Volume group | `vg_gluster` |
| Thin pool | `thinpool` |
| Brick logical volume | `brick1` |
| Brick mount point | `/data/glusterfs/brick1` |
| Brick path (directory used in the volume) | `/data/glusterfs/brick1/vol` |
| Volume name | `gv0` |
| Client mount point | `/mnt/gv0` |
| Physical volume | `/dev/vdb1` (a partition on the extra disk) |
| Second disk, from milestones 2b and 2c | `/dev/vdc1`, volume group `vg_gluster2`, thin pool `thinpool`, thin LV `brick2`, mounted at `/data/glusterfs/brick2` |
| Replica set 1 | `brick1` on `gluster1` and `gluster2`, `brick2` on `gluster3` |
| Replica set 2 | `brick2` on `gluster1` and `gluster2`, `brick1` on `gluster3` |
| TLS files, from milestone 3a | `/etc/pki/tls/glusterfs.key`, `glusterfs.pem` and `glusterfs.ca` on every machine |
| Management TLS switch | `/var/lib/glusterd/secure-access` on every machine |
| Access lists | `auth.allow`: the four lab addresses; `auth.ssl-allow`: `gluster1,gluster2,gluster3,gluster4` |
| Metrics, from milestone 3b | `node_exporter` on 9100 (open to `gluster4` only), `gluster-metrics.sh` every 30 s via `gluster-metrics.timer`, textfile directory `/var/lib/node_exporter/textfile` |
| Monitoring on `gluster4` | Prometheus on 9090 and Grafana on 3000, Podman containers configured from `/opt/monitoring` ([monitoring/](monitoring)) |

Disk and pool sizes are not fixed by this lab. Size them to your disks, and keep the thin LV's virtual size below the pool size so the pool cannot be overcommitted by accident.

## Installation and deployment

The complete step-by-step procedure with the reasoning for each step is in [docs/build-guide.md](docs/build-guide.md). In outline:

1. Prepare the VMs: hostnames, `/etc/hosts`, chrony, firewall service `glusterfs`.
2. On each server: PV, VG, thin pool, thin LV, XFS, fstab mount, brick subdirectory, SELinux label.
3. Install `centos-release-gluster*` and `glusterfs-server`, enable `glusterd`.
4. From `gluster1`: `gluster peer probe`, then probe `gluster1` back from another node by name.
5. Create and start the replica 3 volume `gv0`.
6. On the client: install `glusterfs-fuse` and mount with `backup-volfile-servers`.

## Verification and testing

On any server:

```bash
sudo gluster pool list
sudo gluster volume status gv0
sudo gluster volume heal gv0 info summary
sudo gluster volume get gv0 cluster.quorum-type
```

Expected: all three peers `Connected`, three bricks `Online`, zero heal entries, quorum type `auto`.

On the client, write a file and confirm it exists on every brick with the same content:

```bash
echo "hello gluster" | sudo tee /mnt/gv0/hello.txt
```

```bash
# on each server
cat /data/glusterfs/brick1/vol/hello.txt
```

The drills in [docs/failure-drills.md](docs/failure-drills.md), [docs/brick-replacement.md](docs/brick-replacement.md), [docs/expansion.md](docs/expansion.md) and [docs/security.md](docs/security.md) are the main tests.

## Operational commands

```bash
./scripts/check-cluster.sh gv0                                   # on a server: pool, bricks, heal and quorum summary
./scripts/drill-writer.sh /mnt/gv0/test 300 0.5 latency.log      # on the client: steady writes with per-write latency
./scripts/compare-bricks.sh /data/glusterfs/brick1/vol/test      # on each server: file count and combined checksum
cat /var/lib/node_exporter/textfile/gluster.prom                 # on a server: the Gluster metrics last written
curl -s gluster1:9100/metrics | grep '^gluster_'                 # on gluster4: what Prometheus scrapes
curl -s localhost:9090/api/v1/alerts | python3 -m json.tool      # on gluster4: current alert state
```

The dashboard is at `http://<gluster4>:3000` (Dashboards → Gluster → Gluster gv0) and Prometheus at `http://<gluster4>:9090`.

## Security considerations

- SELinux is enforcing and firewalld is on. On the servers, only the predefined `glusterfs` service is open, plus 9100 for metrics from `gluster4` only.
- All Gluster traffic uses mutual TLS with a lab certificate authority, on the management plane (`glusterd`, 24007) and the data plane (brick ports). Clients must hold a certificate signed by the lab CA, and their certificate name must be on `auth.ssl-allow`. Client addresses are also restricted with `auth.allow`. Details and the refusal tests are in [docs/security.md](docs/security.md).
- The lab CA's private key stays on `gluster1` and is not in this repository. The certificates expire on 2027-10-28.
- Prometheus (9090) and Grafana (3000) on `gluster4` use plain HTTP, and Prometheus has no authentication. The Grafana admin password was entered at a prompt and is not stored in any file.
- Lab commands are run as root or with `sudo` for convenience. A real deployment should separate administrative access.
- The split-brain drill deliberately disables quorum and self-heal. That configuration is for a throwaway file in a lab and must be reverted afterwards.

## Troubleshooting

Issues actually encountered, with causes and fixes, are in [docs/troubleshooting.md](docs/troubleshooting.md). Highlights:

| Symptom | Where it was seen |
|---|---|
| New mount fails while only one of three nodes is up | Drill 3 |
| Brick shows `Online: N` after `glusterd` starts, with peers down | Drill 4 |
| Write stalls for tens of seconds after a node is force-stopped | Drill 2 |
| A split-brain file reads normally on a long-lived mount | Drill 4 |
| Manual heal says `File not in split-brain` | Drill 4 |
| `glusterd` cannot load its certificate and `volume start` fails after enabling TLS | Drill 8 |

## Cleanup and recovery

Teardown destroys the data. Only do this in the lab.

```bash
# client
sudo umount /mnt/gv0

# any server
sudo gluster volume stop gv0 --mode=script
sudo gluster volume delete gv0 --mode=script
sudo gluster peer detach gluster2
sudo gluster peer detach gluster3
```

Do not reuse a brick directory after deleting a volume: it keeps volume identity attributes and Gluster will refuse to reuse it. Recreate the filesystem instead (`mkfs.xfs -f -i size=512`) or remove the logical volumes entirely.

Recovery procedures for node failure, hard failure, quorum loss and split-brain are documented as drills in [docs/failure-drills.md](docs/failure-drills.md). Rebuilding a destroyed brick and moving a brick to a new disk are in [docs/brick-replacement.md](docs/brick-replacement.md). Adding a replica set and rebalancing are in [docs/expansion.md](docs/expansion.md).

## Screenshots and evidence

Raw command output and log excerpts from the drills are in [docs/evidence](docs/evidence). The screenshots below are from the running lab. The commands used to produce each one are listed in [screenshots/README.md](screenshots/README.md).

### Build and verification

![Brick layout on a storage server](screenshots/01-brick-layout-lvm-xfs-selinux.png)

*Brick layout on a storage server: LVM thin pool and thin volume, XFS mounted at the brick path, and the SELinux label on the brick directory.*

![Trusted pool and replica 3 volume status](screenshots/02-pool-and-volume-status.png)

*Trusted pool and volume `gv0`: three peers connected, replica 3, three bricks online.*

![Client mount and replicas](screenshots/03-client-mount-and-replicas.png)

*Client mount of `gv0` and the same files present on every brick.*

### Drill 1: graceful node loss ([details](docs/failure-drills.md#drill-1-graceful-node-loss-and-self-heal))

![Heal backlog during the outage](screenshots/04-drill1-heal-pending.png)

*`gluster volume heal gv0 info summary` while one node is down: the surviving bricks list entries pending heal and the stopped node is unreachable.*

![Heal backlog after recovery](screenshots/04-drill1-heal-recovered.png)

*The same command after the node returned: the backlog is repaired by the self-heal daemon without manual commands.*

### Drill 2: hard failure ([details](docs/failure-drills.md#drill-2-hard-failure-and-networkping-timeout))

![Write stall at two ping-timeout settings](screenshots/05-drill2-write-stall-latency.png)

*Longest write in each run against normal write times, at the default `network.ping-timeout` and at a shorter value. Exact figures from the original runs are in [drill2-write-latency.txt](docs/evidence/drill2-write-latency.txt).*

### Drill 3: quorum loss ([details](docs/failure-drills.md#drill-3-quorum-loss))

![Client log when quorum is lost](screenshots/06-drill3-client-quorum-lost-log.png)

*Client mount log: the quorum-not-met message, then lookups failing with `Transport endpoint is not connected`.*

### Drill 4: split-brain ([details](docs/failure-drills.md#drill-4-split-brain-creation-and-resolution))

![Input/output error on a split-brain file](screenshots/07-drill4-split-brain-eio.png)

*Reading the split-brain file from a fresh mount returns `Input/output error`.*

![Conflicting replication attributes](screenshots/07-drill4-split-brain-xattrs.png)

*`getfattr` output from the bricks showing the conflicting `trusted.afr.gv0-client-N` blame attributes.*

![Split-brain resolution with CLI policies](screenshots/08-drill4-source-brick-resolution.png)

*The `bigger-file` and `latest-mtime` policies refusing, then `source-brick` healing the file.*

### Drill 5: brick rebuild ([details](docs/brick-replacement.md))

![The rebuilt brick before it is re-admitted](screenshots/09-drill5-brick-rebuilt-empty.png)

*Rebuilding the brick on `gluster3`: a new thin volume, XFS, the mount, the SELinux relabel, and an empty `vol` directory holding nothing but `.` and `..`.*

![Heal progress after heal full](screenshots/10-drill5-heal-progress.png)

*`heal full`, then `heal info summary` with entries pending on the two source bricks and none on the rebuilt one, then the same command reporting zero everywhere.*

![Digests compared across the three servers](screenshots/11-drill5-digests-match.png)

*Both directories compared on `gluster1`, `gluster2` and `gluster3` after the rebuild: 151 files and 100 files, each with the same digest on every server.*

![Gluster command log and self-heal daemon log](screenshots/12-drill5-reset-brick-logs.png)

*Gluster's own logs on `gluster3`: the `reset-brick` start and commit and the `heal full` command, and the full sweep on the rebuilt brick.*

### Drill 6: brick moved to a new disk ([details](docs/brick-replacement.md#2b-move-to-a-new-disk-with-replace-brick))

![The new brick before replace-brick](screenshots/13-drill6-new-brick-ready.png)

*The new brick on `gluster3`'s second disk: XFS on `vg_gluster2/brick2` mounted at `/data/glusterfs/brick2`, and an empty `vol` directory with the `glusterd_brick_t` label and no Gluster attributes.*

![replace-brick commit and the new brick path](screenshots/14-drill6-replace-brick-commit.png)

*`replace-brick ... commit force` succeeding, `Brick3` now on `/data/glusterfs/brick2/vol` and already online, and the commit recorded in Gluster's command history.*

![Self-heal daemon log after replace-brick](screenshots/15-drill6-heal-from-shd-log.png)

*The self-heal daemon log on `gluster1`: the new brick attaching 20 ms after the commit shown above, and the heal of the root directory starting by itself a tenth of a second later.*

![Digests compared across the three servers](screenshots/16-drill6-digests-match.png)

*All four test directories compared on `gluster1`, `gluster2` and `gluster3` after the move, with the same counts and digests on every server.*

### Drill 7: expansion to 2 x 3 and rebalance ([details](docs/expansion.md))

![add-brick refusing the old brick](screenshots/17-drill7-old-brick-refused.png)

*`gluster3`'s old brick still carries `gv0`'s volume ID, so `add-brick` refuses it: `already part of a volume`.*

![The volume expanded to 2 x 3](screenshots/18-drill7-volume-expanded.png)

*After the old brick is wiped, `add-brick` succeeds and `gv0` becomes `Distributed-Replicate`, `2 x 3 = 6`, with Brick4 to Brick6 forming the second set.*

![Layouts and file counts before the rebalance](screenshots/19-drill7-layout-before-rebalance.png)

*Before any rebalance: the existing `drill7` gives set 2 an all-zero range and all 350 files are on set 1, while `drill7-newdir`, created after the expansion, is split in half with 45 and 55 files.*

![First rebalance with skipped files](screenshots/20-drill7-rebalance-skipped.png)

*The first rebalance reports `completed` with 0 failures, but 105, 108 and 107 files skipped.*

![Layouts after the first rebalance](screenshots/21-drill7-layout-after-rebalance.png)

*After the first rebalance, `drill7`'s layout is split and carries commit hash `570942e4`, yet all 350 files are still on set 1.*

![The skip reason and a link file](screenshots/22-drill7-skip-and-link-file.png)

*The rebalance log's free-space skip for `drill7/f3.bin`, and the zero-byte `---------T` link file left on set 2, pointing to `gv0-replicate-0`.*

![Forced rebalance completed](screenshots/23-drill7-rebalance-force-completed.png)

*`rebalance start force`: 105, 127 and 107 files moved, 0 skipped, 0 failures.*

![Layouts and file counts after the forced rebalance](screenshots/24-drill7-layout-after-force.png)

*After the forced rebalance: commit hash `57096e02`, `drill7` at 177 and 173 files per set, and no link files left.*

![File placement seen from the client](screenshots/25-drill7-client-placement.png)

*From the client, `pathinfo` places `f3.bin` on set 2 and `f1.bin` on set 1, each with its three bricks, and `df` reports 16G.*

![Per-set digests on the three servers](screenshots/26-drill7-set-digests.png)

*`drill7` per set on all three servers: set 1 holds 177 files and set 2 holds 173, and each set's digest is identical on every server.*

### Drill 8: access control and TLS ([details](docs/security.md))

![Mount refused by auth.allow](screenshots/27-drill8-auth-allow-refused.png)

*With the client's address removed from `auth.allow`, the bricks refuse its mount: `Authentication failed`, then `AUTH_FAILED`.*

![The lab CA and certificates](screenshots/28-drill8-certificates.png)

*Five certificates verify against the lab CA; the self-signed `rogue` certificate fails. Subjects and issuers show who signed each.*

![TLS enabled on the volume](screenshots/29-drill8-tls-enabled.png)

*`client.ssl` and `server.ssl` on, the two allow lists (addresses redacted), the certificate files and `secure-access` in place, and six bricks and three self-heal daemons online.*

![TLS on the management and brick ports](screenshots/30-drill8-tls-on-the-wire.png)

*`openssl s_client` from the client: `glusterd` on 24007 and a brick port both present `gluster1`'s certificate, issued by the lab CA, and it verifies.*

![Mount without a certificate](screenshots/31-drill8-no-certificate-refused.png)

*With no certificate, the client cannot start TLS and fails to fetch the volume file.*

![Mount with a self-signed certificate](screenshots/32-drill8-rogue-certificate-refused.png)

*A self-signed certificate claiming to be `gluster4` is rejected at the handshake: `alert unknown ca`.*

![Mount with a certificate for the wrong name](screenshots/33-drill8-wrong-cn-refused.png)

*A lab-signed certificate for `intruder` passes TLS, then every brick refuses it: `Authentication failed`.*

![Mount with the real certificate](screenshots/34-drill8-valid-mount.png)

*With its own certificate the client mounts over TLS, writes a file, and the `drill7` digest is unchanged.*

### Drill 9: monitoring and alerts ([details](docs/monitoring.md))

![Gluster metrics served by an exporter](screenshots/35-drill9-gluster-metrics.png)

*The `gluster_` metrics served by `gluster1`'s `node_exporter`: six bricks up, heal and split-brain counts at 0, peers connected.*

![Prometheus targets](screenshots/36-drill9-prometheus-targets.png)

*Prometheus scraping the three servers, all `UP`.*

![Alert rules loaded](screenshots/37-drill9-alert-rules.png)

*The five Gluster alert rules loaded, all inactive.*

![Dashboard before the incident](screenshots/38-drill9-dashboard-healthy.png)

*The provisioned Grafana dashboard before the crash: 6 bricks online, nothing pending, no alerts.*

![A brick process killed](screenshots/39-drill9-brick-killed.png)

*`gluster3`'s set 2 brick process killed with `kill -9`, and `volume status` showing it offline.*

![Both alerts firing](screenshots/40-drill9-alerts-firing.png)

*Prometheus with `GlusterBrickDown` firing for the crashed brick and `GlusterHealBacklog` firing for the two surviving copies in its set.*

![Dashboard during an outage](screenshots/41-drill9-dashboard-incident.png)

*The dashboard during the second crash: 5 bricks online, the brick row red, the backlog rising, three alerts firing. The first outage is visible earlier on the time axis.*

![Brick recovered](screenshots/42-drill9-brick-recovered.png)

*After `volume start gv0 force`, the brick is online again and every heal count is 0.*

![Dashboard after recovery](screenshots/43-drill9-dashboard-recovered.png)

*After recovery: 6 bricks online, nothing pending, no alerts, and both outages and their heal backlogs visible on the time axis.*

![Set 2 copies compared](screenshots/44-drill9-set-digests.png)

*The set 2 copies of `drill9` on all three servers, including the brick that crashed: 149 files with the same digest.*

### Benchmark baseline ([details](docs/benchmark.md))

![Direct I/O through the mount](screenshots/45-bench-direct-io-check.png)

*A 64 MiB `O_DIRECT` write through the FUSE mount completing with `err= 0`, confirming the mount accepts direct I/O before the benchmark.*

![Raw filesystem run](screenshots/46-bench-raw-run.png)

*The raw XFS baseline on `gluster1`: six profiles, three runs each. The text after `run N of 3` is the end of fio's last status line from the previous run.*

![Gluster run](screenshots/47-bench-gluster-run.png)

*The same profiles through the Gluster client on `gluster4`.*

![Benchmark summary](screenshots/48-bench-results.png)

*The median of each profile for both targets, and Gluster as a percentage of the raw filesystem.*

## Known limitations

- Everything runs on one physical machine with shared storage and virtual networking. Latency and throughput numbers are only meaningful relative to each other, not as absolute figures. The raw-disk benchmark ran largely from the host's memory, so it is a loose upper bound rather than the SSD's speed.
- Each timing measurement in the drills is a single run. They show the effect, not a statistical result.
- In drill 2, the observed stalls were longer than the configured `network.ping-timeout`. The cause is not established.
- In drill 3, the documentation describes loss of client quorum as making the replica set read-only. On the tested version the mount became unusable for reads as well. The exact log lines are recorded and the version-specific behaviour has not been investigated further.
- No automation yet.
- Alerts are visible in Prometheus and Grafana but are not delivered anywhere: there is no Alertmanager.
- Only one OS and one Gluster version were tested.

## Future improvements

1. Ansible role that rebuilds the whole lab idempotently.
2. Phase 2: CephFS on the same VMs, the same failure drills, the same `fio` profiles, and a written comparison.
3. The Gluster benchmark repeated with TLS off, to measure what encryption costs.

## References

- [Gluster documentation home](https://docs.gluster.org/)
- [Resolving split-brain (Gluster docs)](https://docs.gluster.org/en/latest/Troubleshooting/resolving-splitbrain/)
- [Arbiter volumes and quorum options (Gluster docs)](https://glusterdocs.readthedocs.io/en/latest/Administrator%20Guide/arbiter-volumes-and-quorum/)
- [Managing split-brain (Red Hat Gluster Storage administration guide)](https://docs.redhat.com/en/documentation/red_hat_gluster_storage/3/html/administration_guide/sect-Managing_Split-brain)
- [Gluster project roadmap](https://www.gluster.org/roadmap/)
- [CentOS Storage SIG Gluster 11 packages, aarch64](https://mirror.stream.centos.org/SIGs/9-stream/storage/aarch64/gluster-11/Packages/g)
- [cephadm installation (phase 2)](https://docs.ceph.com/en/latest/cephadm/install/)

## TL;DR

Three VMs form a GlusterFS volume (`gv0`) on LVM thin and XFS bricks, replica 3 and later expanded to 2 x 3, mounted from a fourth VM with the FUSE client. Nine drills covered failure, recovery, brick replacement, expansion, mutual TLS and alerting, and a `fio` baseline measured the volume against the raw filesystem under it; the results are in [Key results](#key-results) and the evidence in `docs/evidence`. Not done yet: Ansible automation and the CephFS comparison.
