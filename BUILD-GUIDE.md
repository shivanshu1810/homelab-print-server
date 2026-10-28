# Build Guide — Windows Print Server Homelab

Follow these steps in order. Each major step ends with a **✅ Checkpoint** — don't move on until it passes. If something fails, jump to [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Lab values used in this guide** (change them to match your network):

| Setting | Value |
|---|---|
| Print server hostname | `print.lab.local` |
| Printer IP (example) | `192.168.1.50` |
| Port type | Standard TCP/IP, RAW, port **9100** |
| Example queue / share name | `HP-Lab` |
| Default paper size | Letter |
| Duplex | On (if the printer supports it) |

---

## Step 0 — Prepare the server

1. Install **Windows Server 2022 (evaluation)** or use a **Windows 10/11 Pro** machine/VM.
2. Rename the computer to `print`:
   - Settings → System → About → **Rename this PC** → `print` → restart.
   - In a domain-less homelab, your server will be reachable as `\\print`. If you run your own DNS (or edit the client PC's `hosts` file), you can also make `print.lab.local` resolve to it — the guide uses `print.lab.local` as the friendly name.
3. Give the server a **static IP** or a **DHCP reservation** so its address never changes.
4. Give the **printer** a static IP or DHCP reservation too — print queues break when a printer's IP changes (see TROUBLESHOOTING.md).

**✅ Checkpoint:** From another PC, `ping print` (or the server's IP) gets replies, and browsing to the printer's IP in a web browser opens its status page.

---

## Step 1 — Install the printing components

**On Windows Server 2022:**

1. Open **Server Manager** → **Manage** → **Add Roles and Features**.
2. Click through to **Server Roles** and tick **Print and Document Services**.
3. Under Role Services, make sure **Print Server** is ticked.
4. Click **Next** → **Install**. A restart is usually not required.

**On Windows 10/11 Pro:**

Printing support is built in. You just need the management console:

1. Press `Win + R`, type `optionalfeatures`, press Enter.
2. Expand **Print and Document Services** and confirm **Internet Printing Client** / printing features are enabled as needed.
3. The **Print Management** console (`printmanagement.msc`) is included with Pro editions — go to Step 2.

**✅ Checkpoint:** Server Manager shows the Print and Document Services role as installed (Server), or `printmanagement.msc` opens (Pro).

---

## Step 2 — Open Print Management and check the Spooler

1. Press `Win + R`, type `printmanagement.msc`, press Enter.
2. Expand **Print Servers** → your server name. You'll see **Drivers**, **Ports**, **Printers**, and **Deployed Printers**.
3. Quick service check: press `Win + R`, type `services.msc`, find **Print Spooler**:
   - **Status:** Running
   - **Startup type:** Automatic

**✅ Checkpoint:** Print Management opens without errors and the Print Spooler service is **Running / Automatic**.

---

## Step 3 — Create a Standard TCP/IP port (RAW, port 9100)

Do this from **Print Management** so the port exists before you add the printer:

1. In Print Management, right-click **Ports** → **Add Port…**
2. Choose **Standard TCP/IP Port** → **New Port…** (the Add Printer Port wizard opens).
3. **Printer Name or IP Address:** enter the printer's IP, e.g. `192.168.1.50`.
   - The **Port Name** fills in automatically (e.g. `IP_192.168.1.50`) — that's fine.
4. If Windows can't detect the device type, choose **Generic Network Card**.
5. On the **Additional Port Information** screen:
   - Protocol: **Raw**
   - Port Number: **9100**
   - **SNMP Status Enabled:** untick it for homelab printers (SNMP is the #1 cause of printers falsely showing "Offline" — see TROUBLESHOOTING.md).
6. **Finish**.

**✅ Checkpoint:** The new port appears in the **Ports** list with Protocol **Raw** and Port **9100**.

> PowerShell alternative: `scripts/Install-PrintServer.ps1` creates the port, printer, and share in one run.

---

## Step 4 — Install the driver

Always install the driver **on the server** — clients then download it automatically when they connect.

1. Download the correct driver for your printer model from the manufacturer's site (HP / Canon / Epson / Brother). Prefer the full **signed driver package** (an `.exe` installer or an `.inf`-based package).
2. **Option A — vendor installer:** run it on the server and choose the network/TCP-IP install option if offered, or install the driver only.
3. **Option B — add the driver in Print Management:**
   1. Right-click **Drivers** → **Add Driver…**
   2. Choose the processor architecture (**x64** for almost all modern labs).
   3. If your model isn't listed, click **Have Disk…** and point to the driver's `.inf` file.
   4. Finish the wizard.

**✅ Checkpoint:** Your driver appears under **Drivers** in Print Management, with no error icons.

---

## Step 5 — Create and share the queue

1. In Print Management, right-click **Printers** → **Add Printer…**
2. Choose **Add a new printer using an existing port** and select the TCP/IP port from Step 3.
3. Choose **Use an existing printer driver on the computer** and pick the driver from Step 4.
4. **Printer Name:** give the queue a clear name, e.g. `HP-Lab`.
5. **Sharing:** select **Share this printer**:
   - **Share name:** short, no spaces — e.g. `HP-Lab`
   - Tick **List in the directory** only if you run Active Directory (skip in most homelabs).
6. Finish. Optionally tick "Print a test page" — do it in Step 7 anyway.

**✅ Checkpoint:** The printer appears under **Printers** with the share icon, and from another PC you can see it by browsing to `\\print.lab.local` (or `\\print`).

---

## Step 6 — Set queue defaults

Defaults set on the server are inherited by every client that connects.

1. In Print Management, right-click your printer → **Set Printing Defaults…**
2. Set:
   - **Paper size:** Letter
   - **Duplex / Print on both sides:** "Flip on long edge" if the printer supports duplex (otherwise leave single-sided)
   - Colour: leave on **Colour** for colour printers, or **Monochrome** to save toner on shared office queues — your choice in a lab.
3. **OK** to save.
4. Also right-click the printer → **Properties** → **Advanced** tab and confirm:
   - **Spool print documents…** is selected (normal behaviour)
   - Driver shown is the correct one from Step 4.

**✅ Checkpoint:** Reopen **Set Printing Defaults** — Letter and your duplex choice stuck.

---

## Step 7 — Print a test page from the server

1. Right-click the printer → **Properties** → **Print Test Page**.
2. Watch the queue: right-click the printer → **See what's printing**. The job should appear, spool, and disappear.

**✅ Checkpoint:** The test page physically prints, and the queue returns to **0 jobs**.

---

## Step 8 — Connect a client PC

On a second Windows PC on the same network:

1. Press `Win + R`, type:

   ```
   \\print.lab.local\HP-Lab
   ```

   (Use your share name. If `print.lab.local` doesn't resolve in your lab, use `\\print\HP-Lab` or `\\<server-IP>\HP-Lab`.)
2. First connection installs the driver automatically from the server — this is the whole point of a print server. You may see a brief "installing driver" prompt.
3. The queue window opens and the printer is now in the client's **Settings → Bluetooth & devices → Printers & scanners**.
4. (Optional) Right-click the printer → **Printing preferences** and confirm the defaults from Step 6 (Letter, duplex) came across.
5. Print a test page from the client: printer **Properties** → **Print Test Page**.

**✅ Checkpoint:** The client's test page prints, and on the server the job briefly appears in the shared queue and clears.

---

## Step 9 — Verify queue health

On the server:

1. Run the health script in PowerShell:

   ```powershell
   .\scripts\Get-PrintQueueHealth.ps1
   ```

2. You're looking for:
   - **Print Spooler:** Running
   - Every queue: **Ready** (or Idle), job count **0** after test pages clear
   - **No stuck or error jobs**

Manual check: open each queue ("See what's printing") — an empty list with status **Ready** is a healthy queue.

**✅ Checkpoint:** Spooler running, all queues Ready, **0 stuck jobs**. Your print server works.

---

## Step 10 (optional) — Add a second queue

Repeat Steps 3–8 for a second printer (different IP, driver, and share name, e.g. `Canon-Lab`). Two queues on one server is when centralised printing starts to feel real: one place to check drivers, defaults, and queue health for the whole "office."

**✅ Checkpoint:** Both queues show in Print Management and in `\\print.lab.local`, and a test page prints from each.

---

## Step 11 (optional) — Set queue permissions

By default, everyone can print. On a real office server you'd also control who can manage the queue:

1. Printer **Properties** → **Security** tab.
2. Typical setup:
   - **Everyone / Domain Users:** Print ✔
   - **Creator Owner:** Manage Documents ✔
   - **Administrators / a "Print Admins" group:** Print, Manage Documents, **Manage Printer** ✔
3. In a homelab (no domain), leave **Everyone: Print** in place and just look at the tab so you recognise it — know that **Manage Printer** is the permission that lets someone pause queues, change ports, and delete printers, so it's admin-only in real environments.

**✅ Checkpoint:** You can explain the difference between **Print**, **Manage Documents**, and **Manage Printer** permissions.

---

## You're done

You now have a working Windows print server: centralised drivers and queues on `print.lab.local`, clients connecting by share name, and a repeatable way to check queue health. Keep [TROUBLESHOOTING.md](TROUBLESHOOTING.md) nearby — sooner or later, someone (probably you) will file the "I cannot print" ticket.
