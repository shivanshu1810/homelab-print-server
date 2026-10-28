# "I Cannot Print" — Ticket Playbook

How a service desk actually works a print ticket: start with the simplest, most common causes and move down the list. Each item is written as **Symptom → Cause → Fix → Verify**, the way you'd note it on a real ticket.

**Golden rule:** fix one thing at a time, re-test after each fix, and write down what worked. Half of print troubleshooting is discovering which layer broke: the printer, the network, the server, the queue, the driver, or the client.

---

## Triage order (work top to bottom)

1. Printer power, paper, and error lights
2. Ping the printer — is it on the network at all?
3. Print Spooler service on the server — is it running?
4. Stuck job at the top of the queue
5. Wrong or corrupted driver
6. Printer shows "Offline" but isn't (SNMP status)
7. Printer IP changed (DHCP) — set a reservation or static IP

---

## 1. Printer power, paper, toner, error lights

**Symptom →** User says "nothing prints." Printer display is dark, or shows a paper jam / out-of-paper / door-open message, or a blinking amber light.

**Cause →** The most common cause of all: the printer itself. Powered off, out of paper, jammed, a tray open, or out of toner. No server fix exists for a printer with no paper.

**Fix →**
- Confirm the printer is powered on.
- Check every tray has the right paper (Letter in this lab) seated properly.
- Clear any jam — pull paper out **slowly, in the direction of travel**, then open and close the doors to reset the sensors.
- Reseat toner/ink if the printer reports it empty or unrecognised.

**Verify →** The printer's own status page or display shows **Ready**. Print a test page from the printer's built-in menu — if the printer can't print its own page, the problem is the printer, not the network.

---

## 2. Ping the printer

**Symptom →** Jobs sit in the queue and never move. Server shows the printer as unavailable. Several users affected at once.

**Cause →** The printer is off the network: unplugged cable, Wi-Fi dropped, switch port dead — or its IP address changed (see item 7).

**Fix →**
1. From the print server, open PowerShell or Command Prompt:

   ```
   ping 192.168.1.50
   ```

   (Use your printer's IP.)
2. **No replies:** check the printer's power and network cable / Wi-Fi connection. Check the IP shown on the printer's display or its printed network config page — is it the IP you pinged?
3. **Replies received:** the printer is on the network; move to item 3.

**Verify →** Ping replies return consistently (no "Request timed out"), and browsing to `http://<printer-IP>` opens the printer's web status page.

---

## 3. Print Spooler service stopped

**Symptom →** **Nobody** can print to **any** queue on the server. Queues may look greyed out, or clients get errors connecting. One bad job or driver crash can take the spooler down for everyone.

**Cause →** The Print Spooler service on the server has stopped or is stuck.

**Fix →**
1. On the server, open `services.msc` → find **Print Spooler**.
2. If it's stopped, **Start** it. Confirm Startup type is **Automatic**.
3. Or in PowerShell:

   ```powershell
   Get-Service Spooler
   Restart-Service Spooler
   ```

4. Or run this repo's script, which restarts it and prints queue status after:

   ```powershell
   .\scripts\Restart-PrintSpooler.ps1
   ```

**Verify →** Spooler shows **Running**, and a fresh test page prints. If the spooler keeps stopping, a corrupt job or driver is usually the cause — see items 4 and 5.

---

## 4. Stuck job at the top of the queue

**Symptom →** One user's job sits at the top of the queue with status **Error**, **Error – Printing**, or similar — and **every job behind it is blocked too**. The queue looks "full" but nothing prints.

**Cause →** A corrupt or oversized job (huge PDFs and photos are classics) failed mid-print and is wedging the queue. A queue prints strictly in order, so one bad job stops everyone.

**Fix →**
1. Open the queue (Print Management → printer → **See what's printing**), or run:

   ```powershell
   .\scripts\Get-PrintQueueHealth.ps1
   ```

   to see exactly which job is stuck.
2. Try the gentle fix first: right-click the stuck job → **Cancel**. Right-click other held jobs → **Restart** if needed.
3. If the job won't cancel (very common), do the full spooler flush:
   - Run:

     ```powershell
     .\scripts\Restart-PrintSpooler.ps1 -ClearStuckJobs
     ```

   - The script asks you to confirm, stops the spooler, deletes the pending job files (`*.SHD` / `*.SPL`) in `C:\Windows\System32\spool\PRINTERS`, and restarts the spooler.
   - **Tell affected users first:** this removes *all* pending jobs on the server — they will need to resend anything that hadn't printed.

**Verify →** The queue is empty, status shows **Ready**, and a new test page prints immediately. The original sender re-sends their document — if it jams again on the same document, the document itself is the problem (try printing it as an image from the PDF reader, or to a different queue).

---

## 5. Wrong or corrupted driver

**Symptom →** Print jobs vanish from the queue but nothing comes out — or pages of garbled symbols print. Spooler crashes when one particular PC prints. Problems started right after a Windows update or a "helpful" driver install on a client.

**Cause →** The queue is using the wrong driver for the printer model (or a corrupted one). Classic giveaway: gibberish output usually means a PostScript/PCL mismatch.

**Fix →**
1. On the **server** (never fix drivers client-by-client — that's the point of a print server): Print Management → printer → **Properties** → **Advanced** tab → check the **Driver** name matches the actual printer model.
2. If wrong: download the correct driver from the manufacturer's site (signed package preferred), install it via **Drivers → Add Driver…**, then switch the queue to it on the Advanced tab.
3. If the driver is correct but behaving badly: remove the queue's driver package and reinstall a fresh copy, then re-add the queue (`scripts/Install-PrintServer.ps1` recreates the queue once the good driver is installed).
4. Ask affected clients to remove and re-add the shared printer (`\\print.lab.local\<ShareName>`) so they pull the fresh driver from the server.

**Verify →** A test page from the server **and** from a client prints cleanly — correct text, correct formatting, no symbol soup.

---

## 6. Printer shows "Offline" but it isn't (SNMP false offline)

**Symptom →** Windows insists the printer is **Offline** and holds all jobs — but the printer is on, pingable, its web page loads, and it happily prints its own test page.

**Cause →** Windows checks printer status using **SNMP**. If the printer doesn't answer SNMP the way Windows expects (or a community string / firewall blocks it), Windows marks the queue Offline and refuses to print — even though the RAW printing path on port 9100 is perfectly fine.

**Fix →**
1. On the server: Print Management → **Ports** → right-click the printer's TCP/IP port → **Configure Port…**
2. **Untick "SNMP Status Enabled."**
3. Click OK. The queue usually flips back to **Ready** within a few seconds.
4. (This is why BUILD-GUIDE.md turns SNMP off when creating the port.)

**Verify →** Queue status shows **Ready** instead of Offline, held jobs start printing, and `.\scripts\Get-PrintQueueHealth.ps1` reports the queue as OK.

---

## 7. Printer IP changed by DHCP

**Symptom →** Printing worked yesterday, dead today. Pinging the printer's old IP fails — but the printer is on, and its display shows a **different IP address** than the queue's port uses. Often happens after a power cut or router reboot.

**Cause →** The printer got its IP from DHCP and the lease changed. The server's TCP/IP port still points at the **old** IP, so jobs go nowhere.

**Fix →**
- **Short term:** update the queue's port to the printer's current IP (or create a new port with `scripts/Install-PrintServer.ps1` using the new IP and switch the queue to it).
- **Real fix (always do this on a print server):** stop the address from changing:
  - Set a **DHCP reservation** in the router/DHCP server for the printer's MAC address, **or**
  - Set a **static IP** on the printer itself (outside the DHCP pool, e.g. `.50` in this lab).
- Do the same for the print server — clients connect to it by name, and it should never move either.

**Verify →** Reboot the printer and confirm it comes back on the **same** IP. Ping it, print a test page, and note the reserved/static IP on the ticket so the next tech doesn't rediscover it.

---

## Quick reference — ticket notes template

Copy this into the ticket as you work it:

```
Issue:        User(s) cannot print to <queue name>
Scope:        One user / one queue / all queues on the server
Printer:      Power OK? Paper? Error lights? Own test page prints?
Network:      Ping printer IP — replies Y/N. IP on printer display matches port?
Server:       Spooler service Running? Queue status?
Queue:        Stuck job? (Get-PrintQueueHealth.ps1) Job ID / document / user
Driver:       Correct model on the queue? Changed recently?
Offline?:     SNMP Status Enabled on the port — untick and retest
IP changed?:  DHCP reservation / static IP set for the printer?
Fix applied:  <what you actually did>
Verify:       Test page printed from server AND client. Queue back to 0 jobs.
```

If you've worked this list top to bottom and it still won't print, you now have real diagnostic notes to escalate with — which is exactly what a good service desk ticket looks like.
