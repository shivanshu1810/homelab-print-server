<#
.SYNOPSIS
    Reports the health of every print queue on this machine (report-only).

.DESCRIPTION
    Get-PrintQueueHealth.ps1 checks the two things a service desk tech
    looks at first when "printing is broken":

      1. The Print Spooler service - if it is stopped, nothing prints.
      2. Every print queue - its status, how many jobs it holds, and the
         details of any job that is stuck or in an error state.

    The output is a readable on-screen report. Queues or jobs with problems
    are flagged with [PROBLEM] so they stand out. A healthy print server
    shows: spooler Running, every queue Ready/Normal, and 0 stuck jobs.

    This script changes NOTHING. It never starts services, deletes jobs, or
    modifies queues. To fix a stuck queue, see Restart-PrintSpooler.ps1 and
    TROUBLESHOOTING.md.

.PARAMETER ComputerName
    Optional. The print server to check. Defaults to the local machine.
    Useful for checking the print server from an admin workstation, e.g.
    -ComputerName "print.lab.local". Requires PowerShell remoting / WMI
    access to the target (the printing cmdlets use CIM).

.EXAMPLE
    .\Get-PrintQueueHealth.ps1

    Shows spooler status and a health table for every local queue.

.EXAMPLE
    .\Get-PrintQueueHealth.ps1 -ComputerName "print.lab.local"

    Runs the same report against the print server named print.lab.local.

.NOTES
    Author : Homelab project (self-directed learning)
    Target : Windows PowerShell 5.1 on Windows Server 2022 / Windows 10/11 Pro
    Requires: The PrintManagement module (built into Pro / Server editions).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = $env:COMPUTERNAME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Job status values (from the PrintJobStatus enumeration) that mean a job
# needs attention. A job holding one of these flags at the top of a queue
# blocks every job behind it.
$problemJobFlags = @(
    'Error', 'Offline', 'PaperOut', 'Blocked', 'UserIntervention', 'Retained'
)

Write-Host ""
Write-Host "=== Print Queue Health Report ===" -ForegroundColor Cyan
Write-Host "Server : $ComputerName"
Write-Host "Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Print Spooler service status
# ---------------------------------------------------------------------------
Write-Host "--- Print Spooler Service ---" -ForegroundColor Yellow

try {
    $spooler = Get-Service -ComputerName $ComputerName -Name Spooler -ErrorAction Stop
    if ($spooler.Status -eq 'Running') {
        Write-Host "Spooler : Running (StartType: $($spooler.StartType))" -ForegroundColor Green
    }
    else {
        Write-Host "[PROBLEM] Spooler : $($spooler.Status) (StartType: $($spooler.StartType)) - nothing can print until this is Running." -ForegroundColor Red
    }
}
catch {
    Write-Host "[PROBLEM] Could not read the Spooler service on '$ComputerName': $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ---------------------------------------------------------------------------
# 2. Per-queue status, job counts, and stuck/error jobs
# ---------------------------------------------------------------------------
Write-Host "--- Queues ---" -ForegroundColor Yellow

$printers = @()
try {
    $printers = @(Get-Printer -ComputerName $ComputerName -ErrorAction Stop | Sort-Object -Property Name)
}
catch {
    Write-Host "[PROBLEM] Could not list printers on '$ComputerName': $($_.Exception.Message)" -ForegroundColor Red
    return
}

if ($printers.Count -eq 0) {
    Write-Host "No print queues found on this machine."
    return
}

$rows          = @()
$problemQueues = 0
$problemJobs   = 0

foreach ($printer in $printers) {
    # All jobs currently held by this queue
    $jobs = @(Get-PrintJob -ComputerName $ComputerName -PrinterName $printer.Name -ErrorAction SilentlyContinue)

    # Jobs whose status contains at least one problem flag
    $stuckJobs = @()
    foreach ($job in $jobs) {
        $statusText = "$($job.JobStatus)"
        foreach ($flag in $problemJobFlags) {
            if ($statusText -match $flag) {
                $stuckJobs += $job
                break
            }
        }
    }

    # A queue is unhealthy if Windows reports a non-Normal status or it
    # holds any stuck/error job.
    $queueProblem = ($printer.PrinterStatus -ne 'Normal') -or ($stuckJobs.Count -gt 0)
    if ($queueProblem) { $problemQueues++ }
    $problemJobs += $stuckJobs.Count

    $health = 'OK'
    if ($queueProblem) { $health = 'PROBLEM' }

    $rows += [PSCustomObject]@{
        Queue     = $printer.Name
        Shared    = $printer.Shared
        Status    = $printer.PrinterStatus
        Jobs      = $jobs.Count
        StuckJobs = $stuckJobs.Count
        Health    = $health
    }

    # Detail lines for the stuck jobs, so you can see exactly what is blocked
    foreach ($job in $stuckJobs) {
        Write-Host ("  [PROBLEM] Queue '{0}' - job {1} '{2}' from {3} is stuck: {4}" -f `
            $printer.Name, $job.ID, $job.DocumentName, $job.SubmittedBy, $job.JobStatus) -ForegroundColor Red
    }
}

$rows | Format-Table -AutoSize | Out-String | Write-Host

# ---------------------------------------------------------------------------
# 3. Summary
# ---------------------------------------------------------------------------
Write-Host "--- Summary ---" -ForegroundColor Yellow
Write-Host "Queues checked : $($printers.Count)"
Write-Host "Queues flagged : $problemQueues"
Write-Host "Stuck jobs     : $problemJobs"

if ($problemQueues -eq 0 -and $problemJobs -eq 0) {
    Write-Host "Result: HEALTHY - all queues normal, 0 stuck jobs." -ForegroundColor Green
}
else {
    Write-Host "Result: ATTENTION NEEDED - see [PROBLEM] lines above." -ForegroundColor Red
    Write-Host "Tip: a single stuck job at the top of a queue blocks everything behind it."
    Write-Host "     See TROUBLESHOOTING.md, or run Restart-PrintSpooler.ps1 to restart the spooler."
}
Write-Host ""
