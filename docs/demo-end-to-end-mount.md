# Demo: End-to-End Mount with the Weka Manila Driver

This guide goes beyond share creation — it mounts a WekaFS share on the DevStack
host using the **WekaFS kernel client**, writes data, reads it back, and verifies
the quota with `df`. This proves the full stack is working: Manila → Weka REST API
→ Weka filesystem → kernel client → POSIX I/O.

The commands in this guide are run **inside the DevStack instance**.

---

## Before You Start

You will need:

- The **SSH key file** and **DevStack public IP** — get the IP with:

```bash
cd terraform && terraform output -raw devstack_public_ip
```

The WekaFS kernel module (`wekafsio`) must be loaded on the DevStack host. The
bootstrap script does this automatically — verify it in Step 3.

This demo mounts using **UDP mode** (`net=udp`). Weka still creates a client
container, but uses UDP networking rather than DPDK. This is required in this
environment because Weka cannot auto-detect the AWS network interface for DPDK
mode. The DevStack host will appear as a client in the Weka UI once mounted.

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

## Step 3 — Verify the WekaFS Kernel Module

Before mounting anything, confirm the WekaFS kernel module is loaded:

```bash
lsmod | grep wekafs
```

Expected output (module name and size will vary by version):

```
wekafsio             1234567  0
```

If the module is not loaded, run:

```bash
sudo modprobe wekafsio
lsmod | grep wekafs
```

> **Note:** Running `weka status` on the DevStack host will return an error like
> "Failed connecting to http://127.0.0.1:14000" — this is expected. The DevStack
> host is not configured as a Weka cluster member. The kernel module alone is
> sufficient for UDP-mode mounts.

---

## Step 4 — Create a Share

Create a 2 GiB WEKAFS share. If the `weka_wekafs` share type already exists from
a previous demo, skip the `type-create` line.

```bash
manila type-create weka_wekafs false --extra-specs share_backend_name=weka
manila create --share-type weka_wekafs --name mount-demo WEKAFS 2
manila list   # wait for 'available'
```

---

## Step 5 — Get the Export Location

```bash
manila share-export-location-list mount-demo
```

The export location is in the format:

```
<weka-backend-ip>/<filesystem-name>
```

Note this value — it is used as the mount source in the next step.

---

## Step 6 — Mount the Share

Create a mount point and mount the share using the WekaFS kernel client:

```bash
sudo mkdir -p /mnt/mount-demo
sudo mount -t wekafs <export-location> /mnt/mount-demo -o net=udp
```

Verify the mount succeeded:

```bash
mount | grep mount-demo
```

Expected output:

```
<export-location> on /mnt/mount-demo type wekafs (rw,relatime,...)
```

Check the available capacity — it should reflect the 2 GiB quota set by Manila:

```bash
df -h /mnt/mount-demo
```

Expected output:

```
Filesystem             Size  Used Avail Use% Mounted on
<export-location>      2.0G     0  2.0G   0% /mnt/mount-demo
```

> **What just happened?** The WekaFS kernel client mounted the Weka filesystem
> directly over the cluster fabric. The `df` output shows the Manila-managed quota
> as the filesystem size.

---

## Step 7 — Write Data

Write a test file and a directory tree to the mounted share:

```bash
echo "Hello from Weka via Manila" | sudo tee /mnt/mount-demo/hello.txt
sudo mkdir -p /mnt/mount-demo/subdir
sudo dd if=/dev/urandom of=/mnt/mount-demo/subdir/random.bin bs=1M count=64
```

The `dd` command writes 64 MiB of random data. After it completes, check usage:

```bash
df -h /mnt/mount-demo
```

You should see ~64 MiB used:

```
Filesystem             Size  Used Avail Use% Mounted on
<export-location>      2.0G   64M  1.9G   4% /mnt/mount-demo
```

---

## Step 8 — Read Back the Data

Verify the data is readable and intact:

```bash
cat /mnt/mount-demo/hello.txt
ls -lh /mnt/mount-demo/subdir/
```

Expected output:

```
Hello from Weka via Manila
total 64M
-rw-r--r-- 1 root root 64M ... random.bin
```

---

## Step 9 — Extend the Share and Observe the Quota Change

Extend `mount-demo` from 2 GiB to 4 GiB:

```bash
manila extend mount-demo 4
manila list   # wait for 'available'
```

Without unmounting, check the quota has updated:

```bash
df -h /mnt/mount-demo
```

Expected output:

```
Filesystem             Size  Used Avail Use% Mounted on
<export-location>      4.0G   64M  3.9G   2% /mnt/mount-demo
```

> **What just happened?** Manila updated the Weka filesystem quota via the REST API.
> The change is reflected immediately on all mounted clients — no remount needed.

---

## Step 10 — Unmount and Delete

Unmount the share before deleting it:

```bash
sudo umount /mnt/mount-demo
```

Confirm it is no longer mounted:

```bash
mount | grep mount-demo
```

Delete the share:

```bash
manila delete mount-demo
manila list   # confirm gone
```

---

## Full Command Summary

```bash
# Load credentials
source /opt/stack/devstack/openrc admin admin

# Verify WekaFS kernel module
lsmod | grep wekafs

# Create share
manila type-create weka_wekafs false --extra-specs share_backend_name=weka
manila create --share-type weka_wekafs --name mount-demo WEKAFS 2
manila list   # wait for 'available'

# Get export location
manila share-export-location-list mount-demo

# Mount
sudo mkdir -p /mnt/mount-demo
sudo mount -t wekafs <export-location> /mnt/mount-demo -o net=udp
mount | grep mount-demo
df -h /mnt/mount-demo   # should show 2.0G quota

# Write data
echo "Hello from Weka via Manila" | sudo tee /mnt/mount-demo/hello.txt
sudo mkdir -p /mnt/mount-demo/subdir
sudo dd if=/dev/urandom of=/mnt/mount-demo/subdir/random.bin bs=1M count=64
df -h /mnt/mount-demo   # should show ~64M used

# Read back
cat /mnt/mount-demo/hello.txt
ls -lh /mnt/mount-demo/subdir/

# Extend and observe live quota update
manila extend mount-demo 4
manila list   # wait for 'available'
df -h /mnt/mount-demo   # should now show 4.0G

# Unmount and delete
sudo umount /mnt/mount-demo
manila delete mount-demo
manila list   # confirm gone
```

---

## Troubleshooting

**`mount: unknown filesystem type 'wekafs'`**

The WekaFS kernel module is not loaded:

```bash
sudo modprobe wekafsio
lsmod | grep wekafs
```

If `modprobe` fails, the Weka agent may not be installed. Check:

```bash
weka local status
```

To reinstall the agent:

```bash
curl -sk https://<weka_alb_dns>:14000/dist/v1/install | bash
sudo modprobe wekafsio
```

**Mount hangs or times out**

Check that the Weka cluster is reachable from the DevStack host:

```bash
ping <weka-backend-ip>
curl -sk https://<weka_alb_dns>:14000/api/v2/cluster | python3 -m json.tool | head -10
```

**`df` shows wrong size after extend**

Give it a few seconds — the quota update propagates to the kernel client asynchronously.
If it does not update after 30 seconds, check Manila logs:

```bash
sudo tail -50 /var/log/manila/manila-share.log | grep -i extend
```
