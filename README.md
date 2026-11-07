# My Print Server Lab

Printing problems are one of the most common help desk tickets, so I set up a print server at home to practice. It is a learning project on my own computer, not a work system.

## What I set up

- One Windows machine acting as the print server
- Printers added on the server and shared from there
- Other computers connect to the shared printer name instead of setting up printers one by one
- I practiced fixing a stuck print queue by clearing the jobs and restarting the Print Spooler service

## Main steps

1. Add the printer on the server and install the right driver
2. Share the printer with a simple name
3. Connect a second computer to the shared printer
4. Print a test page
5. Break it on purpose with a stuck job, then fix the queue

The scripts folder has the PowerShell I used.
