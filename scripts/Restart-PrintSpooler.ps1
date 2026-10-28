<#
.SYNOPSIS
    Safely restarts the Print Spooler service, with optional stuck-job cleanup.

.DESCRIPTION
    Restart-PrintSpooler.ps1 is the standard first fix for a wedged print
    queue: restart the Print Spooler service, then show the queue status so
    you can confirm things are moving again.

    Default behaviour (no switches):
      1. Restarts the Spooler service (Restart-Service).
      2. Prints a status table of every queue and its job count.

    With -ClearStuckJobs:
      1. Asks for interactive confirmation FIRST - nothing is deleted
         before you type Y.
      2. Stops the Spooler service.
      3. Deletes the stuck job files (*.SHD and *.SPL) from the spool
         folder (C:\Windows\System32\spool\PRINTERS). These files ARE the
         pending print jobs, so every job still in every queue on this
         server is removed - users must resend anything that had not
         printed yet. That is why the confirmation exists.
      4. Starts the Spooler service and prints the queue status.

    The script reports each action it takes. It never touches drivers,
    ports, queues, or printer settings.

.PARAMETER ClearStuckJobs
    Switch. When present, the script (after your confirmation) stops the
    spooler, deletes pending job files from the spool folder, and restarts
    the spooler. Omit it to only restart the service.

.EXAMPLE
    .\Restart-PrintSpooler.ps1

    Restarts the Print Spooler and prints queue status afterwards.

.EXAMPLE
    .\Restart-PrintSpooler.ps1 -ClearStuckJobs

    Prompts for confirmation, then clears all pending job files and
    restarts the spooler - the full fix for a queue blocked by a bad job.

.NOTES
    Author : Homelab project (self-directed learning)
    Target : Windows PowerShell 5.1 on Windows Server 2022 / Windows 10/11 Pro
    Requires: Administrator rights (restarting services / spool folder).
    Warning : Restarting the spooler briefly interrupts printing for every
              queue on the server. On a real office server, warn users first
              if you can.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$ClearStuckJobs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$spoolFolder = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'

# ---------------------------------------------------------------------------
# Helper: show a quick status table of all queues
# ---------------------------------------------------------------------------
function Show-QueueStatus {
    Write-Host ""
    Write-Host "--- Queue status ---" -ForegroundColor Yellow
    $spooler = Get-Service -Name Spooler
    Write-Host "Print Spooler: $($spooler.Status)"

    $printers = @(Get-Printer -ErrorAction SilentlyContinue | Sort-Object -Property Name)
    if ($printers.Count -eq 0) {
        Write-Host "No print queues found."
        return
    }

    $rows = foreach ($printer in $printers) {
        $jobs = @(Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue)
        [PSCustomObject]@{
            Queue  = $printer.Name
            Status = $printer.PrinterStatus
            Jobs   = $jobs.Count
        }
    }
    $rows | Format-Table -AutoSize | Out-String | Write-Host
}

# ---------------------------------------------------------------------------
# Pre-flight: must be running as administrator
# ---------------------------------------------------------------------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please re-run this script from an elevated PowerShell prompt (Run as administrator)."
    return
}

Write-Host ""
Write-Host "=== Restart Print Spooler ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Simple path: restart only
# ---------------------------------------------------------------------------
if (-not $ClearStuckJobs) {
    Write-Host "Restarting the Print Spooler service..."
    Restart-Service -Name Spooler -Force
    Write-Host "Print Spooler restarted. New status: $((Get-Service -Name Spooler).Status)" -ForegroundColor Green

    Show-QueueStatus

    Write-Host "Done. If a queue still shows stuck jobs, re-run with -ClearStuckJobs"
    Write-Host "to remove the pending job files (users will need to resend their jobs)."
    return
}

# ---------------------------------------------------------------------------
# ClearStuckJobs path: confirm FIRST, before anything is stopped or deleted
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "WARNING: -ClearStuckJobs deletes the pending job files in:" -ForegroundColor Red
Write-Host "  $spoolFolder"
Write-Host "Every job still queued on this server will be REMOVED and must be resent."
Write-Host ""
$answer = Read-Host "Type Y and press Enter to continue, or anything else to cancel"

if ($answer -ne 'Y' -and $answer -ne 'y') {
    Write-Host "Cancelled. Nothing was stopped or deleted."
    return
}

Write-Host ""
Write-Host "[1/3] Stopping the Print Spooler service..."
Stop-Service -Name Spooler -Force
Write-Host "      Spooler stopped."

Write-Host "[2/3] Removing stuck job files (*.SHD, *.SPL)..."
$jobFiles = @()
if (Test-Path -Path $spoolFolder) {
    $jobFiles = @(Get-ChildItem -Path $spoolFolder -Include '*.SHD', '*.SPL' -Recurse -ErrorAction SilentlyContinue)
}
if ($jobFiles.Count -eq 0) {
    Write-Host "      No job files found - spool folder was already empty."
}
else {
    foreach ($file in $jobFiles) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Host "      Removed $($jobFiles.Count) job file(s)."
}

Write-Host "[3/3] Starting the Print Spooler service..."
Start-Service -Name Spooler
Write-Host "      Spooler started. New status: $((Get-Service -Name Spooler).Status)" -ForegroundColor Green

Show-QueueStatus

Write-Host "Done. Queues should now be empty. Ask users to resend any jobs"
Write-Host "that had not printed - cleared jobs are gone for good."
