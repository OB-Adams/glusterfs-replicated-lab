# Monitoring and alerts

Milestone 3, step 3b (drill 9). Gluster's brick, heal and peer state is exported as metrics from each server, collected by Prometheus on `gluster4`, shown on a Grafana dashboard, and watched by alert rules. Two rules were exercised by crashing a brick while a client wrote, then recovering it. See [milestones.md](milestones.md).

Run on 2026-10-28. The figures below come from [evidence/drill9-session-gluster1.txt](evidence/drill9-session-gluster1.txt) to [evidence/drill9-session-gluster4.txt](evidence/drill9-session-gluster4.txt), [evidence/drill9-alerts.txt](evidence/drill9-alerts.txt), [evidence/drill9-logs.txt](evidence/drill9-logs.txt) and screenshots 35 to 44, which were taken during the run. The configuration that was deployed is in [../monitoring](../monitoring) and [../scripts/gluster-metrics.sh](../scripts/gluster-metrics.sh).

## Concepts

**Metrics, not logs.** A metric is a number sampled over time, with labels saying what it describes, such as `gluster_brick_up{brick="gluster3:/data/glusterfs/brick1/vol"} 1`. Numbers can be graphed and alerted on with simple rules; logs then explain why something happened.

**Prometheus pulls.** Each server runs an exporter, a small HTTP server that prints its current metrics on `/metrics`. Prometheus fetches every target every 15 seconds and stores the samples. A target that cannot be scraped is recorded as `up == 0`, so a silent server is itself a signal.

**node_exporter and the textfile collector.** `node_exporter` is the standard Linux host exporter and knows nothing about Gluster. Its textfile collector serves any `*.prom` file in a chosen directory. `gluster-metrics.sh`, run every 30 seconds by a systemd timer, turns `gluster volume status`, `gluster volume heal gv0 info summary` and `gluster pool list` into metrics and writes them there through a temporary file and a rename, so a half-written file is never served.

| Metric | Meaning |
|---|---|
| `gluster_brick_up{volume,host,brick}` | 1 if `volume status` shows the brick process online, 0 if not |
| `gluster_heal_pending_entries{volume,brick}` | Entries waiting to be healed on that brick; absent while the brick is unreachable |
| `gluster_heal_split_brain_entries{volume,brick}` | Entries in split-brain on that brick |
| `gluster_peer_connected{peer}` | 1 if `pool list` shows the peer connected |
| `gluster_metrics_last_success_timestamp_seconds` | When the script last got data from every command |

**Three reporters, one value.** `volume status` and `heal info` describe the whole volume from any server, so all three servers publish the same values, and the volume stays observable if one server dies. Alert rules and dashboard queries collapse the three copies with `max by (brick)`.

**Alert lifecycle.** A rule is a PromQL expression evaluated every 15 seconds. When it first returns a result, the alert is *pending*; if it keeps returning one for the rule's `for` duration, it is *firing*; when it stops, the alert is *resolved*. The `for` duration keeps a single bad sample from raising an alarm. A full deployment would send firing alerts to Alertmanager for delivery by email or chat; this lab stops at Prometheus and Grafana.

| Rule | Expression | `for` | Severity |
|---|---|---|---|
| `GlusterBrickDown` | `max by (volume, brick) (gluster_brick_up) == 0` | 30s | critical |
| `GlusterHealBacklog` | `max by (volume, brick) (gluster_heal_pending_entries) > 0` | 2m | warning |
| `GlusterSplitBrain` | `max by (volume, brick) (gluster_heal_split_brain_entries) > 0` | none | critical |
| `GlusterExporterDown` | `up{job="gluster-nodes"} == 0` | 1m | warning |
| `GlusterMetricsStale` | `time() - max by (instance) (gluster_metrics_last_success_timestamp_seconds) > 120` | none | warning |

**Grafana reads Prometheus.** Grafana stores no metrics; it runs PromQL against Prometheus and draws the results. Its data source and dashboard are provisioned from files at startup, so the dashboard is a JSON file in the repository.

## Layout

| Machine | Runs | Port |
|---|---|---|
| `gluster1`, `gluster2`, `gluster3` | `node_exporter` 1.8.2, and `gluster-metrics.timer` every 30 s | 9100, open to `gluster4` only |
| `gluster4` | Prometheus `v2.53.2` in Podman, host network | 9090 |
| `gluster4` | Grafana `11.2.0` in Podman, host network | 3000 |

Configuration on `gluster4` lives in `/opt/monitoring` and is mounted into the containers with `:Z` so SELinux allows them to read it. `podman-restart.service` brings the containers back after a reboot. The Grafana admin password was entered at a prompt and never written to a file.

## Procedure

1. **Exporters** on each server: `node_exporter` as a systemd service reading `/var/lib/node_exporter/textfile`, `gluster-metrics.sh` with its service and 30-second timer, and a firewalld rich rule opening 9100 to `gluster4` only.
2. **Prometheus and Grafana** on `gluster4`: configuration and rules checked with `promtool`, dashboard JSON checked with `python3 -m json.tool`, both containers started, 9090 and 3000 opened.
3. **Baseline.** Three targets `UP`, five rules `inactive`, the dashboard at 6 bricks online and 0 pending, split-brain and firing.
4. **Crash** `gluster3:/data/glusterfs/brick1/vol` (set 2) with `kill -9` while the client writes one 4 KiB file a second into `drill9`.
5. **Watch** the alerts go pending and firing, and capture Prometheus's alert state from `/api/v1/alerts`.
6. **Recover** with `gluster volume start gv0 force`, and watch the backlog heal and the alerts resolve.
7. **Verify** the set 2 copies of `drill9` on all three servers.

## Timeline

Times are UTC on 2026-10-28. Times to the second come from the self-heal daemon log on `gluster1`, `cmd_history.log` and the Prometheus API; the rest from the session logs and screenshots. The brick was crashed twice.

| Time | Event |
|---|---|
| 21:44 | Recordings started; exporters installed on the servers, then Prometheus and Grafana on `gluster4` |
| 22:18 | Prometheus collecting; baseline screenshots 35 to 38 follow |
| 22:35:49 | **Incident 1.** The `drill9` writer running; `gluster3`'s brick1 process (PID 1797) killed. The self-heal daemon on `gluster1` loses `gv0-client-5` |
| 22:36:19.8 | `GlusterBrickDown` and `GlusterHealBacklog` both become pending at the same evaluation |
| about 22:36:50 | `GlusterBrickDown` firing, after its 30 s |
| about 22:38:20 | `GlusterHealBacklog` firing, after its 2 min |
| 22:40:46 | `gluster volume start gv0 force` on `gluster1` |
| 22:40:49.29 | The new brick process attaches on port 53744; healing starts 0.12 s later without any heal command |
| 22:40:52.15 | `gluster1`'s self-heal daemon logs its last heal for incident 1: 72 data and 76 metadata heals |
| 22:41:19 | `volume heal gv0 full` run; the heal had already finished |
| 22:44:08 | **Incident 2.** The restarted brick process (PID 7558) killed again on `gluster3` |
| about 22:50 | The writer started again; the backlog rises again |
| 22:52:56 | Dashboard during incident 2: 5 bricks online, 144 entries pending, 3 alerts firing (screenshot 41) |
| 22:54:01.70 | After `volume start gv0 force` on `gluster3`, the brick attaches on port 59600; `gluster1`'s daemon completes 64 data heals by 22:54:02.89 |
| 22:56 | Dashboard after recovery: 6 bricks online, 0 pending, 0 firing (screenshot 43) |
| 22:58 | Closing check: six bricks online, every heal count 0 |

## Findings

**Both alert rules fired, as designed, twice.** In incident 1, the Prometheus API shows `GlusterBrickDown` for `gluster3:/data/glusterfs/brick1/vol` and `GlusterHealBacklog` for `gluster1:/data/glusterfs/brick2/vol` and `gluster2:/data/glusterfs/brick2/vol`, all firing, with the backlog at 101 entries per brick at the time of the capture. Screenshot 40 shows the same alerts earlier, at 78. Incident 2 produced the same three alerts (screenshot 41). After each recovery they resolved, and the API returned no active alerts.

**The backlog alert names the healthy bricks.** The crashed brick reports no heal count while it is unreachable, so `GlusterHealBacklog` fires for the two surviving copies in its set, which are the ones holding the pending records. `GlusterBrickDown` names the missing brick. Read together, the two alerts identify the replica set and the stale copy.

**Both alerts became pending together, about 30 seconds after the crash.** The crash at 22:35:49 showed up in the metrics at the next run of the 30-second timer, and Prometheus marked both rules pending at the same evaluation, 22:36:19.8. The time to detect is set by the timer interval plus the scrape interval plus each rule's `for`: about a minute for a dead brick, and about two and a half minutes for a backlog.

**Healing started by itself as soon as the brick returned.** In both incidents, the self-heal daemon began healing within a fraction of a second of the restarted brick attaching, and finished in about 3 seconds for 4 KiB files. The `heal full` at 22:41:19 came after the heal had already completed and was not needed. This matches drill 6 (see [brick-replacement.md](brick-replacement.md)).

**A crashed brick stays down until someone restarts it.** `glusterd` did not restart the killed process on its own; the brick stayed offline for about five minutes in incident 1 and about ten in incident 2, until `volume start gv0 force`. That is why the brick-down alert matters: nothing else would have brought the copy back.

**The dashboard's backlog total counts each entry twice.** "Entries pending heal" sums the per-brick values. Each pending entry is recorded on both surviving bricks of the set, so the 144 shown in incident 2 is 72 entries on each of the two bricks.

**No false alarms from the collector.** `GlusterExporterDown` and `GlusterMetricsStale` stayed inactive throughout, including while `heal info` reported a brick as unreachable. The metrics script judges success by whether `heal info` returned data, not by its exit status, which can be non-zero while a brick is down.

## Verification

| Check | Result |
|---|---|
| Exporters | Three targets `UP` (screenshot 36); `gluster1` serves six `gluster_brick_up`, six pending, six split-brain and three peer series (screenshot 35) |
| Rules | Five rules loaded, all inactive at the baseline (screenshot 37) |
| Alert state | Captured from the API before, during and after incident 1 ([evidence/drill9-alerts.txt](evidence/drill9-alerts.txt)) |
| Recovery | The brick online and every heal count 0 at 22:42 (screenshot 42) and at the closing check |
| Data | The set 2 copies of `drill9` hold 149 files with digest `153e9c96…5172cc1` on all three servers, including the brick that crashed (screenshot 44). The client sees all 300 files |

## Operational notes

- A brick process that crashes is not restarted automatically. Alert on it, and recover with `gluster volume start <volume> force`, which starts only the processes that are missing.
- Read `GlusterBrickDown` and `GlusterHealBacklog` together: the first names the stale copy, the second names the copies holding its pending changes.
- Detection time is the sum of the collection interval, the scrape interval and the rule's `for`. Shorten the 30-second timer before shortening `for`.
- Prometheus and Grafana here have no TLS, Prometheus has no authentication, and alerts are not delivered anywhere. Alertmanager, TLS and authentication on the monitoring endpoints are the next steps for anything beyond a lab.
