# Build guide

Manual build of the lab, with the reason for each step. Commands are labelled with the machine they run on. Sizes are examples for a small data disk, so adjust them to yours.

Tested on: UTM guests (aarch64) running a RHEL-family OS. Record your exact OS release and Gluster version in the README before publishing.

## 0. Environment

| VM | Role |
|---|---|
| `gluster1`, `gluster2`, `gluster3` | Storage servers, each with one extra virtual disk (a second is added in milestones 2b and 2c, see [brick-replacement.md](brick-replacement.md) and [expansion.md](expansion.md)) |
| `gluster4` | Client |

On every VM, add all four hostnames to `/etc/hosts` with static addresses and enable time sync:

```bash
sudo dnf -y update
sudo dnf -y install chrony
sudo systemctl enable --now chronyd
```

Gluster identifies peers by name, and an address that changes breaks brick connections later. Set static addresses (or DHCP reservations) before creating the pool.

## 1. Install packages

The CentOS Storage SIG provides Gluster for the RHEL family through a release package. Confirm the available release first:

```bash
dnf search centos-release-gluster
```

On `gluster1`, `gluster2`, `gluster3`:

```bash
sudo dnf install -y centos-release-gluster11
sudo dnf install -y glusterfs-server lvm2 xfsprogs attr policycoreutils-python-utils firewalld
sudo systemctl enable --now glusterd
```

On `gluster4`:

```bash
sudo dnf install -y centos-release-gluster11
sudo dnf install -y glusterfs-fuse fio
```

If dependency errors appear, enable the CRB repository: `sudo dnf config-manager --set-enabled crb`.

Verify the release package name and aarch64 availability against the [SIG package index](https://mirror.stream.centos.org/SIGs/9-stream/storage/aarch64/gluster-11/Packages/g).

## 2. Open the firewall (servers)

```bash
sudo firewall-cmd --permanent --add-service=glusterfs
sudo firewall-cmd --reload
sudo firewall-cmd --info-service=glusterfs
```

`glusterd` uses 24007 and 24008. Every brick process uses its own port from 49152 upward, so the service opens a range. Keep the firewall enabled rather than disabling it.

## 3. Build the brick (each server)

Identify the data disk first:

```bash
lsblk
```

In this lab the disk was partitioned and the partition `/dev/vdb1` was used as the physical volume. LVM works the same on a partition or a raw disk. If you later reuse the disk for Ceph, remove the LVM stack and wipe the partition table first.

```bash
sudo pvcreate /dev/vdb1
sudo vgcreate vg_gluster /dev/vdb1
sudo lvcreate -L 9G --thinpool thinpool vg_gluster
sudo lvcreate -V 8G --thin -n brick1 vg_gluster/thinpool
sudo mkfs.xfs -i size=512 /dev/vg_gluster/brick1
```

Example sizes assume a 10 GB partition. Keep the thin LV's virtual size below the pool size so the pool cannot be overcommitted.

Why:

- **Thin pool.** Gluster volume snapshots depend on LVM thin provisioning. A thin LV allocates blocks only when written. If a thin pool fills up, the filesystem on top returns I/O errors, so monitor pool usage.
- **XFS with 512-byte inodes.** Gluster keeps replication state, layout and identity in extended attributes. A larger inode keeps them inside the inode instead of spilling into extra blocks.

## 4. Mount and prepare the brick (each server)

```bash
sudo mkdir -p /data/glusterfs/brick1
echo '/dev/vg_gluster/brick1 /data/glusterfs/brick1 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount -a
sudo mkdir /data/glusterfs/brick1/vol
```

The brick is the `vol` subdirectory, not the mount point. If the logical volume ever fails to mount at boot, the subdirectory will not exist and Gluster will refuse to start the brick. Without it, Gluster would write into an empty directory on the root disk.

SELinux label:

```bash
sudo semanage fcontext -a -t glusterd_brick_t "/data/glusterfs(/.*)?"
sudo restorecon -Rv /data/glusterfs
ls -Zd /data/glusterfs/brick1/vol
```

`semanage fcontext` stores the rule in the policy, `restorecon` applies it. Check that `ls -Z` shows the expected type on your system.

Validate:

```bash
df -hT /data/glusterfs/brick1
sudo lvs -a
```

## 5. Form the trusted pool

On `gluster1` only:

```bash
sudo gluster peer probe gluster2
sudo gluster peer probe gluster3
sudo gluster peer status
```

Then on `gluster2`, probe `gluster1` by name:

```bash
sudo gluster peer probe gluster1
sudo gluster pool list
```

When `gluster1` probes the others, they learn it only by the address it connected from. Probing it back by hostname makes every node know every other node by name. Peers are stored as files under `/var/lib/glusterd/peers/`.

## 6. Create and start the volume

From any server:

```bash
sudo gluster volume create gv0 replica 3 \
  gluster1:/data/glusterfs/brick1/vol \
  gluster2:/data/glusterfs/brick1/vol \
  gluster3:/data/glusterfs/brick1/vol
sudo gluster volume start gv0
sudo gluster volume info gv0
sudo gluster volume status gv0
sudo gluster volume get gv0 cluster.quorum-type
```

Expected: type `Replicate`, 1 x 3 = 3 bricks, all bricks online, quorum type `auto`. For a replica 3 volume, client quorum defaults to `auto`, meaning 2 bricks must be reachable for writes ([quorum documentation](https://glusterdocs.readthedocs.io/en/latest/Administrator%20Guide/arbiter-volumes-and-quorum/)).

Brick order defines replica sets and also the `gv0-client-N` indexes seen in logs and attributes.

Inspect what Gluster wrote:

```bash
sudo getfattr -d -m . -e hex /data/glusterfs/brick1/vol
ls /var/lib/glusterd/vols/gv0/
```

`trusted.glusterfs.volume-id` ties the brick to this volume. The `.vol` files are the volfiles (translator stacks) that clients download.

## 7. Mount on the client

On `gluster4`:

```bash
sudo mkdir -p /mnt/gv0
sudo mount -t glusterfs -o backup-volfile-servers=gluster2:gluster3 gluster1:/gv0 /mnt/gv0
df -hT /mnt/gv0
```

`df` reports the capacity of one brick, not three, because every file is stored three times.

Persistent mount, in `/etc/fstab`:

```text
gluster1:/gv0  /mnt/gv0  glusterfs  defaults,_netdev,backup-volfile-servers=gluster2:gluster3  0 0
```

Client log for mount problems: `/var/log/glusterfs/mnt-gv0.log`.

## 8. First replication test

On `gluster4`:

```bash
echo "hello gluster" | sudo tee /mnt/gv0/hello.txt
sudo dd if=/dev/urandom of=/mnt/gv0/test100M.bin bs=1M count=100
for i in $(seq 1 20); do sudo touch /mnt/gv0/file$i; done
```

On each server:

```bash
ls -lh /data/glusterfs/brick1/vol
sudo getfattr -d -m . -e hex /data/glusterfs/brick1/vol/hello.txt
sudo gluster volume heal gv0 info
```

Expected: identical files and sizes on all three bricks, `trusted.gfid` present, no pending heal entries.

Never write into a brick directory directly. Only inspect it. A file created directly on a brick has no gfid and is invisible to Gluster.

## Completion criteria

- [ ] Three peers `Connected` in `gluster pool list`.
- [ ] `gv0` is `Started` with three bricks online.
- [ ] Client mount works and `df` shows a single brick's capacity.
- [ ] Test files appear identically on all three bricks.
- [ ] `gluster volume heal gv0 info` shows no entries.
- [ ] SELinux enforcing and the firewall enabled throughout.
