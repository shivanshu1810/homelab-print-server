<#
.SYNOPSIS
    Sets up one shared print queue on a Windows print server (homelab).

.DESCRIPTION
    Install-PrintServer.ps1 performs the core print-server setup steps in
    order, skipping anything that already exists so it is safe to re-run:

      1. Installs the Print-Services feature (Windows Server editions only).
         On client Windows (10/11) it warns and continues, because printing
         support is built in there.
      2. Creates a Standard TCP/IP printer port (RAW, port 9100) if missing.
      3. Adds the printer queue using the named driver.
      4. Shares the printer with the given share name.

    Nothing is removed or overwritten. If a port, printer, or share already
    exists, the script reports it and moves on.

    Run it from an elevated (Run as administrator) Windows PowerShell 5.1
    prompt on the print server. The driver named by -DriverName must already
    be installed on the server (see BUILD-GUIDE.md, Step 4) - Windows can
    only create a queue with a driver that exists.

.PARAMETER PrinterName
    Display name of the print queue, e.g. "HP-Lab".

.PARAMETER PrinterIP
    IP address of the physical network printer, e.g. "192.168.1.50".
    Give the printer a static IP or DHCP reservation first.

.PARAMETER DriverName
    Exact name of the installed printer driver, as shown under Drivers in
    Print Management, e.g. "HP Universal Printing PCL 6".

.PARAMETER ShareName
    Share name clients use to connect, e.g. "HP-Lab".
    Clients connect with \\<ServerName>\<ShareName>.
    Keep it short and avoid spaces.

.EXAMPLE
    .\Install-PrintServer.ps1 -PrinterName "HP-Lab" -PrinterIP "192.168.1.50" `
        -DriverName "HP Universal Printing PCL 6" -ShareName "HP-Lab"

    Creates port IP_192.168.1.50 (RAW 9100), adds the HP-Lab queue with the
    named driver, and shares it as \\<server>\HP-Lab.

.NOTES
    Author : Homelab project (self-directed learning)
    Target : Windows PowerShell 5.1 on Windows Server 2022 / Windows 10/11 Pro
    Requires: Administrator rights.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PrinterName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
    [string]$PrinterIP,

    [Parameter(Mandatory = $true)]
    [string]$DriverName,

    [Parameter(Mandatory = $true)]
    [string]$ShareName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
Write-Host "=== Print Server Setup ===" -ForegroundColor Cyan
Write-Host "Printer : $PrinterName"
Write-Host "IP      : $PrinterIP"
Write-Host "Driver  : $DriverName"
Write-Host "Share   : \\$env:COMPUTERNAME\$ShareName"
Write-Host ""

# ---------------------------------------------------------------------------
# Step 1: Install the Print-Services feature (Server editions only)
# ---------------------------------------------------------------------------
Write-Host "[1/4] Checking print components..." -ForegroundColor Yellow

$os = Get-CimInstance -ClassName Win32_OperatingSystem
# ProductType: 1 = client Windows, 2 = domain controller, 3 = server
if ($os.ProductType -ne 1) {
    $feature = Get-WindowsFeature -Name Print-Services -ErrorAction SilentlyContinue
    if ($null -ne $feature) {
        if ($feature.Installed) {
            Write-Host "      Print-Services feature is already installed. Skipping."
        }
        else {
            Write-Host "      Installing Print-Services feature..."
            Install-WindowsFeature -Name Print-Services -IncludeManagementTools | Out-Null
            Write-Host "      Print-Services feature installed."
        }
    }
    else {
        Write-Warning "      Could not query the Print-Services feature on this edition. Continuing - printing cmdlets will be checked below."
    }
}
else {
    Write-Warning "      This is a client edition of Windows (10/11). The Print-Services server role does not apply here; built-in printing support will be used. Continuing."
}

# The printing cmdlets (Add-PrinterPort, Add-Printer, ...) ship with the
# PrintManagement module. Confirm it is available before going further.
if (-not (Get-Command -Name Add-Printer -ErrorAction SilentlyContinue)) {
    Write-Warning "The PrintManagement PowerShell module is not available on this machine, so the queue cannot be created."
    Write-Warning "On Windows Server, install Print and Document Services. On Windows 10/11 Pro, the module is included - try a fresh elevated prompt."
    return
}

# Make sure the spooler is up - nothing print-related works without it.
$spooler = Get-Service -Name Spooler
if ($spooler.Status -ne 'Running') {
    Write-Host "      Print Spooler is $($spooler.Status). Starting it..."
    Start-Service -Name Spooler
}
Write-Host "      Print Spooler is running."

# ---------------------------------------------------------------------------
# Step 2: Create the TCP/IP printer port (RAW, port 9100) if missing
# ---------------------------------------------------------------------------
Write-Host "[2/4] Checking printer port..." -ForegroundColor Yellow

$portName = "IP_$PrinterIP"
$existingPort = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue

if ($null -ne $existingPort) {
    Write-Host "      Port '$portName' already exists. Skipping."
}
else {
    Write-Host "      Creating Standard TCP/IP port '$portName' (RAW, port 9100, SNMP off)..."
    Add-PrinterPort -Name $portName -PrinterHostAddress $PrinterIP -PortNumber 9100 -SNMPEnabled:$false
    Write-Host "      Port created."
}

# ---------------------------------------------------------------------------
# Step 3: Add the printer queue if missing
# ---------------------------------------------------------------------------
Write-Host "[3/4] Checking print queue..." -ForegroundColor Yellow

# The named driver must already be installed - fail early with a clear
# message instead of a confusing Add-Printer error.
$driver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
if ($null -eq $driver) {
    Write-Warning "Driver '$DriverName' is not installed on this server."
    Write-Warning "Install it first (Print Management > Drivers > Add Driver, or the vendor installer), then re-run this script."
    return
}

$existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($null -ne $existingPrinter) {
    Write-Host "      Printer '$PrinterName' already exists. Skipping queue creation."
}
else {
    Write-Host "      Adding printer '$PrinterName' on port '$portName' with driver '$DriverName'..."
    Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $portName
    Write-Host "      Printer added."
}

# ---------------------------------------------------------------------------
# Step 4: Share the printer if it is not already shared with this name
# ---------------------------------------------------------------------------
Write-Host "[4/4] Checking sharing..." -ForegroundColor Yellow

$printer = Get-Printer -Name $PrinterName
if ($printer.Shared -and $printer.ShareName -eq $ShareName) {
    Write-Host "      '$PrinterName' is already shared as '$ShareName'. Skipping."
}
elseif ($printer.Shared -and $printer.ShareName -ne $ShareName) {
    Write-Warning "      '$PrinterName' is already shared, but as '$($printer.ShareName)' instead of '$ShareName'. Leaving the existing share unchanged."
}
else {
    Write-Host "      Sharing '$PrinterName' as '$ShareName'..."
    Set-Printer -Name $PrinterName -Shared $true -ShareName $ShareName
    Write-Host "      Printer shared."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$final = Get-Printer -Name $PrinterName
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Queue   : $($final.Name)"
Write-Host "Port    : $($final.PortName)"
Write-Host "Driver  : $($final.DriverName)"
Write-Host "Status  : $($final.PrinterStatus)"
if ($final.Shared) {
    Write-Host "Connect : \\$env:COMPUTERNAME\$($final.ShareName)"
}
Write-Host ""
Write-Host "Next steps: set printing defaults (Letter, duplex) in Print Management,"
Write-Host "print a test page, then run Get-PrintQueueHealth.ps1 to verify the queue."
