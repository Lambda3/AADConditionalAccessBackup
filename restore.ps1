#Requires -PSEdition Desktop

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([switch]$NonInteractive, [DateTime]$Date, [switch]$Update)

Set-StrictMode -Version 3.0

$ErrorActionPreference = 'stop'

$IsWin = [System.PlatformID]::Win32NT, [System.PlatformID]::Win32S, [System.PlatformID]::Win32Windows, [System.PlatformID]::Win32Windows, [System.PlatformID]::WinCE, [System.PlatformID]::Xbox -contains [System.Environment]::OSVersion.Platform
if (!$IsWin) {
    Write-Error "This script is only for Windows."
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

# tem que chamar Connect-AzureAD antes
try {
    Write-Verbose "Checking if connected to AAD..."
    Get-AzureADTenantDetail | Out-Null
} catch {
    Connect-AzureAD
}

if ($PSBoundParameters.ContainsKey('Date')) {
    $selectedDate = $Date
} else {
    $dates = $dateDirs | ForEach-Object { Get-Date -Month $_.Name.Substring(4, 2) -Day $_.Name.Substring(6, 2) -Year $_.Name.Substring(0, 4) } | Sort-Object
    # $dates = $dates | Select-Object -first 3
    # $dates = @()
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
            Write-Host "Backup months:"
            $groups = $dates | Group-Object -Property { Get-Date $_ -Format MM/yyyy }
            if ($groups.Length -eq 1) {
            } else {
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
                if ($selectedGroup) {
                    $selectedGroup
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
    $policy = Get-Content $backupFile.FullName | ConvertFrom-Json
    $conditions = $null
    if ($policy.Conditions) {
        $conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet
        if ($policy.Conditions.Applications) {
            $conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
            $conditions.Applications.IncludeApplications = $policy.Conditions.Applications.IncludeApplications
            $conditions.Applications.ExcludeApplications = $policy.Conditions.Applications.ExcludeApplications
            $conditions.Applications.IncludeUserActions = $policy.Conditions.Applications.IncludeUserActions
            $conditions.Applications.IncludeAuthenticationContextClassReferences = $policy.Conditions.Applications.IncludeAuthenticationContextClassReferences
        }
        if ($policy.Conditions.Users) {
            $conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
            $conditions.Users.IncludeUsers = $policy.Conditions.Users.IncludeUsers
            $conditions.Users.ExcludeUsers = $policy.Conditions.Users.ExcludeUsers
            $conditions.Users.IncludeGroups = $policy.Conditions.Users.IncludeGroups
            $conditions.Users.ExcludeGroups = $policy.Conditions.Users.ExcludeGroups
            $conditions.Users.IncludeRoles = $policy.Conditions.Users.IncludeRoles
            $conditions.Users.ExcludeRoles = $policy.Conditions.Users.ExcludeRoles
        }

        if ($policy.Conditions.Locations) {
            $conditions.Locations = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessLocationCondition
            $conditions.Locations.IncludeLocations = $condition.Locations.IncludeLocations
            $conditions.Locations.ExcludeLocations = $condition.Locations.ExcludeLocations
        }
    }

    $grantControls = $null
    if ($policy.GrantControls) {
        $grantControls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
        $grantControls._Operator = $policy.GrantControls._Operator
        $grantControls.BuiltInControls = $policy.GrantControls.BuiltInControls
        $grantControls.CustomAuthenticationFactors = $policy.GrantControls.CustomAuthenticationFactors
        $grantControls.TermsOfUse = $policy.GrantControls.TermsOfUse
    }

    $sessionControls = $null
    if ($policy.SessionControls) {
        $sessionControls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessSessionControls
        if ($policy.SessionControls.ApplicationEnforcedRestrictions) {
            $sessionControls.ApplicationEnforcedRestrictions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationEnforcedRestrictions
            $sessionControls.ApplicationEnforcedRestrictions.IsEnabled = $policy.SessionControls.ApplicationEnforcedRestrictions.IsEnabled
        }
        if ($policy.SessionControls.CloudAppSecurity) {
            $sessionControls.CloudAppSecurity = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessCloudAppSecurity
            $sessionControls.CloudAppSecurity.CloudAppSecurityType = $policy.SessionControls.CloudAppSecurity.CloudAppSecurityType
            $sessionControls.CloudAppSecurity.IsEnabled = $policy.SessionControls.CloudAppSecurity.IsEnabled
        }
        if ($policy.SessionControls.SignInFrequency) {
            $sessionControls.SignInFrequency = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessSignInFrequency
            $sessionControls.SignInFrequency.Type = $policy.SessionControls.SignInFrequency.Type
            $sessionControls.SignInFrequency.Value = $policy.SessionControls.SignInFrequency.Value
            $sessionControls.SignInFrequency.IsEnabled = $policy.SessionControls.SignInFrequency.IsEnabled
        }
        if ($policy.SessionControls.PersistentBrowser) {
            $sessionControls.PersistentBrowser = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessPersistentBrowser
            $sessionControls.PersistentBrowser.Mode = $policy.SessionControls.PersistentBrowser.Mode
            $sessionControls.PersistentBrowser.IsEnabled = $policy.SessionControls.PersistentBrowser.IsEnabled
        }
    }

    if ($Update) {
        try {
            Get-AzureADMSConditionalAccessPolicy -PolicyId $policy.Id | Out-Null
            if ($PSCmdlet.ShouldProcess($policy.DisplayName, "Update policy")) {
                # Set-AzureADMSConditionalAccessPolicy -PolicyId $policy.Id -DisplayName $policy.DisplayName -State $policy.State -Conditions $conditions -GrantControls $grantControls -SessionControls $sessionControls
                Write-Host "Set-AzureADMSConditionalAccessPolicy"
            }
        } catch {
            Write-Warning "Policy id $($policy.Id) ($($policy.DisplayName)) not found. Skipping."
        }
    } else {
        $newPolicyName = "$($policy.DisplayName) (2)"
        if ($PSCmdlet.ShouldProcess($newPolicyName, "Create policy")) {
            # New-AzureADMSConditionalAccessPolicy -DisplayName $newPolicyName -State 'disabled' -Conditions $conditions -GrantControls $grantControls -SessionControls $sessionControls
            Write-Host "New-AzureADMSConditionalAccessPolicy"
        }
    }
}
