## Results (median of runs)

| Target | Profile | Runs | Main figure | Range | Read IOPS | Read MiB/s | Write IOPS | Write MiB/s | Mean latency (ms) | p99 latency (ms) |
|---|---|---|---|---|---|---|---|---|---|---|
| raw-xfs | seq-write | 3 | 18,804 MiB/s | 17,892 to 19,148 | 0 | 0.0 | 18,803 | 18,803.7 | 3.27 | 6.78 |
| raw-xfs | seq-read | 3 | 21,703 MiB/s | 21,396 to 21,707 | 21,702 | 21,703.1 | 0 | 0.0 | 2.90 | 5.41 |
| raw-xfs | rand-read-4k | 3 | 154,184 IOPS | 151,883 to 154,212 | 154,184 | 602.3 | 0 | 0.0 | 0.41 | 0.99 |
| raw-xfs | rand-write-4k | 3 | 133,920 IOPS | 129,625 to 135,406 | 0 | 0.0 | 133,920 | 523.1 | 0.47 | 1.14 |
| raw-xfs | mixed-70-30 | 3 | 124,562 IOPS | 118,066 to 124,785 | 87,203 | 340.6 | 37,359 | 145.9 | 0.49 | 1.27 |
| raw-xfs | small-files | 3 | 31,128 files/s | 25,641 to 34,783 | 0 | 0.0 | 31,128 | 121.6 | 0.08 | 0.18 |
| gluster-fuse | seq-write | 3 | 199 MiB/s | 196 to 205 | 0 | 0.0 | 198 | 198.6 | 302.86 | 400.56 |
| gluster-fuse | seq-read | 3 | 847 MiB/s | 811 to 858 | 846 | 846.7 | 0 | 0.0 | 70.91 | 106.43 |
| gluster-fuse | rand-read-4k | 3 | 12,260 IOPS | 12,056 to 12,465 | 12,260 | 47.9 | 0 | 0.0 | 5.21 | 10.29 |
| gluster-fuse | rand-write-4k | 3 | 3,278 IOPS | 3,041 to 3,316 | 0 | 0.0 | 3,278 | 12.8 | 18.40 | 38.54 |
| gluster-fuse | mixed-70-30 | 3 | 6,838 IOPS | 6,784 to 6,884 | 4,783 | 18.7 | 2,055 | 8.0 | 8.60 | 25.30 |
| gluster-fuse | small-files | 3 | 322 files/s | 318 to 322 | 0 | 0.0 | 322 | 1.3 | 3.08 | 4.55 |

## Each target as a percentage of raw-xfs

| Profile | gluster-fuse |
|---|---|
| seq-write | 1% |
| seq-read | 4% |
| rand-read-4k | 8% |
| rand-write-4k | 2% |
| mixed-70-30 | 5% |
| small-files | 1% |
