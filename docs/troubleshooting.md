# Troubleshooting

Issues that were actually hit during this lab, followed by the general diagnostic commands used. Causes marked "not established" were not confirmed.

## Issues encountered

### New mount fails when only one of three servers is up

- **Where:** drill 3.
- **Symptom:** `mount -t glusterfs ...` prints `Mount failed. Check the log file for more details.`
- **Log evidence:** `no read subvols for /` followed by `first lookup on root failed (Transport endpoint is not connected)`, then the mount unmounts itself (`/var/log/glusterfs/mnt-gv0.log`).
- **Cause:** client quorum is not met, so the replicate layer will not nominate a brick to read from. The root lookup at the end of the mount fails.
- **Fix:** bring a second server back. With 2 of 3 bricks reachable the mount succeeds.

### Existing mount returns `Transport endpoint is not connected` for everything

- **Where:** drill 3, after the second server went down.
- **Cause:** same quorum loss. The log shows `Client-quorum is not met` at the moment the second brick disconnected.
- **Fix:** restore a second brick. In the lab the old mount was lazily unmounted and mounted again, and the new mount worked once two bricks were up.

### Brick shows `Online: N` right after `glusterd` starts

- **Where:** drill 4, on `gluster2` while the other two servers were down.
- **Symptom:** `gluster volume status gv0` lists the brick with no port and no PID.
- **Workaround that worked:** `sudo gluster volume start gv0 force`, which starts any brick process that is not running.
- **Cause:** not established. A possible factor is that `glusterd` waits to sync with its peers, but that was not confirmed.
- **Check first:** `sudo gluster volume get gv0 cluster.server-quorum-type` should be `none`. If it is `server`, glusterd deliberately kills bricks when it loses contact with most of the pool.

### Client stalls for a long time after a node is force-stopped

- **Where:** drill 2.
- **Symptom:** one write took 70.3 s (default timeout) or 13.2 s (timeout 10 s). Others took about 0.03 s.
- **Cause:** the client waits for `network.ping-timeout` before declaring a silent brick dead. The measured stall was longer than the timeout and the extra time is unexplained.
- **Fix or mitigation:** a shorter `network.ping-timeout` shortens the stall at the cost of more risk of false disconnects.
- **Not this:** a graceful shutdown does not stall, because the connection is closed cleanly.

### A split-brain file still reads normally on one client

- **Where:** drill 4.
- **Symptom:** the client that wrote the last version kept returning it while the bricks disagreed. After unmounting and mounting again, reads returned `Input/output error`.
- **Cause:** the long-lived mount was serving cached data. A fresh mount has no cache.
- **Fix:** do not trust a warm client when checking for split-brain. Check `gluster volume heal gv0 info split-brain` and inspect the bricks, or remount.

### Manual heal reports `File not in split-brain`

- **Where:** drill 4.
- **Symptom:** `bigger-file` and `latest-mtime` both returned `File not in split-brain`.
- **What changed it:** the first attempt was made after quorum and the self-heal settings had been restored. When the test was redone and the manual resolution was run first, the file was recognised as split-brain.
- **Practice:** capture evidence and resolve split-brain before changing cluster settings.

### Policy-based resolution refuses

- **Where:** drill 4.
- **Symptoms:** `No bigger file` and `No difference in mtime`.
- **Cause for `bigger-file`:** both versions were the same length.
- **Cause for `latest-mtime`:** not established.
- **Fix:** choose a source explicitly: `gluster volume heal gv0 split-brain source-brick <host:brick> <file>`.

## Operational note (documented behaviour, not an incident in this lab)

`systemctl stop glusterd` stops only the management daemon. Brick processes (`glusterfsd`) keep serving data. To take a brick out of service, stop its process as well (for example `sudo pkill glusterfsd`) or shut the node down. The drill 4 procedure does both.

## General diagnostics

What each command tests is noted next to it.

```bash
sudo gluster pool list                                   # are all peers connected
sudo gluster peer status                                 # peer state and hostnames
sudo gluster volume status gv0                           # which brick processes are running, and on what ports
sudo gluster volume heal gv0 info summary                # pending heal counts per brick
sudo gluster volume heal gv0 info split-brain            # files with no trustworthy replica
sudo gluster volume get gv0 cluster.quorum-type          # client quorum policy
sudo gluster volume get gv0 cluster.server-quorum-type   # server quorum policy
sudo gluster volume get gv0 network.ping-timeout         # how long clients wait on a silent brick
sudo getfattr -d -m . -e hex <file-on-brick>             # replication blame (trusted.afr.*), gfid
sudo tail -50 /var/log/glusterfs/glusterd.log            # management daemon log on a server
sudo tail -50 /var/log/glusterfs/mnt-gv0.log             # client mount log on the client
sudo firewall-cmd --info-service=glusterfs               # which ports are open for Gluster
ls -Zd /data/glusterfs/brick1/vol                        # SELinux label on the brick
df -hT /data/glusterfs/brick1                            # brick filesystem and free space
sudo lvs -a                                              # thin pool usage
```
