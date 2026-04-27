# Demo: Manage and Unmanage Existing Weka Filesystems

This guide demonstrates how to bring an **existing Weka filesystem** under Manila
management (`manila manage`) and how to release it back to unmanaged state
(`manila unmanage`) without deleting the underlying data.

This is the key workflow for **migrations**: if you have existing Weka filesystems
that were created outside of Manila, you can adopt them into Manila's management
plane without any downtime or data movement.

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

## Step 3 — Create a Weka Filesystem Outside of Manila

To simulate a pre-existing filesystem, create one directly using the Weka CLI.
This represents what a filesystem looks like before Manila is involved.

The DevStack host is not a Weka cluster member, so the `weka` CLI must be
pointed at the cluster API with `-H`. New deployments have the following
variables set in `/etc/environment` automatically by the bootstrap script.
For existing deployments, export them manually from `manila.conf`:

```bash
export WEKA_HOST=$(sudo crudini --get /etc/manila/manila.conf weka weka_api_server)
export WEKA_USERNAME=admin
export WEKA_PASSWORD=$(sudo crudini --get /etc/manila/manila.conf weka weka_password)
export WEKA_ORG=Root
```

| Variable | Value |
|---|---|
| `WEKA_HOST` | Weka cluster ALB hostname |
| `WEKA_USERNAME` | `admin` |
| `WEKA_PASSWORD` | Weka admin password |
| `WEKA_ORG` | `Root` |

Confirm the CLI can reach the cluster:

```bash
weka status -H $WEKA_HOST
```

Create a filesystem named `pre-existing-fs` in the default filesystem group with
a 2 GiB quota:

```bash
weka fs create pre-existing-fs default 2GiB -H $WEKA_HOST
```

Verify it was created:

```bash
weka fs -H $WEKA_HOST
```

Expected output includes a row for `pre-existing-fs` with `2.00 GiB` total capacity.

> **What just happened?** You created a Weka filesystem directly via the Weka CLI,
> bypassing Manila entirely. This is what customer filesystems typically look like
> before they adopt the Manila driver.

---

## Step 4 — Find the Manila Service Host

The `manila manage` command requires the full `service_host` including the pool
name. Get it from:

```bash
openstack share pool list
```

Look for the pool whose `Backend` column is `weka`. The full host string is in
the `Name` column, in the format:

```
<hostname>@weka#<pool>
```

The pool name matches the `weka_filesystem_group` config option (defaults to
`default`). So the full host is typically:

```
<hostname>@weka#default
```

Note this value — it is referred to as `<SERVICE_HOST>` in the next step.

> **Important:** Do **not** use `manila service-list` to get this value — it
> shows only `<hostname>@weka` without the pool suffix, which will cause
> `manage_error`. Always use `openstack share pool list`.

---

## Step 5 — Manage the Filesystem

Bring `pre-existing-fs` under Manila management. The export path for a WEKAFS
share is simply the filesystem name:

```bash
manila manage \
  --name managed-fs \
  --share_type weka_wekafs \
  <SERVICE_HOST> \
  WEKAFS \
  pre-existing-fs
```

Wait for the share to become `available`:

```bash
manila list
```

Expected output:

```
+--------------------------------------+------------+-----------+------+
| ID                                   | Name       | Status    | Size |
+--------------------------------------+------------+-----------+------+
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | managed-fs | available |    2 |
+--------------------------------------+------------+-----------+------+
```

> **What just happened?** Manila imported the existing filesystem into its database.
> No data was moved and no new Weka filesystem was created. The size reported by
> Manila reflects the quota that was already set on the filesystem.

---

## Step 6 — Use the Managed Share

The managed share behaves exactly like any Manila-created share. Verify you can
inspect and extend it:

```bash
# Inspect
manila show managed-fs

# Check the export location
manila share-export-location-list managed-fs

# Extend from 2 GiB to 3 GiB
manila extend managed-fs 3
manila list   # wait for 'available'
manila show managed-fs   # confirm size = 3
```

The extend operation updates the Weka filesystem quota just as it would for a
share originally created by Manila.

---

## Step 7 — Unmanage the Share

Release the share back to unmanaged state. This removes it from Manila's database
but **does not delete** the Weka filesystem or its data:

```bash
manila unmanage managed-fs
```

Confirm the share is no longer in Manila:

```bash
manila list
```

The share should not appear. Confirm the Weka filesystem still exists and its data
is intact:

```bash
weka fs -H $WEKA_HOST
```

`pre-existing-fs` should still be listed with its current quota (3 GiB after the
extend in Step 6).

> **What just happened?** Manila removed its record of the share. The underlying
> Weka filesystem is untouched — it continues to exist and serve any clients that
> were already mounting it. You can re-manage it at any time by repeating Step 5.

---

## Step 8 — Clean Up

Delete the Weka filesystem directly (since Manila no longer manages it).
The `-f` flag is required to confirm deletion without an interactive prompt:

```bash
weka fs delete pre-existing-fs -H $WEKA_HOST -f
```

Confirm it is gone:

```bash
weka fs -H $WEKA_HOST
```

---

## Full Command Summary

```bash
# Load credentials
source /opt/stack/devstack/openrc admin admin

# Export Weka CLI credentials (new deployments have these in /etc/environment;
# for existing deployments export manually from manila.conf)
export WEKA_HOST=$(sudo crudini --get /etc/manila/manila.conf weka weka_api_server)
export WEKA_USERNAME=admin
export WEKA_PASSWORD=$(sudo crudini --get /etc/manila/manila.conf weka weka_password)
export WEKA_ORG=Root

# Create a filesystem directly on Weka (simulates a pre-existing filesystem)
weka fs create pre-existing-fs default 2GiB -H $WEKA_HOST
weka fs -H $WEKA_HOST   # confirm it exists

# Find the Manila service host — use pool list, NOT service-list
# The Name column gives the full host including pool (e.g. ip-...@weka#default)
openstack share pool list

# Manage the filesystem under Manila
manila manage \
  --name managed-fs \
  --share_type weka_wekafs \
  <SERVICE_HOST> \
  WEKAFS \
  pre-existing-fs
manila list   # wait for 'available'

# Use the managed share like any other Manila share
manila show managed-fs
manila share-export-location-list managed-fs
manila extend managed-fs 3
manila list   # wait for 'available'
manila show managed-fs   # confirm size = 3

# Unmanage — removes from Manila but does NOT delete the filesystem
manila unmanage managed-fs
manila list              # confirm share is gone from Manila
weka fs -H $WEKA_HOST   # confirm filesystem still exists on Weka

# Clean up the filesystem directly (-f required to skip interactive prompt)
weka fs delete pre-existing-fs -H $WEKA_HOST -f
weka fs -H $WEKA_HOST   # confirm gone
```

---

## Troubleshooting

**`manila manage` results in `manage_error` state**

Check Manila logs for the specific error:

```bash
sudo tail -100 /var/log/manila/manila-share.log | grep -i manage
```

Common causes:
- The filesystem name does not exist on the Weka cluster — verify with `weka fs -H $WEKA_HOST`
- Wrong `service_host` — copy it exactly from `manila service-list`
- Wrong share type — the share type must have `share_backend_name=weka`

**`manila unmanage` command not found**

Ensure OpenStack credentials are loaded:

```bash
source /opt/stack/devstack/openrc admin admin
```

**Filesystem still shows in `manila list` after unmanage**

`unmanage` is asynchronous. Wait a few seconds and run `manila list` again. If
it remains, check logs:

```bash
sudo tail -50 /var/log/manila/manila-share.log | grep -i unmanage
```
