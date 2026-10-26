# Architecture

This document explains the components of the lab and how data and control traffic move between them. The diagrams are Mermaid source and render on GitHub.

## Components

| Component | Runs on | Responsibility |
|---|---|---|
| `glusterd` | gluster1, gluster2, gluster3 | Management daemon. Holds pool and volume configuration, starts brick processes, answers CLI commands. Listens on 24007/tcp. |
| `glusterfsd` (brick process) | gluster1, gluster2, gluster3 | One per brick. Serves file operations for that brick on its own port. |
| Brick | gluster1, gluster2, gluster3 | A directory on a local XFS filesystem: `/data/glusterfs/brick1/vol`. |
| Self-heal daemon | gluster1, gluster2, gluster3 | Finds files that a brick missed and copies them from a good replica. |
| FUSE client | gluster4 | Mounts `gv0`. Fetches the volume description, then talks to every brick directly and performs the replication itself. |

## Topology

```mermaid
flowchart LR
    subgraph clientvm["Client VM"]
        C["gluster4<br/>FUSE client<br/>mounted at /mnt/gv0"]
    end
    subgraph pool["Trusted storage pool: volume gv0, replica 3"]
        subgraph s1["gluster1"]
            G1["glusterd"]
            B1["brick1<br/>XFS on LVM thin"]
        end
        subgraph s2["gluster2"]
            G2["glusterd"]
            B2["brick1<br/>XFS on LVM thin"]
        end
        subgraph s3["gluster3"]
            G3["glusterd"]
            B3["brick1<br/>XFS on LVM thin"]
        end
    end
    C -->|"24007/tcp: fetch volfile at mount"| G1
    C -->|"brick port: file operations"| B1
    C -->|"brick port: file operations"| B2
    C -->|"brick port: file operations"| B3
    G1 <-->|"24007/tcp"| G2
    G2 <-->|"24007/tcp"| G3
    G1 <-->|"24007/tcp"| G3
```

Control plane: `glusterd` to `glusterd` on 24007/tcp, and the client's one-time volfile fetch.
Data plane: client directly to each brick process. Brick ports are allocated per brick starting at 49152 by default, which is why the predefined `glusterfs` firewalld service opens a range.

The client names `gluster1` at mount time, but that is only used to download the volfile. `backup-volfile-servers=gluster2:gluster3` lets the mount succeed if gluster1 is down at that moment.

## Write path

```mermaid
sequenceDiagram
    participant App as Application
    participant AFR as FUSE client with AFR
    participant B1 as brick on gluster1
    participant B2 as brick on gluster2
    participant B3 as brick on gluster3
    App->>AFR: write
    AFR->>B1: pre-op, mark write pending
    AFR->>B2: pre-op, mark write pending
    AFR->>B3: pre-op, mark write pending
    AFR->>B1: data
    AFR->>B2: data
    AFR->>B3: data
    B1-->>AFR: ok
    B2-->>AFR: ok
    B3-->>AFR: ok
    AFR->>B1: post-op, clear pending
    AFR->>B2: post-op, clear pending
    AFR->>B3: post-op, clear pending
    AFR-->>App: write complete
```

AFR (Automatic File Replication) is the replication layer inside the client. If a brick does not acknowledge, the pending marker for it is not cleared on the bricks that did. Those `trusted.afr.gv0-client-N` attributes are the self-heal to-do list. Brick index N follows the order in `gluster volume create`: client-0 is gluster1, client-1 is gluster2, client-2 is gluster3.

## Availability states observed

```mermaid
stateDiagram-v2
    [*] --> Healthy
    Healthy --> Degraded: one brick lost
    Degraded --> Unavailable: second brick lost
    Unavailable --> Degraded: one brick returns
    Degraded --> Healing: lost brick returns
    Healing --> Healthy: heal backlog reaches zero
```

| State | Bricks reachable | Observed behaviour |
|---|---|---|
| Healthy | 3 of 3 | Normal writes, around 28 ms for small file creates in this lab |
| Degraded | 2 of 3 | Reads and writes continue. Graceful loss: no pause. Hard loss: a pause until `network.ping-timeout` expires. |
| Unavailable | 1 of 3 | Client log reports quorum not met. All lookups fail with `Transport endpoint is not connected` and new mounts fail. |
| Healing | 3 of 3, one stale | Surviving bricks list pending entries until the self-heal daemon copies them to the returned brick. |

Evidence for each row is in [failure-drills.md](failure-drills.md) and [evidence/](evidence).

## Split-brain

Split-brain means every replica is blamed by at least one other, so there is no trustworthy source.

```mermaid
flowchart TB
    subgraph before["Both bricks wrote while unable to see each other"]
        A["gluster1 holds version A<br/>blames gluster2 and gluster3"]
        B["gluster2 holds version B<br/>blames gluster1 and gluster3"]
        O["gluster3 holds the original<br/>blamed by both"]
    end
    A -.->|"blame"| B
    B -.->|"blame"| A
    A -.->|"blame"| O
    B -.->|"blame"| O
    before --> R["No unblamed brick exists<br/>Reads return an I/O error<br/>An operator must choose a source"]
```

Quorum on prevents this because the minority side refuses writes. The drill disables quorum and the self-heal options on purpose to create it.

## Trust boundaries and exposure

| Boundary | Traffic | Control in place | Not yet in place |
|---|---|---|---|
| Client to servers | Volfile fetch, file data | firewalld `glusterfs` service on servers | TLS, `auth.allow` |
| Server to server | Pool management, heal traffic | firewalld `glusterfs` service | TLS |
| Host to guests | SSH for administration | Lab network only | Hardening |
