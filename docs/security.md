# Access control and TLS

Milestone 3, step 3a (drill 8). Client access to `gv0` is restricted by address with `auth.allow`, then all Gluster traffic, management and data, is moved to mutual TLS with a lab certificate authority, and three kinds of bad client are refused at three different layers. See [milestones.md](milestones.md).

Run on 2026-10-28. The figures below come from [evidence/drill8-logs.txt](evidence/drill8-logs.txt), Gluster's command history and logs, and screenshots 27 to 34, which were taken during the run. The terminal recordings for this drill were not kept.

## Concepts

**Two planes.** On the management plane, `glusterd` talks to `glusterd` on 24007/tcp, and a client fetches its volfile from `glusterd` at mount time. On the data plane, each client talks to every brick process on that brick's own port. Before this drill both were plain TCP.

**`auth.allow` checks addresses.** It is a volume option listing the client IP addresses each brick accepts. It gives no confidentiality, and an address can be borrowed on a shared network, so it is a first fence. The servers' own addresses must be on it, because their self-heal and rebalance processes are clients of the bricks too.

**Mutual TLS.** Both ends of every connection present a certificate, and each end checks that the other's was signed by a certificate authority it trusts. A certificate binds a public key to a name; the signature inside the handshake proves the sender holds the matching private key. This lab has its own CA, one certificate per machine, and the CA's certificate as every machine's trust anchor.

**Files and switches.** This build reads `glusterfs.key`, `glusterfs.pem` and `glusterfs.ca` from `/etc/pki/tls/`. Management TLS is switched on by the empty file `/var/lib/glusterd/secure-access` on every server and client: `glusterd` reads it only at startup, so all servers have to be restarted together, and a client reads it before fetching its volfile. Data-plane TLS is switched on with the volume options `client.ssl` and `server.ssl` and takes effect when the volume starts.

**Authentication is not authorization.** A valid certificate proves who the client is. Whether that name may use the volume is a separate list, `auth.ssl-allow`, checked by the bricks.

## Procedure

1. **Baseline.** Six bricks online, zero heal entries, and the `drill7` reference digest `58adce45…ff57` from the client.
2. **`auth.allow`** (`gluster1`): set it to the three servers and the client and remount the client; remove the client and try to mount; put it back.
3. **Certificates** (`gluster1`, in `/root/lab-ca`): a 4096-bit lab CA, then a 2048-bit key and a CA-signed certificate for `gluster1` to `gluster4` and for `intruder`, all valid for 365 days, and a self-signed `rogue` certificate with the CN `gluster4`. Each machine receives its own key and certificate and the CA certificate in `/etc/pki/tls/`, labelled `cert_t` with `restorecon`. `gluster4` also keeps the two test certificates in `/root/test-certs`.
4. **TLS on.** Unmount the client and stop the volume, then:

   ```bash
   gluster volume set gv0 client.ssl on
   gluster volume set gv0 server.ssl on
   gluster volume set gv0 auth.ssl-allow 'gluster1,gluster2,gluster3,gluster4'
   ```

   Stop `glusterd` on all three servers, `touch /var/lib/glusterd/secure-access` on each, start `glusterd` on all three, start the volume. Create the same file on the client.
5. **On the wire.** From the client, `openssl s_client` against 24007 and a brick port, trusting only the lab CA.
6. **Bad clients.** On `gluster4`, mount with no certificate, with `rogue`, and with `intruder`.
7. **Real client.** Restore `gluster4`'s own certificate, mount, write a file, and check the `drill7` digest.

## Timeline

Times are UTC on 2026-10-28, from `cmd_history.log`, the Gluster logs and the screenshots.

| Time | Event |
|---|---|
| 16:19 | Baseline: volume status checked on `gluster1` and `gluster3` |
| 16:22 to 16:23 | `auth.allow` set to the three servers and the client; the client mounts at 16:23 |
| 16:25:14 | Client's address removed. Each brick drops the already-mounted client at once |
| 16:26:37 to 16:26:42 | Address restored; the client mounts |
| 16:27:07 | Address removed again; the mount at 16:27:14 is refused (screenshot 27) |
| 16:28:05 to 16:28:13 | Address restored for the rest of the lab; the client mounts |
| 16:39 | Certificates installed |
| 16:47:05 to 16:47:31 | Volume stopped; `client.ssl`, `server.ssl` and `auth.ssl-allow` set |
| 16:51 | `glusterd` restarted with `secure-access`: `could not load our cert at /etc/pki/tls/glusterfs.pem` |
| 16:52:04 to 17:00:30 | `volume start` fails five times: `Commit failed on localhost` |
| about 17:03 | Certificate files moved from `/etc/ssl` to `/etc/pki/tls`, `glusterd` restarted on all servers |
| 17:04:20 | `volume start` succeeds; the servers' own processes log in to the bricks as `gluster1`, `gluster2` and `gluster3` |
| 17:08 | Six bricks and three self-heal daemons online with TLS on (screenshot 29) |
| 17:16:59 | Mount with no certificate refused (screenshot 31) |
| 17:20:12 | Mount with `rogue` refused (screenshot 32) |
| 17:24:17 | Mount with `intruder` refused (screenshot 33) |
| 17:28:47 | Mount with the real certificate succeeds; file written at 17:29:12 (screenshot 34) |

## Findings

**`auth.allow` is enforced by the bricks, and on live connections.** Removing the client's address at 16:25:14 made the brick log `no authentication module is interested in accepting remote-client` and `unauthorized client, hence terminating the connection` for the mounted client. The bricks re-check existing clients when the option changes and drop any that no longer match; the setting does not wait for the next mount. A fresh mount at 16:27:14 failed with `SETVOLUME on remote-host failed … Authentication failed` and `AUTH_FAILED`. The volfile fetch from `glusterd` was not affected; the refusal came from the bricks.

**This build reads its certificates from `/etc/pki/tls`.** The certificates were first installed in `/etc/ssl`, the path most upstream examples use. With `secure-access` present, `glusterd` attempted TLS on every connection and failed each one with `could not load our cert at /etc/pki/tls/glusterfs.pem`. Peers could not connect, a peer with no certificate to offer produced `no shared cipher`, and `volume start` failed five times with `Commit failed on localhost`. Moving the three files to `/etc/pki/tls`, relabelling them and restarting `glusterd` on all servers fixed it, and the volume started at 17:04:20. The log names the path it searched, which is the quickest way to diagnose this.

**The servers authenticate to the bricks by certificate name.** After the start, the brick log shows `connecting user name: gluster1`, `gluster2` and `gluster3`, checked against `allowed user names: gluster1,gluster2,gluster3,gluster4`. Their self-heal daemons and other internal clients use the servers' certificates, which is why the servers must be in `auth.ssl-allow`. All six bricks and the three self-heal daemons came up with TLS on.

**Both ports speak TLS.** `openssl s_client` from the client, trusting only the lab CA, received `subject=CN=gluster1`, `issuer=CN=gluster-lab-ca` and `Verify return code: 0 (ok)` from 24007 and from brick port 53225.

**Three bad clients were refused at three different layers.**

| Client certificate | Client side | Server side | Layer |
|---|---|---|---|
| None | `could not load our cert`, `SSL connect error`, `failed to fetch volume file` | none needed | The client cannot start TLS |
| `rogue`, self-signed, CN `gluster4` | `tlsv1 alert unknown ca` | `glusterd` on `gluster1`: `certificate verify failed` | TLS handshake on 24007 |
| `intruder`, signed by the lab CA | `SETVOLUME on remote-host failed … Authentication failed`, `AUTH_FAILED` on every brick | brick: `connecting user name: intruder`, `Cannot authenticate client` | Brick authorization |

`rogue` carried the right name and the wrong signature, and never got a volfile. `intruder` had a genuine lab certificate, completed TLS and fetched the volfile, and was then refused by name.

**Address and name checks are both applied.** For `intruder`, the brick log first compares the client's address with each `auth.allow` entry and finds a match, then checks the certificate name against `auth.ssl-allow` and refuses it. Each list has to admit a client.

## Verification

| Check | Result |
|---|---|
| Lab certificates | All five lab-signed certificates verify against the CA; `rogue` fails with `self-signed certificate` (screenshot 28) |
| Volume options | `client.ssl on`, `server.ssl on`, `auth.ssl-allow gluster1,gluster2,gluster3,gluster4`, `auth.allow` set to the three servers and the client (screenshot 29) |
| Services | Six bricks and three self-heal daemons online with TLS on (screenshot 29) |
| Real client | Mounted over TLS at 17:28:47, `df` 16G, a file written and read back |
| Data | The 300 original `drill7` files from the client digest to `58adce45…ff57`, the same as before the drill (screenshot 34) |

## Operational notes

- The certificate path depends on how Gluster was built. Check the `could not load our cert at …` line, or the package documentation, before installing certificates.
- Enabling management TLS needs `glusterd` restarted on every server together; a server with `secure-access` and one without cannot talk to each other.
- Changing `auth.allow` disconnects clients that no longer match immediately. Schedule it like any other change that can cut clients off.
- The servers must appear in both `auth.allow` (by address) and `auth.ssl-allow` (by name), or self-heal and rebalance stop working.
- The certificates expire 365 days after issue, on 2027-10-28. When they do, every connection fails.
- `ca.key` is the master key: anyone holding it can issue an allowed identity. It stays in `/root/lab-ca` on `gluster1` and never goes into the repository.
