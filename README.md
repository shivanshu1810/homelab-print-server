# Homelab Print Server (Windows)

A self-directed homelab project that turns one Windows machine into a **central print server** for a small network — the same setup used in offices, schools, clinics, and warehouses everywhere.

Instead of every PC talking to every printer on its own, all printers, drivers, and queues live on **one server** (`print.lab.local`). Clients just connect to a share name, and the server handles the rest.

---

## Why this project?

**"I can't print" is the #1 helpdesk ticket in almost every workplace.**

Service desk and IT support roles deal with print problems daily:
- Stuck jobs blocking a whole queue
- Wrong or corrupted drivers
- Printers showing "offline" when they aren't
- Users who can't find the right printer

Building a print server at home teaches the exact skills behind those tickets: how queues, ports, drivers, and the Print Spooler service fit together — and how to fix them when they break. This project is the print-server companion to basic Windows Server / desktop support skills that show up in entry-level IT support, service desk, and helpdesk job postings.

---

## What the finished lab looks like

One Windows machine acts as the print server:

```
                        +----------------------+
   Client PC  --------> |                      |
 (\\print.lab.local)    |   PRINT SERVER       |
                        |   print.lab.local    |
   Client PC  --------> |                      |
                        |  Queues:             | ----> HP-style printer   (TCP/IP, port 9100)
   Laptop     --------> |   HP-Lab             | ----> Canon-style printer (TCP/IP, port 9100)
                        |   Canon-Lab          | ----> Epson-style printer (TCP/IP, port 9100)
                        |   Epson-Lab          |
                        +----------------------+
                          Print Spooler service
                          Drivers stored once,
                          on the server
```

In words:
- The **print server** holds every printer's driver and print queue in one place.
- Each physical printer is reached over the network using a **Standard TCP/IP port** with **RAW printing on port 9100** (the way most office printers accept jobs).
- Each queue is **shared** with a clean name (for example `HP-Lab`), so a client PC connects with `\\print.lab.local\HP-Lab` and automatically gets the right driver from the server.
- The **Print Spooler** service on the server accepts jobs from clients, holds them in the queue, and sends them to the printer in order.
- The goal state: every queue healthy, **0 stuck jobs**, test pages printing from both the server and a client.

---

## Skills demonstrated

- Installing and using **Print Management** (Windows print administration console)
- Creating **Standard TCP/IP printer ports** (RAW, port 9100)
- Installing a **printer driver** (including a signed driver package) on a server
- Creating and **sharing print queues** with clean share names
- Setting queue **defaults** (paper size Letter, duplex) that clients inherit
- Connecting a **client PC** to a shared queue and printing a test page
- Checking **queue health**: queue status, job counts, stuck/error jobs
- Restarting the **Print Spooler** service safely and clearing stuck jobs
- Basic print troubleshooting: offline printers, SNMP false-offline, DHCP IP changes
- **PowerShell** automation for setup and health checks (scripts included)

---

## What you need

| Item | Notes |
|---|---|
| A Windows machine or VM to be the print server | **Windows Server 2022 evaluation** (free 180-day trial from Microsoft) **or Windows 10/11 Pro** — both can share printers. Server gives you the full Print and Document Services role; Pro works fine for a homelab. |
| A second PC (or VM) to act as a client | Any Windows PC on the same network. |
| A network printer | Any printer with Ethernet/Wi-Fi that accepts TCP/IP printing (most HP, Canon, Epson, Brother office printers do). No printer? A second PC can act as a TCP/IP printer target for practice, or you can build everything up to the test-page step and still learn the queue/port/driver workflow. |
| The printer's driver | Download the correct model driver from the manufacturer's website (a signed driver package installs most cleanly). |
| Admin rights on the server | Needed to install drivers, ports, and shares. |
| About 1–2 hours | Less if your VM is already installed. |

**Suggested lab naming (used throughout this repo):**

- Server hostname: `print.lab.local`
- Example queue/share names: `HP-Lab`, `Canon-Lab`, `Epson-Lab`
- Printer port: Standard TCP/IP, RAW, **port 9100**

---

## Build steps (summary)

Full instructions are in **[BUILD-GUIDE.md](BUILD-GUIDE.md)**. The short version:

1. Name the server `print` and give it a stable IP address.
2. Install the printing components (Print and Document Services on Server; Print Management console on Pro).
3. Confirm the **Print Spooler** service is running.
4. Create a **Standard TCP/IP port** pointing at the printer's IP, RAW, port 9100.
5. Install the printer **driver** (signed package where possible).
6. Create the queue and **share it** with a clean share name.
7. Set defaults: **Letter** paper, duplex on (if the printer supports it).
8. From a client PC, connect with `\\print.lab.local\<ShareName>` and print a **test page**.
9. Verify queue health: queue shows Ready, **0 stuck jobs** (use `scripts/Get-PrintQueueHealth.ps1`).
10. Optional: add a second queue, then set queue permissions.

When something breaks, **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** is an "I cannot print" ticket playbook written the way a service desk would work the problem.

---

## Repo structure

```
homelab-print-server/
├── README.md                        <- you are here
├── BUILD-GUIDE.md                   <- full step-by-step build
├── TROUBLESHOOTING.md               <- "I cannot print" ticket playbook
└── scripts/
    ├── Install-PrintServer.ps1      <- sets up a port, printer, and share
    ├── Get-PrintQueueHealth.ps1     <- report-only queue + spooler health check
    └── Restart-PrintSpooler.ps1     <- safe spooler restart (optional stuck-job cleanup)
```

The scripts target **Windows PowerShell 5.1** (the version built into Windows) and are safe to re-run: the installer skips anything that already exists, the health script changes nothing, and the restart script only clears stuck job files if you explicitly ask it to and confirm.

---

## Honest note

This is a **self-directed homelab project** built for learning — it is not production work and was not built for an employer. It documents a standard, real-world print server setup (centralized queues, TCP/IP RAW printing, shared queues, spooler management) so the skills can be practised, demonstrated, and talked about confidently in interviews for IT support / service desk roles.
