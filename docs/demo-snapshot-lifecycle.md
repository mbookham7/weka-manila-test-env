# Demo: Snapshot Lifecycle with the Weka Manila Driver

This guide demonstrates snapshot operations through the Manila Weka driver:
creating a snapshot, reverting a share back to it (in-place recovery), and
cloning a snapshot into a new independent share.

This is the key **data protection** story for the driver. All snapshot operations
map directly to native Weka snapshot capabilities via the REST API — no data copying
is needed for create or revert.

The commands in this guide are run **inside the DevStack instance**.

---

## Before You Start

You will need:

- The **SSH key file** and **DevStack public IP** — get the IP with:

```bash
cd terraform && terraform output -raw devstack_public_ip
```

---

## Step 1 — SSH into the DevStack Instance

```bash
ssh -i weka-test.pem ubuntu@<DEVSTACK_IP>
```

---

## Step 2 — Load the OpenStack Credentials

```bash
source /opt/stack/devstack/openrc admin admin
```

---

## Step 3 — Create a Share

Create a 1 GiB NFS share to use as the source. If you have already created the
`weka_nfs` share type in a previous demo, skip the `type-create` line.

```bash
manila type-create weka_nfs false --extra-specs share_backend_name=weka \
  snapshot_support=True \
  create_share_from_snapshot_support=True \
  revert_to_snapshot_support=True
manila create --share-type weka_nfs --name snapshot-source NFS 1
manila list   # wait for 'available'
```

> If the `weka_nfs` type already exists, add the snapshot capabilities to it instead:
>
> ```bash
> manila type-key weka_nfs set snapshot_support=True
> manila type-key weka_nfs set create_share_from_snapshot_support=True
> manila type-key weka_nfs set revert_to_snapshot_support=True
> ```

---

## Step 4 — Mount the Share and Write Test Data

Get the export location:

```bash
manila share-export-location-list snapshot-source
```

Grant access so the DevStack host can mount it:

```bash
manila access-allow snapshot-source ip 10.0.2.0/24 --access-level rw
manila access-list snapshot-source   # wait for 'active'
```

Mount the share and write a test file:

```bash
sudo mkdir -p /mnt/snapshot-source
sudo mount -t nfs <export-path> /mnt/snapshot-source
echo "original data — before snapshot" | sudo tee /mnt/snapshot-source/testfile.txt
cat /mnt/snapshot-source/testfile.txt
```

---

## Step 5 — Create a Snapshot

With data on the share, take a snapshot:

```bash
manila snapshot-create snapshot-source --name demo-snapshot
```

Wait for the snapshot to become `available`:

```bash
manila snapshot-list
```

Expected output:

```
+--------------------------------------+---------------+-----------+------+------------------+
| ID                                   | Name          | Status    | Size | Share ID         |
+--------------------------------------+---------------+-----------+------+------------------+
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | demo-snapshot | available |    1 | xxxxxxxx-...     |
+--------------------------------------+---------------+-----------+------+------------------+
```

> **What just happened?** The driver called the Weka REST API to create a native
> Weka snapshot of the filesystem. The snapshot is instantaneous and space-efficient —
> it only stores changed blocks going forward.

---

## Step 6 — Modify the Share Contents

Simulate data loss or corruption by overwriting the test file:

```bash
echo "corrupted data — after snapshot" | sudo tee /mnt/snapshot-source/testfile.txt
cat /mnt/snapshot-source/testfile.txt
```

You should now see `corrupted data — after snapshot`. The original content is
preserved in the snapshot.

---

## Step 7 — Revert to Snapshot

Revert the share back to the state captured in the snapshot. The share must be
unmounted first:

```bash
sudo umount /mnt/snapshot-source
```

Then revert:

```bash
manila revert-to-snapshot demo-snapshot
```

The share briefly enters `reverting` state. Wait for `available`:

```bash
manila list
```

Remount and verify the original data is restored:

```bash
sudo mount -t nfs <export-path> /mnt/snapshot-source
cat /mnt/snapshot-source/testfile.txt
```

You should see `original data — before snapshot`.

> **What just happened?** The driver issued a Weka snapshot restore operation — an
> in-place, instant rollback. No data was copied; the filesystem pointer was moved
> back to the snapshot state.

---

## Step 8 — Create a New Share from the Snapshot

The snapshot can also be cloned into an entirely new, independent share. This is
useful for creating test environments from production snapshots.

```bash
manila create \
  --share-type weka_nfs \
  --name snapshot-clone \
  --snapshot-id demo-snapshot \
  NFS 1
```

Wait for the clone to become `available`:

```bash
manila list
```

Grant access and mount the clone:

```bash
manila access-allow snapshot-clone ip 10.0.2.0/24 --access-level rw
manila access-list snapshot-clone   # wait for 'active'

sudo mkdir -p /mnt/snapshot-clone
manila share-export-location-list snapshot-clone
sudo mount -t nfs <clone-export-path> /mnt/snapshot-clone

cat /mnt/snapshot-clone/testfile.txt
```

You should see `original data — before snapshot` — the clone has the snapshot's
data, not the current (modified) share contents.

> **What just happened?** The driver created a new Weka filesystem and copied the
> snapshot data into it via an NFS-mounted rsync. The result is a fully independent
> share — changes to either the original or the clone do not affect the other.

---

## Step 9 — Clean Up

Unmount both shares, then delete everything:

```bash
sudo umount /mnt/snapshot-source
sudo umount /mnt/snapshot-clone

manila delete snapshot-clone
manila snapshot-delete demo-snapshot
manila delete snapshot-source

manila list             # confirm shares are gone
manila snapshot-list    # confirm snapshot is gone
```

---

## Full Command Summary

```bash
# Load credentials
source /opt/stack/devstack/openrc admin admin

# Create source share
manila type-create weka_nfs false --extra-specs share_backend_name=weka snapshot_support=True create_share_from_snapshot_support=True revert_to_snapshot_support=True
manila create --share-type weka_nfs --name snapshot-source NFS 1
manila list   # wait for 'available'

# Mount and write data
manila share-export-location-list snapshot-source
manila access-allow snapshot-source ip 10.0.2.0/24 --access-level rw
sudo mkdir -p /mnt/snapshot-source
sudo mount -t nfs <export-path> /mnt/snapshot-source
echo "original data — before snapshot" | sudo tee /mnt/snapshot-source/testfile.txt

# Create snapshot
manila snapshot-create snapshot-source --name demo-snapshot
manila snapshot-list   # wait for 'available'

# Simulate data loss
echo "corrupted data — after snapshot" | sudo tee /mnt/snapshot-source/testfile.txt

# Revert to snapshot
sudo umount /mnt/snapshot-source
manila revert-to-snapshot demo-snapshot
manila list   # wait for 'available'
sudo mount -t nfs <export-path> /mnt/snapshot-source
cat /mnt/snapshot-source/testfile.txt   # should show original data

# Clone snapshot to new share
manila create --share-type weka_nfs --name snapshot-clone --snapshot-id demo-snapshot NFS 1
manila list   # wait for 'available'
manila access-allow snapshot-clone ip 10.0.2.0/24 --access-level rw
sudo mkdir -p /mnt/snapshot-clone
sudo mount -t nfs <clone-export-path> /mnt/snapshot-clone
cat /mnt/snapshot-clone/testfile.txt   # should show original data

# Clean up
sudo umount /mnt/snapshot-source
sudo umount /mnt/snapshot-clone
manila delete snapshot-clone
manila snapshot-delete demo-snapshot
manila delete snapshot-source
```

---

## Troubleshooting

**Snapshot stuck in `creating` state**

```bash
sudo tail -50 /var/log/manila/manila-share.log | grep -i snapshot
```

**`revert-to-snapshot` fails with share in `reverting_error`**

Ensure the share is unmounted before reverting. Check for active mounts:

```bash
mount | grep snapshot-source
```

**Clone stuck in `creating` state**

Clone creation copies data via rsync — it takes longer than a plain share create.
Monitor progress:

```bash
sudo tail -f /var/log/manila/manila-share.log | grep -i snapshot
```
