#Requires -PSEdition Desktop

[CmdletBinding(SupportsShouldProcess)]
param([switch]$NonInteractive)

Set-StrictMode -Version 3.0

$ErrorActionPreference = 'stop'

$IsWin = [System.PlatformID]::Win32NT, [System.PlatformID]::Win32S, [System.PlatformID]::Win32Windows, [System.PlatformID]::Win32Windows, [System.PlatformID]::WinCE, [System.PlatformID]::Xbox -contains [System.Environment]::OSVersion.Platform
if (!$IsWin) {
    Write-Error "This script is only for Windows."
}
if (!(Get-Command jq -ErrorAction Ignore)) {
    Write-Error "jq is not installed. Please install it from https://stedolan.github.io/jq/download/ (or via scoop or winget)."
}

$dataDir = "$PSScriptRoot\data"
if (!(Test-Path "$dataDir")) {
    if ($PSCmdlet.ShouldProcess($dataDir, "Create directory")) {
        mkdir "$dataDir" | Out-Null
    }
}
$date = Get-Date -Format yyyyMMdd
$backupDir = "$dataDir\$date"
if (Test-Path $backupDir) {
    if ($NonInteractive) {
        Write-Error "Backup directory already exists. Skipping."
    }
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

# tem que chamar Connect-AzureAD antes
try {
    Write-Verbose "Checking if connected to AAD..."
    Get-AzureADTenantDetail | Out-Null
} catch {
    Connect-AzureAD
}

Write-Verbose "Getting policies..."
$policies = Get-AzureADMSConditionalAccessPolicy
$policies | ForEach-Object {
    $policy = $_
    $displayNameSanitized = $policy.DisplayName -replace '[<>:"/\\| ?*]', '_'
    $fileName = "$backupDir\$displayNameSanitized.json"
    Write-Verbose "Writing '$fileName'..."
    if ($PSCmdlet.ShouldProcess($fileName, "Write file")) {
        $policy | ConvertTo-Json -Depth 100 | jq | Out-File -LiteralPath $fileName -Encoding UTF8
    }
}
Write-Verbose "Done."
