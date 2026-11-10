# Exercise: The PC Health Report

Exercise code for the lesson **Exercise: The PC Health Report** in PowerShell in Depth on [ask-codey.com](https://www.ask-codey.com).

`HealthReport.psm1` makes a one-page health report for a Windows PC, as a web page: which Windows it runs and how long since it last restarted, how full each disk is, and every restart in the last 30 days with what it means. It runs, but the report isn't one you could hand to anyone yet. The disks come out as lines of bytes, the restarts have no meaning and show every event, the command reads the whole System log and lists USB sticks as if they were disks, and the page shows only one table, with no heading. Finish four jobs, answer three questions, and a Pester check tries your module with stand-in objects and tells you what's done.

This exercise is **Windows only**: it reads parts of Windows that a Mac or Linux doesn't have.

## What's here

- `HealthReport.psm1`: the report's commands. `ConvertTo-SystemReport` is ready to use and is the example for the others; four jobs are for you to finish.
- `answers.txt`: three questions, each with a numbered line for your answer. For you to finish.
- `Check.Tests.ps1`: the check. You don't need to change it.

## What to do

A `.psm1` file is a **module**: a script file of commands that `Import-Module` loads into your window. Open PowerShell 7 in this folder (the one with `answers.txt` in it), open the module in VS Code (`code .`) or with `edit .\HealthReport.psm1`, and try it as it is:

```powershell
Import-Module .\HealthReport.psm1 -Force
Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" | ConvertTo-DiskReport
Invoke-HealthReport -Path .\health-report.html
Invoke-Item .\health-report.html
```

The disk comes back as a sentence of bytes, `Invoke-HealthReport` takes a few seconds while it reads the whole System log, and the page in your browser has one table and no heading. Run `Import-Module .\HealthReport.psm1 -Force` again after every change you save: `-Force` loads the new version. Then, one job at a time:

1. **Disks in gigabytes.** In `ConvertTo-DiskReport`, hand back one `[PSCustomObject]` per disk with these properties, in this order: `Drive` (the disk's `DeviceID`), `SizeGB` and `FreeGB` (`Size` and `FreeSpace` divided by `1GB` and rounded to one decimal place with `[math]::Round(..., 1)`), `PercentFree` (`FreeSpace` divided by `Size`, times 100, rounded to a whole number), and `Status`: `Low` when `PercentFree` is under 15, and `OK` otherwise.
2. **Restarts in plain words.** In `ConvertTo-RestartReport`, hand back one `[PSCustomObject]` per restart event with `Date` (the day only: `$LogEvent.TimeCreated.ToString('yyyy-MM-dd')`), `Id` and `Meaning`, using the table below. Leave out any event whose ID isn't in the table. A hashtable of ID and meaning is a tidy way to do it, and `.ContainsKey()` says whether an ID is in it.
3. **Gather only what you need.** In `Invoke-HealthReport`, ask for the disks inside the PC only, with `-Filter 'DriveType=3'` (USB sticks are 2, DVD drives 5). Then read the restarts with `Get-WinEvent -FilterHashtable`, not `-LogName`: `LogName = 'System'`, `Id = 41, 1074, 6005, 6006, 6008` and `StartTime = (Get-Date).AddDays(-30)`. When nothing matches, Get-WinEvent says *No events were found*; add `-ErrorAction SilentlyContinue`, so a PC with no restarts still gets its report.
4. **One page, three parts.** In `New-HealthReport`, make the page from three tables, each with `ConvertTo-Html -Fragment -PreContent '<h2>…</h2>'` (`-Fragment` makes the table alone, not a whole page): `This PC` (from `$System`), `Disks` and `Restarts`, in that order, under the heading `<h1>PC Health Report</h1>`. Keep `-Head $head`, which gives the page its title and its colors. In the disks table, replace `<td>Low</td>` with `<td class="low">Low</td>` (`-replace` works on every line at once), so the style block colors it. When there are no restarts, write `<h2>Restarts</h2><p>No restarts in the last 30 days.</p>` instead of the table.

| ID | Meaning |
|---|---|
| 41 | Restarted without a clean shutdown: a crash or a power cut |
| 1074 | A person or a program asked for a restart or shutdown |
| 6005 | Windows started |
| 6006 | Windows shut down cleanly |
| 6008 | The shutdown before this start was unexpected |

Then answer the three questions in `answers.txt`, and save it.

## Check your work

The check needs Pester 5 or newer. Install it once, if you haven't already:

```powershell
Install-PSResource Pester
```

Then, from this folder:

```powershell
Invoke-Pester
```

At first most tests fail: that is expected. Each job you finish turns its tests green, and a failing test's message says what to look at. The tests never read your own PC: they hand your commands **stand-in objects**, made-up disks, events and Windows facts with the same property names as the real ones, and Pester's `Mock` stands in for `Get-CimInstance` and `Get-WinEvent`, so the check gives the same answer on every computer. Report files go in a throwaway folder that Pester makes and removes.

If PowerShell says the check *cannot be loaded* because it *is not digitally signed*, or because *running scripts is disabled*, the folder came from a download that Windows marked as from the internet. Unblock its files once with `Get-ChildItem -Recurse | Unblock-File`, from this folder, and run `Invoke-Pester` again.

## The rules

- Keep the file's name, `HealthReport.psm1`, and the commands' names and parameters.
- `ConvertTo-DiskReport` and `ConvertTo-RestartReport` hand back objects, not text.
- The report reads only: nothing in this module changes your PC.
- Write each answer on its numbered line, after the `)`, like the example: `0) Get-CimInstance`.

## Tips

- `Size` and `FreeSpace` are in bytes. `1GB` is PowerShell's own number for a gigabyte.
- A disk with 15 percent free isn't under 15, so it's `OK`.
- `ConvertTo-SystemReport` shows the shape: `process { }` runs once for each object that comes down the pipe.
- `-PostContent` puts more HTML after a table, so one `ConvertTo-Html -Head $head` call can carry the other two tables.
- To see your page, run `Invoke-HealthReport -Path .\health-report.html`, then `Invoke-Item .\health-report.html`.

## Hand it in

When it works, push your solution to a public repo of your own on GitHub, then paste that repo's address into **Submit your exercise** on the lesson page at [ask-codey.com](https://www.ask-codey.com). That's what completes the lesson. The lesson page shows the Git commands, step by step. The report you make is about your own PC, and `.gitignore` keeps `health-report.html` out of your repo.
