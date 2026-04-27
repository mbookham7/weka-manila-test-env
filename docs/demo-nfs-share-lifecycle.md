# Demo: NFS Share Lifecycle with the Weka Manila Driver

This guide walks through a live demonstration of the Manila Weka driver using the
**NFS protocol** — creating a share, granting IP-based access, extending, shrinking,
and deleting it.

NFS shares are the best protocol to demonstrate **Manila access rules**: unlike WEKAFS
shares, NFS shares fully support `manila access-allow` with IP/CIDR rules, which the
driver maps to Weka client groups on the backend.

The commands in this guide are run **inside the DevStack instance**, which you reach
via SSH from your laptop.

---

## Before You Start

You will need:

- The **SSH key file** for the test environment (e.g. `weka-test.pem`)
- The **DevStack public IP address** — get it by running this on your laptop:

```bash
cd terraform && terraform output -raw devstack_public_ip
```

Make a note of the IP. It is referenced as `<DEVSTACK_IP>` throughout this guide.

---

## Step 1 — SSH into the DevStack Instance

```bash
ssh -i weka-test.pem ubuntu@<DEVSTACK_IP>
```

You should see a prompt like:

```
ubuntu@ip-10-0-2-xxx:~$
```

---

## Step 2 — Load the OpenStack Credentials

```bash
source /opt/stack/devstack/openrc admin admin
```

---

## Step 3 — Create a Share Type for NFS

A share type tells Manila which driver and protocol to use. Create one for NFS:

```bash
manila type-create weka_nfs false --extra-specs share_backend_name=weka snapshot_support=True create_share_from_snapshot_support=True revert_to_snapshot_support=True
```

Verify it was created:

```bash
manila type-list
```

You should see `weka_nfs` in the list.

> If you see an error saying the type already exists, skip ahead to Step 4.

---

## Step 4 — Create an NFS Share

Create a 1 GiB NFS share named `demo-nfs`:

```bash
manila create --share-type weka_nfs --name demo-nfs NFS 1
```

Wait for it to become `available`:

```bash
manila list
```

Expected output:

```
+--------------------------------------+----------+-----------+------+
| ID                                   | Name     | Status    | Size |
+--------------------------------------+----------+-----------+------+
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | demo-nfs | available |    1 |
+--------------------------------------+----------+-----------+------+
```

> **What just happened?** The driver created a Weka filesystem with a 1 GiB quota
> and configured it for NFS export. Manila now manages this filesystem as an NFS share.

---

## Step 5 — Check the Export Location

```bash
manila share-export-location-list demo-nfs
```

You will see a path in the format:

```
<weka-backend-ip>:/<filesystem-name>
```

This is the NFS path clients use to mount the share. Note it down — it is used in
Step 6.

---

## Step 6 — Grant Access

NFS shares use IP/CIDR-based access rules. Grant read-write access to the DevStack
subnet:

```bash
manila access-allow demo-nfs ip 10.0.2.0/24 --access-level rw
```

The access rule briefly enters `queued_to_apply` state, then moves to `active`.
Check it:

```bash
manila access-list demo-nfs
```

Expected output:

```
+--------------------------------------+-------------+-----------+------------+--------+
| id                                   | access_type | access_to | access_lev | state  |
+--------------------------------------+-------------+-----------+------------+--------+
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | ip          | 10.0.2.0/ | rw         | active |
+--------------------------------------+-------------+-----------+------------+--------+
```

> **What just happened?** The driver created a Weka **client group** matching
> `10.0.2.0/24` and associated it with the filesystem's NFS export. Only clients
> in that subnet can mount this share.

---

## Step 7 — Add a Read-Only Rule

You can layer multiple access rules. Add a second subnet with read-only access:

```bash
manila access-allow demo-nfs ip 10.0.1.0/24 --access-level ro
```

Confirm both rules are active:

```bash
manila access-list demo-nfs
```

---

## Step 8 — Extend the Share

Extend `demo-nfs` from 1 GiB to 2 GiB:

```bash
manila extend demo-nfs 2
```

Wait for `available`, then confirm:

```bash
manila list
manila show demo-nfs
```

Look for `size | 2`.

---

## Step 9 — Shrink the Share

Shrink `demo-nfs` back to 1 GiB:

```bash
manila shrink demo-nfs 1
```

Wait for `available`, then confirm:

```bash
manila list
manila show demo-nfs
```

Look for `size | 1`.

> **Note:** Manila will refuse to shrink below the share's current used capacity.
> A `shrinking_error` means there is more data on the share than the target size allows.

---

## Step 10 — Revoke Access

Remove the read-write rule. First, get its ID:

```bash
manila access-list demo-nfs
```

Then revoke it:

```bash
manila access-deny demo-nfs <access-rule-id>
```

Confirm the rule is gone:

```bash
manila access-list demo-nfs
```

---

## Step 11 — Delete the Share

```bash
manila delete demo-nfs
```

Confirm it is gone:

```bash
manila list
```

> **What just happened?** The driver removed the NFS export, deleted the Weka client
> group, and deleted the underlying Weka filesystem. Storage capacity has been returned
> to the cluster pool.

---

## Full Command Summary

```bash
# Load credentials
source /opt/stack/devstack/openrc admin admin

# Create share type (once per environment)
manila type-create weka_nfs false --extra-specs share_backend_name=weka snapshot_support=True create_share_from_snapshot_support=True revert_to_snapshot_support=True

# Create a 1 GiB NFS share
manila create --share-type weka_nfs --name demo-nfs NFS 1
manila list   # wait for 'available'

# Get export location
manila share-export-location-list demo-nfs

# Grant access
manila access-allow demo-nfs ip 10.0.2.0/24 --access-level rw
manila access-allow demo-nfs ip 10.0.1.0/24 --access-level ro
manila access-list demo-nfs   # confirm both rules active

# Extend to 2 GiB
manila extend demo-nfs 2
manila list   # wait for 'available'
manila show demo-nfs   # confirm size = 2

# Shrink back to 1 GiB
manila shrink demo-nfs 1
manila list   # wait for 'available'
manila show demo-nfs   # confirm size = 1

# Revoke access (replace with actual rule ID)
manila access-list demo-nfs
manila access-deny demo-nfs <access-rule-id>

# Delete
manila delete demo-nfs
manila list   # confirm gone
```

---

## Troubleshooting

**Access rule stuck in `queued_to_apply`**

```bash
sudo tail -50 /var/log/manila/manila-share.log | grep -i access
```

**Mount refused after access-allow**

Check the access rule is `active` (not `error`):

```bash
manila access-list demo-nfs
```

If it is in `error` state, check Manila logs for a Weka API error:

```bash
sudo tail -100 /var/log/manila/manila-share.log | grep ERROR
```

**Share stuck in `creating` state**

```bash
sudo tail -50 /var/log/manila/manila-share.log
```
