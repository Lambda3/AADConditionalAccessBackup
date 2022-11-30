#Requires -PSEdition Core
#Requires -Modules Microsoft.Graph.Identity.SignIns

[CmdletBinding(SupportsShouldProcess)]
param([switch]$Force, [string]$DataDirectory)

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

if ($DataDirectory) {
    $dataDir = $DataDirectory
} else {
    $dataDir = "$PSScriptRoot\data"
}
if (!(Test-Path "$dataDir")) {
    if ($PSCmdlet.ShouldProcess($dataDir, "Create directory")) {
        mkdir "$dataDir" | Out-Null
    }
}
$date = Get-Date -Format yyyyMMdd
$backupDir = "$dataDir\$date"
if (Test-Path $backupDir) {
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Run backup and possibly overwrite existing files")
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Do not run backup")
    )
    $shouldContinue = $Host.UI.PromptForChoice("Directory exists", "Backup directory '$backupDir' exists, overwrite files?", $choices, 1)
    if ($shouldContinue -eq 1) {
        Write-Host "Exiting without creating backup."
        exit
    }
} else {
    if ($PSCmdlet.ShouldProcess($backupDir, "Create directory")) {
        mkdir $backupDir | Out-Null
    }
}

Write-Verbose "Checking if connected to Microsoft Graph..."
$mgContext = Get-MgContext
if (!$mgContext -or ($mgContext.Scopes -notcontains 'Policy.Read.All')) {
    Connect-MgGraph -Scopes 'Policy.Read.All'
}

Write-Verbose "Getting policies..."
$policies = Get-MgIdentityConditionalAccessPolicy -All
$policies | ForEach-Object {
    $policy = $_
    $displayNameSanitized = $policy.DisplayName -replace '[<>:"/\\| ?*]', '_'
    $fileName = "$backupDir\$displayNameSanitized.json"
    Write-Verbose "Writing '$fileName'..."
    if ($PSCmdlet.ShouldProcess($fileName, "Write file")) {
        $policy | ConvertTo-Json -Depth 100 | Out-File -LiteralPath $fileName -Encoding UTF8
    }
}
Write-Verbose "Done."
