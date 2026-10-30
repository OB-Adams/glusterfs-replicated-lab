# Benchmark baseline

Milestone 4. The same six `fio` workloads were run against `gv0` from the client, and against the raw XFS filesystem underneath a brick, so the difference shows what Gluster's layers cost. The job files and scripts are in [../benchmarks](../benchmarks), so phase 2 can run exactly the same tests against CephFS. See [milestones.md](milestones.md).

Run on 2026-10-30. The figures below come from fio's JSON output in [evidence/benchmark](evidence/benchmark), the summary in [evidence/benchmark/results.md](evidence/benchmark/results.md), the session logs [evidence/benchmark-session-gluster1.txt](evidence/benchmark-session-gluster1.txt) and [evidence/benchmark-session-gluster4.txt](evidence/benchmark-session-gluster4.txt), and screenshots 45 to 48, which were taken during the run.

**Read the numbers as comparisons, not as performance figures.** All four VMs share one Mac's SSD, CPU and memory, and the raw baseline turned out to run largely at the speed of the Mac's memory (see the findings). The Gluster figures are valid for comparison with CephFS under the same conditions in phase 2; none of the absolute numbers say what Gluster would do on real servers.

## Concepts

**Three measures.** Bandwidth (MiB/s) matters for large sequential transfers, IOPS (operations per second) for many small operations, and latency (milliseconds per operation) for how long each request waits. A system can be good at one and poor at another, so each workload reports the one that matters for it, plus latency.

**Requests in flight.** Each time-based profile runs four workers (`numjobs=4`), and each worker keeps up to 16 requests outstanding at once (`iodepth=16`) using Linux asynchronous I/O (`ioengine=libaio`), so 64 requests are in flight at any moment. By Little's law, requests in flight = IOPS × mean latency, so for a fixed 64, a system that takes longer per request completes fewer per second.

**Caches bypassed.** `direct=1` opens files with `O_DIRECT`, which skips the page cache in the VM running fio. `performance.strict-o-direct on` makes Gluster's bricks honour `O_DIRECT` as well, and `run-bench.sh` drops the page cache before every run.

**What a Gluster request crosses.** The raw test goes from fio to XFS to the virtual disk. A Gluster request goes from fio through the kernel's FUSE module to the `glusterfs` client process, is encrypted with TLS (milestone 3a), crosses the virtual network to the bricks of the right replica set, and for a write must be acknowledged by all three copies before it completes. Each of those steps adds a fixed cost to every request.

**Median of three.** Each profile ran three times per target. The tables report the median, and the range of the main figure shows how much the runs disagreed.

## Setup

| Item | Value |
|---|---|
| VMs | CentOS Stream 9, kernel `5.14.0-759.el9.aarch64`, 5 vCPUs and 3.5 GiB RAM (recorded on `gluster1` and `gluster4`) |
| Virtualisation | UTM with the Apple Virtualization framework (`systemd-detect-virt` reports `apple`) on one Mac |
| fio | 3.35 on `gluster1` and `gluster4` |
| Volume | `gv0`, `Distributed-Replicate` 2 x 3, mutual TLS on, `performance.strict-o-direct on` during the runs |

| Target | Where fio ran | Directory | Path through the stack |
|---|---|---|---|
| `raw-xfs` | `gluster1` | `/data/glusterfs/brick1/fio-baseline` | XFS on the LVM thin volume under `brick1`, outside the brick's `vol` directory, so Gluster never saw it |
| `gluster-fuse` | `gluster4` | `/mnt/gv0/bench` | FUSE client, TLS, distribute, replicate, brick processes on all three servers |

| Profile | Workload | Block size | In flight | Main figure |
|---|---|---|---|---|
| `seq-write` | Sequential write | 1 MiB | 4 x 16 | write MiB/s |
| `seq-read` | Sequential read | 1 MiB | 4 x 16 | read MiB/s |
| `rand-read-4k` | Random read | 4 KiB | 4 x 16 | read IOPS |
| `rand-write-4k` | Random write | 4 KiB | 4 x 16 | write IOPS |
| `mixed-70-30` | Random, 70% reads and 30% writes | 4 KiB | 4 x 16 | total IOPS |
| `small-files` | Each worker creates and writes 2,000 files of 4 KiB, one at a time, then deletes them | 4 KiB | 4 x 1 | files per second |

The first five run for 10 seconds of warm-up then 60 seconds measured, on four 1 GiB files (4 GiB in total) that every profile reuses. `small-files` runs until its 8,000 files are written; the deletes happen after the measured part.

## Procedure

1. **Check** the cluster with `./scripts/check-cluster.sh`: six bricks online, no heal or split-brain entries. Record the kernel, CPUs and memory on both VMs.
2. **Set** `performance.strict-o-direct on`.
3. **Check direct I/O** through the mount with a 64 MiB `O_DIRECT` write from `gluster4` (screenshot 45).
4. **Raw baseline** on `gluster1`: `./benchmarks/run-bench.sh raw-xfs /data/glusterfs/brick1/fio-baseline 3` (screenshot 46), then remove the test directory.
5. **Gluster** on `gluster4`: `./benchmarks/run-bench.sh gluster-fuse /mnt/gv0/bench 3` (screenshot 47), then remove the test directory.
6. **Reset** `performance.strict-o-direct` and run the cluster check again.
7. **Summarise** on the Mac with `python3 benchmarks/summarize.py <results>` (screenshot 48).

## Timeline

Times are UTC on 2026-10-30, from the session logs and the timestamps in the JSON files.

| Time | Event |
|---|---|
| 20:53 | Recording started on `gluster1`; fio present, environment recorded, cluster check clean |
| 21:03:10 | Direct-I/O check on the mount: `err= 0`, 64 MiB written at 182 MiB/s |
| before 21:04:51 | `performance.strict-o-direct` set to `on` |
| 21:04:51 | `raw-xfs` run started on `gluster1` |
| 21:22:58 | `raw-xfs` done: 18 runs; test directory removed afterwards |
| 21:49:22 | `gluster-fuse` run started on `gluster4` |
| 22:10:01 | `gluster-fuse` done: 18 runs; test directory removed afterwards |
| after 22:10 | `performance.strict-o-direct` reset to `off (DEFAULT)`; cluster check clean |
| 22:15 | Recordings ended |

## Results

Medians of three runs. The full table, with read and write figures for every profile, is in [evidence/benchmark/results.md](evidence/benchmark/results.md).

| Profile | `raw-xfs` | `gluster-fuse` | Gluster as % of raw | Gluster range (3 runs) |
|---|---|---|---|---|
| `seq-write` | 18,804 MiB/s | 199 MiB/s | 1% | 196 to 205 |
| `seq-read` | 21,703 MiB/s | 847 MiB/s | 4% | 811 to 858 |
| `rand-read-4k` | 154,184 IOPS | 12,260 IOPS | 8% | 12,056 to 12,465 |
| `rand-write-4k` | 133,920 IOPS | 3,278 IOPS | 2% | 3,041 to 3,316 |
| `mixed-70-30` | 124,562 IOPS | 6,838 IOPS | 5% | 6,784 to 6,884 |
| `small-files` | 31,128 files/s | 322 files/s | 1% | 318 to 322 |

| Profile | `raw-xfs` mean / p99 latency (ms) | `gluster-fuse` mean / p99 latency (ms) |
|---|---|---|
| `seq-write` | 3.27 / 6.78 | 302.86 / 400.56 |
| `seq-read` | 2.90 / 5.41 | 70.91 / 106.43 |
| `rand-read-4k` | 0.41 / 0.99 | 5.21 / 10.29 |
| `rand-write-4k` | 0.47 / 1.14 | 18.40 / 38.54 |
| `mixed-70-30` | 0.49 / 1.27 (reads) | 8.60 / 25.30 (reads) |
| `small-files` | 0.08 / 0.18 (the write only) | 3.08 / 4.55 (the write only) |

Latency is fio's completion latency per request. For `mixed-70-30` it is the read side, which carries 70% of the requests. For `small-files` it covers only the 4 KiB write, not creating or closing the file.

## Findings

**The raw baseline mostly measured the Mac's memory, not its SSD.** `seq-write` sustained 18.8 GiB/s for the measured minute, about 1.1 TiB, and `seq-read` 21.7 GiB/s; no laptop SSD comes close to either. fio's disk statistics show the requests did leave the VM: in `rand-read-4k` run 2, the virtual disk `vdb` received 10.8 million reads, about what fio issued over the warm-up and the measured minute, so the VM's own page cache was bypassed as intended. The speed came from below the VM. The VMs run on the Apple Virtualization framework, where each virtual disk is an image file on the Mac, and the 4 GiB being reread and rewritten fits easily in the Mac's memory. The effect is that the percentage column exaggerates Gluster's cost: it compares Gluster with something close to a memory-speed disk. Because the bricks sit on the same kind of virtual disk, Gluster's own figures are limited mainly by the layers above the disk, not by the SSD.

**Every Gluster figure is a small fraction of the raw one, and latency explains it.** With 64 requests in flight in both targets, Little's law ties the IOPS to the time per request. A 4 KiB random read took 5.2 ms on average through Gluster against 0.4 ms on the raw filesystem, about 13 times longer, and Gluster completed 8% as many. The extra time is the path in the concepts above: FUSE, TLS, the network and the brick processes, all sharing the same CPUs, for every request. fio's checks confirm the load was what was intended: every asynchronous run held all 16 requests per worker in flight for 100% of the time, and IOPS × mean latency comes to 64 in each of them.

**Writes cost about four times as much as reads, because each write goes to three copies.** Random 4 KiB reads reached 12,260 IOPS and random writes 3,278, a ratio of 3.7; sequential reads reached 847 MiB/s and sequential writes 199 MiB/s, 4.3. On the raw filesystem the read and write figures are within 15% of each other. A read is served by one brick of the replica set, while a write is sent to all three and completes only when all three have answered, so the client sends three times the data and waits for the slowest copy. Write latency shows the same thing: 18.4 ms for a random write against 5.2 ms for a read.

**Sequential writes were saturated: more requests in flight made each one wait longer, not finish faster.** The direct-I/O check wrote 1 MiB at a time with one request in flight and reached 182 MiB/s, about 5.5 ms per request. `seq-write`, with 64 in flight, reached only 199 MiB/s, and each request took 303 ms on average. Past that point, extra requests only queue. The limit is somewhere on the write path, which carries three copies, about 600 MiB/s of replication traffic from the client. The direct-I/O check lasted 0.35 seconds and ran once, so this is an indication rather than a measurement.

**Creating files is the most expensive thing Gluster does here.** Through Gluster, the four workers together created, wrote and closed 322 files a second, 1% of the raw rate. Each worker finished a file about every 12.4 ms, but the 4 KiB write itself took 3.1 ms; about three quarters of the time per file went on creating, opening and closing it, each a round trip to the bricks of a replica set and, for a create, to all three copies. On the raw filesystem the write was most of the time per file. Workloads made of many small files, such as source trees, mail spools or package caches, are where a replicated network filesystem costs the most.

**The Gluster results are consistent between runs.** Every Gluster profile's three runs were within 8% of their median, most within 3%. The raw `small-files` runs varied more (25,641 to 34,783 files/s), because each lasted only about a quarter of a second; that figure is the least precise in the table.

## Verification

| Check | Result |
|---|---|
| Cluster before and after | Six bricks online, zero heal and split-brain entries on every brick (session log on `gluster1`) |
| `O_DIRECT` through the mount | `err= 0` and a `WRITE:` line from the direct-I/O check (screenshot 45) |
| Runs completed | 18 JSON files per target, every one with `error` 0 (screenshots 46 and 47, [evidence/benchmark](evidence/benchmark)) |
| Load as configured | Queue depth 16 for 100% of the time in every asynchronous run; IOPS × mean latency = 64 in every time-based run |
| Volume option restored | `performance.strict-o-direct off (DEFAULT)` after the runs |
| Test data removed | `brick1` on `gluster1` back to 414 MiB used after the raw run, and 422 MiB after `gluster4` removed the Gluster test files |

The summary script first reported `small-files` four times too low: it divided by fio's `job_runtime`, which with `group_reporting` adds up the time of all four workers. It now divides by the wall-clock runtime. Screenshot 48 and [evidence/benchmark/results.md](evidence/benchmark/results.md) were produced after the fix, from the same JSON files.

In screenshots 46 and 47, the text after `run N of 3` on each progress line is the end of fio's last status line from the previous run, which the next line was printed over. It is not part of the result.

## Limitations

- One Mac runs all four VMs, the virtual disks are cached in its memory, and the "network" is a virtual switch. Only comparisons made under the same conditions mean anything.
- The raw baseline is close to memory speed, so the percentages overstate Gluster's cost. Phase 2 should compare CephFS with these Gluster figures directly.
- One client, one load level (64 requests in flight), and one block size per pattern. There is no sweep of queue depth, so the point where each target saturates was not mapped.
- TLS was on throughout, and its share of the cost was not separated out. Running the Gluster target again with TLS off would measure it.
- `small-files` times creating and writing the files, not deleting them, and its raw runs were very short.

## Reusing these tests

The six job files and `run-bench.sh` are unchanged from this run. For phase 2:

```bash
./benchmarks/run-bench.sh cephfs /mnt/cephfs/bench 3
python3 benchmarks/summarize.py <results-directory> gluster-fuse   # CephFS as a percentage of Gluster
```

Passing `gluster-fuse` as the baseline compares the two distributed filesystems with each other rather than with the memory-speed raw baseline.
