# Demo: POSIX Share Lifecycle with the Weka Manila Driver

This guide walks through a live demonstration of the Manila Weka driver — creating,
extending, shrinking, and deleting a shared filesystem on a Weka storage cluster
using the **WekaFS POSIX protocol** (native WekaFS mount).

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

Open a terminal on your laptop and run:

```bash
ssh -i weka-test.pem ubuntu@<DEVSTACK_IP>
```

You should see a welcome banner and a prompt like:

```
ubuntu@ip-10-0-2-xxx:~$
```

> **Note:** If you see a "Permission denied" error, check that the key file has
> the right permissions: `chmod 400 weka-test.pem`

---

## Step 2 — Load the OpenStack Credentials

All Manila commands require OpenStack credentials. Run this once per session:

```bash
source /opt/stack/devstack/openrc admin admin
```

There is no output — this is normal. Your terminal is now authenticated as the
OpenStack `admin` user.

---

## Step 3 — Verify the Driver is Running

Before creating anything, confirm the Manila Weka driver is healthy:

```bash
manila service-list
```

Expected output (both services should show `up`):

```
+----+------------------+------+----------+---------+
| Id | Binary           | Host | Zone     | Status  |
+----+------------------+------+----------+---------+
|  1 | manila-scheduler | ...  | nova     | up      |
|  2 | manila-share     | ...  | nova     | up      |
+----+------------------+------+----------+---------+
```

Then confirm the Weka storage pool is visible:

```bash
manila pool-list --detail
```

You should see a pool named `weka` with `WekaShare` as the driver.

---

## Step 4 — Create a Share Type

A **share type** tells Manila which driver and protocol to use. Create one for
the WekaFS POSIX protocol:

```bash
manila type-create weka_wekafs false --extra-specs share_backend_name=weka
```

Verify it was created:

```bash
manila type-list
```

You should see `weka_wekafs` in the list.

> If you see an error saying the type already exists, skip ahead to Step 5.

---

## Step 5 — Create a Share

Create a 1 GiB WEKAFS share named `demo-share`:

```bash
manila create --share-type weka_wekafs --name demo-share WEKAFS 1
```

The share will be in `creating` state for a few seconds while the driver provisions
a filesystem on Weka. Wait for it to become `available`:

```bash
manila list
```

Run `manila list` again after a few seconds until you see:

```
+--------------------------------------+------------+-----------+------+
| ID                                   | Name       | Status    | Size |
+--------------------------------------+------------+-----------+------+
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | demo-share | available |    1 |
+--------------------------------------+------------+-----------+------+
```

> **What just happened?** The Manila Weka driver called the Weka REST API and
> created a new Weka filesystem with a 1 GiB quota. Manila is now managing that
> filesystem as a shared POSIX storage resource.

---

## Step 6 — Check the Export Location

The **export location** is the WekaFS mount path clients use to access the share:

```bash
manila share-export-location-list demo-share
```

You will see a path in the format:

```
<weka-backend-ip>/<filesystem-name>
```

This is the path passed to the WekaFS kernel client when mounting.

> **A note on access control:** WekaFS shares use Weka's own authentication
> layer — not Manila access rules. If you run `manila access-allow` on a WEKAFS
> share, it will return `error` state. This is expected behaviour. In this test
> environment, network access is controlled at the VPC security group level.

---

## Step 7 — Extend the Share

Growing a share updates the quota on the Weka filesystem — no data is moved and
no downtime occurs. Extend `demo-share` from 1 GiB to 2 GiB:

```bash
manila extend demo-share 2
```

The share briefly enters `extending` state. Wait for it to return to `available`:

```bash
manila list
```

Once available, verify the new size:

```bash
manila show demo-share
```

Look for `size | 2` in the output. The Weka filesystem quota has been updated.

---

## Step 8 — Shrink the Share

Shrinking reduces the quota back down. Shrink `demo-share` from 2 GiB to 1 GiB:

```bash
manila shrink demo-share 1
```

The share briefly enters `shrinking` state. Wait for `available`:

```bash
manila list
```

Then confirm:

```bash
manila show demo-share
```

Look for `size | 1`. The Weka filesystem quota has been reduced.

> **Note:** Manila will refuse to shrink a share below its current used capacity.
> If a shrink fails with `shrinking_error`, there is more data on the share than
> the target size allows.

---

## Step 9 — Delete the Share

Delete the share:

```bash
manila delete demo-share
```

The share enters `deleting` state while the driver removes the underlying Weka
filesystem. Confirm it is gone:

```bash
manila list
```

The share should no longer appear in the list.

> **What just happened?** The Manila Weka driver called the Weka REST API to
> delete the filesystem backing this share. Storage capacity has been returned
> to the Weka cluster pool.

---

## Full Command Summary

Here is the entire lifecycle in one block for quick reference:

```bash
# Load credentials
source /opt/stack/devstack/openrc admin admin

# Create share type (once per environment)
manila type-create weka_wekafs false --extra-specs share_backend_name=weka

# Create a 1 GiB WEKAFS (POSIX) share
manila create --share-type weka_wekafs --name demo-share WEKAFS 1
manila list   # wait for 'available'

# Get mount path
manila share-export-location-list demo-share

# Extend to 2 GiB
manila extend demo-share 2
manila list   # wait for 'available'
manila show demo-share   # confirm size = 2

# Shrink back to 1 GiB
manila shrink demo-share 1
manila list   # wait for 'available'
manila show demo-share   # confirm size = 1

# Delete
manila delete demo-share
manila list   # confirm gone
```

---

## Troubleshooting

**Share stuck in `creating` state**

```bash
sudo tail -50 /var/log/manila/manila-share.log
```

**`manila` command not found**

```bash
source /opt/stack/devstack/openrc admin admin
```

**Share in `error` state**

```bash
manila show demo-share
sudo tail -100 /var/log/manila/manila-share.log | grep ERROR
```

**WekaFS kernel module not loaded**

```bash
lsmod | grep wekafs
sudo modprobe wekafsio
```
