# Benchmarks

`fio` workloads for milestone 4, kept here so phase 2 can run exactly the same tests against CephFS. Results and the write-up are in [../docs/benchmark.md](../docs/benchmark.md).

| File | Purpose |
|---|---|
| `fio/*.fio` | One job file per workload. Each reads the directory under test from the `BENCH_DIR` environment variable. |
| `run-bench.sh` | Runs every profile several times against one target, dropping the page cache before each run, and keeps fio's JSON output in `results/<target>/`. Run as root. |
| `summarize.py` | Turns the JSON into Markdown tables: the median of the runs for each target and profile, and each target as a percentage of the baseline. |

```bash
./benchmarks/run-bench.sh raw-xfs /data/glusterfs/brick1/fio-baseline 3   # on a server, outside the brick's vol directory
./benchmarks/run-bench.sh gluster-fuse /mnt/gv0/bench 3                   # on the client
python3 benchmarks/summarize.py <results-directory> [baseline-target]     # baseline defaults to raw-xfs
```

For Gluster, set `performance.strict-o-direct on` during the run so the bricks honour `O_DIRECT` too, and reset it afterwards.
