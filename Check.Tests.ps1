# Checks HealthReport.psm1 and your answers, one test per job and per question in README.md.
# The tests never read your own PC: they hand the module stand-in objects shaped like the real
# ones (a disk, an event, Windows' facts), and they stand in for Get-CimInstance and Get-WinEvent
# with Pester's Mock. Report files go in a throwaway folder that Pester makes and removes (TestDrive).
# Run it from this folder with: Invoke-Pester
# You don't need to change this file.

BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot 'HealthReport.psm1'
    Import-Module $modulePath -Force

    # Stand-ins: objects with the same property names as the real ones.
    function New-StandInDisk([string]$Drive, [int]$Type, $SizeGB, $FreeGB) {
        $size = $null; $free = $null
        if ($null -ne $SizeGB) { $size = [uint64]($SizeGB * 1GB) }
        if ($null -ne $FreeGB) { $free = [uint64]($FreeGB * 1GB) }
        [pscustomobject]@{ DeviceID = $Drive; DriveType = $Type; Size = $size; FreeSpace = $free }
    }

    function New-StandInEvent([int]$Id, [datetime]$When, [string]$Provider = 'EventLog') {
        [pscustomobject]@{ Id = $Id; TimeCreated = $When; ProviderName = $Provider; LevelDisplayName = 'Information' }
    }

    function New-StandInWindows {
        [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; BuildNumber = '26200'; LastBootUpTime = (Get-Date).AddDays(-3).AddHours(-2) }
    }

    # Four drives: two disks inside the PC, a USB stick and an empty DVD drive.
    function Get-StandInDrives {
        New-StandInDisk 'C:' 3 512 50
        New-StandInDisk 'D:' 3 1024 600
        New-StandInDisk 'E:' 2 64 10
        New-StandInDisk 'F:' 5 $null $null
    }

    function Get-StandInRestarts {
        New-StandInEvent 6005 ([datetime]'2026-11-03 08:11:05')
        New-StandInEvent 6006 ([datetime]'2026-11-03 08:10:40')
        New-StandInEvent 1074 ([datetime]'2026-11-03 08:10:31') 'User32'
        New-StandInEvent 7036 ([datetime]'2026-11-02 19:45:00') 'Service Control Manager'
        New-StandInEvent 6008 ([datetime]'2026-10-20 06:02:15')
        New-StandInEvent 41 ([datetime]'2026-10-20 06:02:10') 'Microsoft-Windows-Kernel-Power'
    }

    # The answers in answers.txt: the text after "N)", with runs of spaces made single.
    $script:answers = @{}
    foreach ($line in Get-Content (Join-Path $PSScriptRoot 'answers.txt')) {
        if ($line -match '^\s*(\d+)\)\s*(.*)$') {
            $script:answers[[int]$Matches[1]] = ($Matches[2].Trim() -replace '\s+', ' ')
        }
    }
}

Describe 'Exercise: The PC Health Report' {

    It 'HealthReport.psm1 is here and loads' {
        Test-Path -LiteralPath $modulePath -PathType Leaf | Should -BeTrue -Because 'the module lives in HealthReport.psm1, in this folder. Did it get moved or renamed?'
        Get-Command ConvertTo-SystemReport, ConvertTo-DiskReport, ConvertTo-RestartReport, New-HealthReport, Invoke-HealthReport -ErrorAction SilentlyContinue |
            Should -HaveCount 5 -Because 'the module should load with Import-Module and give you its five commands'
    }

    It '1) a disk becomes an object with Drive, SizeGB, FreeGB, PercentFree and Status' {
        $report = New-StandInDisk 'D:' 3 1024 600 | ConvertTo-DiskReport
        $report | Should -HaveCount 1 -Because 'one disk in should give one object out'
        $report | Should -Not -BeOfType [string] -Because 'each disk should be an object made with [PSCustomObject]@{ }, not a line of text'
        @($report.PSObject.Properties.Name) | Should -Be @('Drive', 'SizeGB', 'FreeGB', 'PercentFree', 'Status') -Because 'the object should have these five properties, in this order'
        $report.Drive | Should -Be 'D:' -Because 'Drive is the disk''s DeviceID'
    }

    It '1) sizes are in gigabytes, rounded to one decimal place, and the percent free is a whole number' {
        $report = New-StandInDisk 'D:' 3 1024 600 | ConvertTo-DiskReport
        $report.SizeGB | Should -Be 1024 -Because 'Size is in bytes: divide by 1GB and round to one decimal place'
        $report.FreeGB | Should -Be 600 -Because 'FreeSpace is in bytes: divide by 1GB and round to one decimal place'
        $report.PercentFree | Should -Be 59 -Because '600 GB free of 1024 GB is 58.6 percent, which rounds to 59'
        $small = New-StandInDisk 'E:' 3 256 38.4 | ConvertTo-DiskReport
        $small.FreeGB | Should -Be 38.4 -Because '[math]::Round(..., 1) keeps one decimal place'
    }

    It '1) a disk under 15 percent free is Low, and the others are OK' {
        $reports = @(Get-StandInDrives | Select-Object -First 2 | ConvertTo-DiskReport)
        $reports | Should -HaveCount 2 -Because 'two disks in should give two objects out'
        $reports[0].PercentFree | Should -Be 10 -Because '50 GB free of 512 GB is about 10 percent'
        $reports[0].Status | Should -Be 'Low' -Because 'a disk under 15 percent free should say Low'
        $reports[1].Status | Should -Be 'OK' -Because 'a disk with 59 percent free should say OK'
        (New-StandInDisk 'E:' 3 256 38.4 | ConvertTo-DiskReport).Status | Should -Be 'OK' -Because 'exactly 15 percent free isn''t under 15, so it''s still OK'
    }

    It '2) a restart event becomes an object with Date, Id and Meaning' {
        $report = New-StandInEvent 6006 ([datetime]'2026-11-03 08:10:40') | ConvertTo-RestartReport
        $report | Should -HaveCount 1 -Because 'one restart event in should give one object out'
        @($report.PSObject.Properties.Name) | Should -Be @('Date', 'Id', 'Meaning') -Because 'the object should have these three properties, in this order'
        $report.Date | Should -Be '2026-11-03' -Because 'Date should be the day only, written as yyyy-MM-dd, with no time of day: $LogEvent.TimeCreated.ToString(''yyyy-MM-dd'')'
        $report.Id | Should -Be 6006 -Because 'Id is the event''s ID'
    }

    It '2) each restart ID gets its meaning in plain words' {
        $reports = @(Get-StandInRestarts | ConvertTo-RestartReport)
        $byId = @{}
        foreach ($r in $reports) { $byId[[int]$r.Id] = "$($r.Meaning)" }
        $byId[6005] | Should -Match 'start' -Because '6005 means Windows started'
        $byId[6006] | Should -Match 'clean' -Because '6006 means Windows shut down cleanly'
        $byId[1074] | Should -Match 'asked' -Because '1074 means a person or a program asked for a restart or shutdown'
        $byId[6008] | Should -Match 'unexpected' -Because '6008 means the shutdown before this start was unexpected'
        $byId[41] | Should -Match 'crash' -Because '41 means Windows restarted without a clean shutdown: a crash or a power cut'
        $byId[41] | Should -Match 'power' -Because '41 means Windows restarted without a clean shutdown: a crash or a power cut'
    }

    It '2) any other event is left out, and the order stays the same' {
        $reports = @(Get-StandInRestarts | ConvertTo-RestartReport)
        @($reports | ForEach-Object { [int]$_.Id }) | Should -Be @(6005, 6006, 1074, 6008, 41) -Because 'event 7036 isn''t a restart event, so the report should leave it out, and keep the others in the order they came'
    }

    Context 'Job 3: gathering the facts' -Skip:(-not $IsWindows) {

        BeforeEach {
            Mock -ModuleName HealthReport Get-CimInstance {
                $what = "$ClassName $Query"
                if ($what -match 'Win32_OperatingSystem') { return New-StandInWindows }
                $drives = Get-StandInDrives
                if ("$Filter $Query" -match 'DriveType\s*=\s*3') { $drives = $drives | Where-Object DriveType -eq 3 }
                $drives
            }
            Mock -ModuleName HealthReport Get-WinEvent { Get-StandInRestarts }
            Mock -ModuleName HealthReport New-HealthReport { }
            $script:reportPath = Join-Path $TestDrive 'health-report.html'
        }

        It '3) reads the restart events with -FilterHashtable: the System log and the five IDs' {
            Invoke-HealthReport -Path $reportPath
            Should -Invoke Get-WinEvent -ModuleName HealthReport -Times 1 -Exactly -ParameterFilter { $null -ne $FilterHashtable } -Because 'Invoke-HealthReport should ask the log for only the restart events, with Get-WinEvent -FilterHashtable, once'
            Should -Invoke Get-WinEvent -ModuleName HealthReport -Times 0 -Exactly -ParameterFilter { $null -ne $LogName } -Because 'Get-WinEvent -LogName System reads the whole log, tens of thousands of events. -FilterHashtable asks for only the ones you want'
            Should -Invoke Get-WinEvent -ModuleName HealthReport -Times 1 -Exactly -ParameterFilter {
                $h = $FilterHashtable[0]
                (@($h.LogName) -contains 'System') -and ((@($h.Id | ForEach-Object { [int]$_ }) | Sort-Object) -join ',') -eq '41,1074,6005,6006,6008'
            } -Because 'the filter should name LogName = ''System'' and Id = 41, 1074, 6005, 6006, 6008'
        }

        It '3) asks only for the last 30 days, with StartTime' {
            Invoke-HealthReport -Path $reportPath
            Should -Invoke Get-WinEvent -ModuleName HealthReport -Times 1 -Exactly -ParameterFilter {
                $start = $FilterHashtable[0].StartTime
                ($start -is [datetime]) -and ($start -gt (Get-Date).AddDays(-31)) -and ($start -lt (Get-Date).AddDays(-29))
            } -Because 'the filter should have StartTime = (Get-Date).AddDays(-30), so the report shows the last 30 days'
        }

        It '3) reports only the disks inside the PC (DriveType 3)' {
            Invoke-HealthReport -Path $reportPath
            Should -Invoke New-HealthReport -ModuleName HealthReport -Times 1 -Exactly -Because 'Invoke-HealthReport should hand everything to New-HealthReport once'
            Should -Invoke New-HealthReport -ModuleName HealthReport -Times 1 -Exactly -ParameterFilter {
                (@($Disks | ForEach-Object { $_.Drive }) -join ',') -eq 'C:,D:'
            } -Because 'the report should list C: and D:, the disks inside the PC, and leave out the USB stick (DriveType 2) and the empty DVD drive (DriveType 5). Ask for -Filter ''DriveType=3''. (This test also needs job 1: each disk''s Drive property.)'
        }

        It '3) hands the restarts on, and the path you gave' {
            Invoke-HealthReport -Path $reportPath
            Should -Invoke New-HealthReport -ModuleName HealthReport -Times 1 -Exactly -ParameterFilter {
                (@($Restarts).Count -eq 5) -and (@($Restarts | Where-Object Meaning).Count -eq 5) -and ($Path -eq $reportPath)
            } -Because 'New-HealthReport should get the five restart events, each made into a Date, an Id and a Meaning by ConvertTo-RestartReport, and the -Path you gave Invoke-HealthReport. (This test also needs job 2.)'
        }

        It '3) no restart events is a normal answer, not an error' {
            # Stands in for Get-WinEvent when nothing matches: it says No events were found,
            # unless it was told to keep quiet (-ErrorAction SilentlyContinue) or to stop (-ErrorAction Stop, for a try/catch).
            $script:errorShown = $false
            Mock -ModuleName HealthReport Get-WinEvent {
                $action = "$($PesterBoundParameters['ErrorAction'])"
                if ($action -in 'SilentlyContinue', 'Ignore') { return }
                if ($action -eq 'Stop') { throw 'No events were found that match the specified selection criteria.' }
                $script:errorShown = $true
            }
            { Invoke-HealthReport -Path $reportPath } | Should -Not -Throw -Because 'a PC with no restarts should still get a report'
            $script:errorShown | Should -BeFalse -Because 'when no event matches, Get-WinEvent says No events were found, in red. Add -ErrorAction SilentlyContinue to Get-WinEvent, so a PC with no restarts gets a report, not an error'
            Should -Invoke New-HealthReport -ModuleName HealthReport -Times 1 -Exactly -ParameterFilter { @($Restarts).Count -eq 0 } -Because 'with no restart events, New-HealthReport should still be called, with no restarts'
        }
    }

    It '4) the report is one web page with a title, a heading and the three parts' {
        $path = Join-Path $TestDrive 'page.html'
        $system = New-StandInWindows | ConvertTo-SystemReport
        $disks = @([pscustomobject]@{ Drive = 'C:'; SizeGB = 512; FreeGB = 50; PercentFree = 10; Status = 'Low' }, [pscustomobject]@{ Drive = 'D:'; SizeGB = 1024; FreeGB = 600; PercentFree = 59; Status = 'OK' })
        $restarts = @([pscustomobject]@{ Date = '2026-11-03'; Id = 6005; Meaning = 'Windows started' })
        $null = New-HealthReport -System $system -Disks $disks -Restarts $restarts -Path $path
        Test-Path -LiteralPath $path | Should -BeTrue -Because 'New-HealthReport should save the page at the -Path it was given'
        $page = Get-Content -LiteralPath $path -Raw
        $page | Should -Match '<title>PC Health Report</title>' -Because 'the browser tab should say PC Health Report: the $head already has the title, so pass it with -Head'
        $page | Should -Match '<h1>PC Health Report</h1>' -Because 'the page should start with the heading <h1>PC Health Report</h1>'
        $page | Should -Match '(?s)<h2>This PC</h2>.*<h2>Disks</h2>.*<h2>Restarts</h2>' -Because 'the page should have the three headings <h2>This PC</h2>, <h2>Disks</h2> and <h2>Restarts</h2>, in that order'
        $page | Should -Match '<td>Microsoft Windows 11 Pro</td>' -Because 'the This PC table should show Windows'' name'
        $page | Should -Match '<td>C:</td>' -Because 'the Disks table should show each drive'
        $page | Should -Match '<td>D:</td>' -Because 'the Disks table should show each drive'
        $page | Should -Match '<td>Windows started</td>' -Because 'the Restarts table should show each restart''s meaning'
        ([regex]::Matches($page, '<table>')).Count | Should -BeGreaterOrEqual 3 -Because 'each part should be a table: one for the PC, one for the disks and one for the restarts'
    }

    It '4) a Low disk is marked so the page shows it in red' {
        $path = Join-Path $TestDrive 'low.html'
        $system = New-StandInWindows | ConvertTo-SystemReport
        $disks = @([pscustomobject]@{ Drive = 'C:'; SizeGB = 512; FreeGB = 50; PercentFree = 10; Status = 'Low' }, [pscustomobject]@{ Drive = 'D:'; SizeGB = 1024; FreeGB = 600; PercentFree = 59; Status = 'OK' })
        $null = New-HealthReport -System $system -Disks $disks -Restarts @() -Path $path
        $page = Get-Content -LiteralPath $path -Raw
        ([regex]::Matches($page, '<td class="low">Low</td>')).Count | Should -Be 1 -Because 'the Low cell should read <td class="low">Low</td>, so the .low rule in the style block colors it. Use -replace on the disks table'
        $page | Should -Match '<td>OK</td>' -Because 'the OK disk keeps a plain cell'
    }

    It '4) with no restarts, the Restarts heading is still there, with a line that says so' {
        $path = Join-Path $TestDrive 'none.html'
        $system = New-StandInWindows | ConvertTo-SystemReport
        $disks = @([pscustomobject]@{ Drive = 'D:'; SizeGB = 1024; FreeGB = 600; PercentFree = 59; Status = 'OK' })
        $null = New-HealthReport -System $system -Disks $disks -Restarts @() -Path $path
        $page = Get-Content -LiteralPath $path -Raw
        $page | Should -Match '<h2>Restarts</h2>' -Because 'the Restarts heading should be there even when there were none'
        $page | Should -Match 'No restarts in the last 30 days' -Because 'with no restarts, the page should say No restarts in the last 30 days.'
    }

    It 'answer 1) the drive that holds your own settings' {
        $answers[1] | Should -Not -BeNullOrEmpty -Because 'question 1 has no answer yet'
        $answers[1] | Should -Match '^(HKCU:?|HKEY_CURRENT_USER)\\?$' -Because 'HKCU:, HKEY_CURRENT_USER, holds the settings of the person who is signed in'
    }

    It 'answer 2) the command that lists a group''s members' {
        $answers[2] | Should -Not -BeNullOrEmpty -Because 'question 2 has no answer yet'
        $answers[2] | Should -Match '^Get-LocalGroupMember\b' -Because 'Get-LocalGroupMember -Group Administrators lists who is in the Administrators group'
    }

    It 'answer 3) the winget command that installs a whole list' {
        $answers[3] | Should -Not -BeNullOrEmpty -Because 'question 3 has no answer yet'
        $answers[3] | Should -Match '^winget import\b' -Because 'winget import --import-file apps.json installs every app on the list'
    }
}
