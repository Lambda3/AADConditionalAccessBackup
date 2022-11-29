#Requires -PSEdition Core
#Requires -Modules Microsoft.Graph.Identity.SignIns

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([switch]$NonInteractive, [DateTime]$Date, [switch]$Update, [switch]$Disable, [switch]$Force)

Set-StrictMode -Version 3.0

$ErrorActionPreference = 'Stop'
if (!(Test-Path variable:\Confirm)) {
    $Confirm = $false
}
if ($Force -and -not $Confirm) {
    $ConfirmPreference = 'None'
}

$IsWin = [System.PlatformID]::Win32NT, [System.PlatformID]::Win32S, [System.PlatformID]::Win32Windows, [System.PlatformID]::Win32Windows, [System.PlatformID]::WinCE, [System.PlatformID]::Xbox -contains [System.Environment]::OSVersion.Platform
if (!$IsWin) {
    Write-Error "This script is only for Windows."
}

function DeleteNullKeys([hashtable]$ht) {
    $keysToRemove = $ht.Keys | Where-Object { $null -eq $ht[$_] }
    $keysToRemove | ForEach-Object { $ht.Remove($_) }
    $ht.Keys | ForEach-Object {
        if ('System.Collections.Hashtable', 'System.Management.Automation.OrderedHashtable', 'System.Collections.Specialized.OrderedDictionary' -contains $ht[$_].GetType().FullName) {
            DeleteNullKeys $ht[$_]
        }
    }
}

$dataDir = "$PSScriptRoot\data"
if (!(Test-Path "$dataDir")) {
    Write-Host "No backups available."
    exit
}
$dateDirs = Get-ChildItem $dataDir
if ($dateDirs.Length -eq 0) {
    Write-Host "No backups available."
    exit
}

Write-Verbose "Checking if connected to Microsoft Graph..."
$mgContext = Get-MgContext
if (!$mgContext -or ($mgContext.Scopes -notcontains 'Policy.Read.All') `
        -or ($mgContext.Scopes -notcontains 'Application.Read.All') `
        -or ($mgContext.Scopes -notcontains 'Policy.ReadWrite.ConditionalAccess')) {
    Connect-MgGraph -Scopes 'Application.Read.All', 'Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess'
}

if ($PSBoundParameters.ContainsKey('Date')) {
    $selectedDate = $Date
} else {
    $dates = $dateDirs | Where-Object { $_.Name -match '\d{8}' } | ForEach-Object { Get-Date -Month $_.Name.Substring(4, 2) -Day $_.Name.Substring(6, 2) -Year $_.Name.Substring(0, 4) } | Sort-Object | Get-Unique -AsString
    $selectedDate = $null
    switch ($dates.Length) {
        0 {
            Write-Host "No backups available."
            break
        }
        { $_ -lt 10 } {
            while ($true) {
                Write-Host "Backup dates:"
                $i = 0
                $dates | ForEach-Object {
                    $i++
                    $dateString = Get-Date $_ -Format dd/MMM/yyyy
                    Write-Host "[$i] $datestring"
                }
                Write-Host -NoNewline "Choose the date (press enter to exit): "
                $choiceString = (Read-Host).Trim()
                if ($choiceString -eq '') { break }
                if ($choiceString -match "^[\d]+$") {
                    [int]$choice = $choiceString
                    if ($choice -le $dates.Length -and $choice -gt 0) {
                        $selectedDate = $dates[$choice - 1]
                        break
                    } else { Write-Host "Please choose a number between the supplied ones." }
                } else { Write-Host "Please write a number." }
            }
        }
        default {
            [array]$groups = $dates | Group-Object -Property { Get-Date $_ -Format MM/yyyy } | Sort-Object { Get-Date $_.Name }
            if ($groups.Length -eq 1) {
                $selectedGroup = $groups[0]
            } else {
                Write-Host "Backup months:"
                $selectedGroup = $null
                while ($true) {
                    $i = 0
                    $groups | ForEach-Object {
                        $i++
                        Write-Host "[$i] $($_.Name) ($($_.Count) backups)"
                    }
                    Write-Host -NoNewline "Choose the month (press enter to exit): "
                    $choiceString = (Read-Host).Trim()
                    if ($choiceString -eq '') { break }
                    if ($choiceString -match "^\d+$") {
                        [int]$choice = $choiceString
                        if ($choice -le $groups.Length -and $choice -gt 0) {
                            $selectedGroup = $groups[$choice - 1]
                            break
                        } else { Write-Host "Please choose a number between the supplied ones." }
                    } else { Write-Host "Please write a number." }
                }
            }
            if ($selectedGroup) {
                while ($true) {
                    Write-Host "Backup dates:"
                    $i = 0
                    $selectedGroup.Group | ForEach-Object {
                        $i++
                        $dateString = Get-Date $_ -Format dd/MMM/yyyy
                        Write-Host "[$i] $dateString"
                    }
                    Write-Host -NoNewline "Choose the date (press enter to exit): "
                    $choiceString = (Read-Host).Trim()
                    if ($choiceString -eq '') { break }
                    if ($choiceString -match "^[\d]+$") {
                        [int]$choice = $choiceString
                        if ($choice -le $selectedGroup.Group.Count -and $choice -gt 0) {
                            $selectedDate = $selectedGroup.Group[$choice - 1]
                            break
                        } else { Write-Host "Please choose a number between the supplied ones." }
                    } else { Write-Host "Please write a number." }
                }
            }
        }
    }
}
if (!($selectedDate)) {
    Write-Host "Exiting without restoring."
    exit
}

Write-Host "Selected date: $(Get-Date $selectedDate -Format dd/MMM/yyyy)"
$dateString = Get-Date $selectedDate -Format yyyyMMdd
$backupDir = "$dataDir\$dateString"
if (!(Test-Path $backupDir)) {
    Write-Host "Backup for date '$(Get-Date $selectedDate -Format dd/MMM/yyyy)' not found."
    exit 1
}

$backupFiles = Get-ChildItem $backupDir -File
if ($VerbosePreference -eq 'Continue') {
    Write-Verbose "Backup files:"
    $backupFiles | Format-Table
}

foreach ($backupFile in $backupFiles) {
    Write-Verbose "Working on $($backupFile.FullName)..."
    $policy = Get-Content -LiteralPath $backupFile.FullName | ConvertFrom-Json -Depth 100 -AsHashtable
    if ($Disable) {
        $policy['State'] = 'disabled'
    }
    if ($Update) {
        Write-Verbose "Searching for existing policy id '$($policy.Id)'..."
        $currentPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "Id eq '$($policy.Id)'"
        if ($currentPolicy) {
            Write-Verbose "Found policy."
            if ($policy.CreatedDateTime) {
                $policy.Remove('CreatedDateTime')
            }
            if ($policy.ModifiedDateTime) {
                $policy.Remove('ModifiedDateTime')
            }
            DeleteNullKeys $policy
            Write-Verbose "Policy details:"
            if ($VerbosePreference -eq 'Continue') {
                $policy | ConvertTo-Json -Depth 100
            }
            if ($PSCmdlet.ShouldProcess($policy.DisplayName, "Update policy")) {
                Write-Verbose "Updating policy..."
                Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id -BodyParameter $policy -ErrorAction Stop
                Write-Verbose "Policy updated."
            } else {
                Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policy.Id -BodyParameter $policy -ErrorAction Stop -WhatIf
            }
        } else {
            Write-Warning "Policy id $($policy.Id) ($($policy.DisplayName)) not found. Skipping."
        }
    } else {
        [array]$policiesWithSameName = Get-MgIdentityConditionalAccessPolicy -Filter "startsWith(DisplayName, '$($policy.DisplayName)')"
        if ($policiesWithSameName) {
            $policy['DisplayName'] = "$($policy.DisplayName) ($($policiesWithSameName.Length))"
            Write-Verbose "Changing policy name to '$($policy.DisplayName)' and setting its state to disabled..."
            $policy['State'] = 'disabled'
        }
        if ($policy.Id) {
            $policy.Remove('Id')
        }
        if ($policy.CreatedDateTime) {
            $policy.Remove('CreatedDateTime')
        }
        if ($policy.ModifiedDateTime) {
            $policy.Remove('ModifiedDateTime')
        }
        DeleteNullKeys $policy
        Write-Verbose "Policy details:"
        if ($VerbosePreference -eq 'Continue') {
            $policy | ConvertTo-Json -Depth 100
        }

        if ($PSCmdlet.ShouldProcess($policy.DisplayName, "Create policy")) {
            Write-Verbose "Creating policy..."
            New-MgIdentityConditionalAccessPolicy -BodyParameter $policy -ErrorAction Stop
            Write-Verbose "Policy created."
        } else {
            New-MgIdentityConditionalAccessPolicy -BodyParameter $policy -ErrorAction Stop -WhatIf
        }
    }
}
