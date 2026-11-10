# HealthReport.psm1: a one-page health report for a Windows PC, as a web page.
# Load it with: Import-Module .\HealthReport.psm1 -Force
# (-Force loads it again after you change this file.)
# Then make the report with: Invoke-HealthReport -Path .\health-report.html

# Turns Windows' own facts (a Win32_OperatingSystem object) into one line for the report.
# Ready to use: it's the example for the other two.
function ConvertTo-SystemReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $OperatingSystem
    )
    process {
        $uptime = (Get-Date) - $OperatingSystem.LastBootUpTime
        [PSCustomObject]@{
            Windows    = $OperatingSystem.Caption
            Build      = $OperatingSystem.BuildNumber
            LastBoot   = $OperatingSystem.LastBootUpTime.ToString('yyyy-MM-dd')
            UptimeDays = $uptime.Days
        }
    }
}

# Job 1: turns each disk (a Win32_LogicalDisk object) into gigabytes and a percent free.
# Right now it hands back a line of text, in bytes.
function ConvertTo-DiskReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $Disk
    )
    process {
        "$($Disk.DeviceID) $($Disk.FreeSpace) of $($Disk.Size) bytes free"
    }
}

# Job 2: turns each restart event into a date, its ID and what it means.
# Right now it passes on every event, with the time of day and no meaning.
function ConvertTo-RestartReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $LogEvent
    )
    process {
        [PSCustomObject]@{
            Date = $LogEvent.TimeCreated
            Id   = $LogEvent.Id
        }
    }
}

# Job 4: builds the web page from the three parts and saves it.
# Right now the page has only the disks, with no heading.
function New-HealthReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $System,
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Disks,
        [AllowEmptyCollection()] $Restarts = @(),
        [Parameter(Mandatory)] [string] $Path
    )
    $head = @'
<title>PC Health Report</title>
<style>
  body { font-family: sans-serif; margin: 2em; }
  table { border-collapse: collapse; margin-bottom: 1.5em; }
  th, td { border: 1px solid #999; padding: 4px 12px; text-align: left; }
  th { background: #1971c2; color: white; }
  .low { background: #ffc9c9; font-weight: bold; }
</style>
'@
    $Disks | ConvertTo-Html -Head $head | Set-Content -Path $Path
    Get-Item -Path $Path
}

# Job 3: gathers this PC's facts, disks and restarts, and writes the report.
# Right now it lists every drive, USB sticks and DVD drives too, and reads the whole System log.
function Invoke-HealthReport {
    [CmdletBinding()]
    param(
        [string] $Path = (Join-Path (Get-Location) 'health-report.html')
    )
    $system = Get-CimInstance -ClassName Win32_OperatingSystem | ConvertTo-SystemReport
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk | ConvertTo-DiskReport
    $restarts = Get-WinEvent -LogName System | Where-Object { $_.Id -in 41, 1074, 6005, 6006, 6008 } | ConvertTo-RestartReport
    New-HealthReport -System $system -Disks @($disks) -Restarts @($restarts) -Path $Path
}

Export-ModuleMember -Function ConvertTo-SystemReport, ConvertTo-DiskReport, ConvertTo-RestartReport, New-HealthReport, Invoke-HealthReport
