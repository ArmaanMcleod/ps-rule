# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#
# PSRule
#

# See details at: https://github.com/Microsoft/ps-rule

[CmdletBinding()]
param (
    # The root path for analysis
    [Parameter(Mandatory = $False)]
    [String]$Path = $Env:INPUT_PATH,

    # The type of input
    [Parameter(Mandatory = $False)]
    [ValidateSet('repository', 'inputPath')]
    [String]$InputType = $Env:INPUT_INPUTTYPE,

     # The path to input files
     [Parameter(Mandatory = $False)]
     [String]$InputPath = $Env:INPUT_INPUTPATH,

    # The path to find rules
    [Parameter(Mandatory = $False)]
    [String]$Source = $Env:INPUT_SOURCE,

    # Rule modules to use
    [Parameter(Mandatory = $False)]
    [String]$Modules = $Env:INPUT_MODULES,

    # A baseline to use
    [Parameter(Mandatory = $False)]
    [String]$Baseline = $env:INPUT_BASELINE,

    # The conventions to use
    [Parameter(Mandatory = $False)]
    [String]$Conventions = $Env:INPUT_CONVENTIONS,

    # The output format
    [Parameter(Mandatory = $False)]
    [ValidateSet('None', 'Yaml', 'Json', 'NUnit3', 'Csv', 'Markdown', 'Sarif')]
    [String]$OutputFormat = $Env:INPUT_OUTPUTFORMAT,

    # The path to store formatted output
    [Parameter(Mandatory = $False)]
    [String]$OutputPath = $Env:INPUT_OUTPUTPATH,

    # Determine if a pre-release module version is installed.
    [Parameter(Mandatory = $False)]
    [String]$PreRelease = $Env:INPUT_PRERELEASE,

    # The specific version of PSRule to use.
    [Parameter(Mandatory = $False)]
    [String]$Version = $Env:INPUT_VERSION
)

$workspacePath = $Env:GITHUB_WORKSPACE;
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue;
if ($Env:SYSTEM_DEBUG -eq 'true') {
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue;
}

# Check inputType
if ([String]::IsNullOrEmpty($InputType) -or $InputType -notin 'repository', 'inputPath') {
    $InputType = 'repository';
}

# Set workspace
if ([String]::IsNullOrEmpty($workspacePath)) {
    $workspacePath = $PWD;
}

# Set Path
if ([String]::IsNullOrEmpty($Path)) {
    $Path = $workspacePath;
}
else {
    $Path = Join-Path -Path $workspacePath -ChildPath $Path;
}

# Set InputPath
if ([String]::IsNullOrEmpty($InputPath)) {
    $InputPath = $Path;
}
else {
    $InputPath = Join-Path -Path $Path -ChildPath $InputPath;
}

# Set Source
if ([String]::IsNullOrEmpty($Source)) {
    $Source = Join-Path -Path $Path -ChildPath '.ps-rule/';
}
else {
    $Source = Join-Path -Path $Path -ChildPath $Source;
}

# Set conventions
if (![String]::IsNullOrEmpty($Conventions)) {
    $Conventions = @($Conventions.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {
        $_.Trim();
    });
}
else {
    $Conventions = @();
}

function WriteDebug {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $True)]
        [String]$Message
    )
    process {
        if ($Env:SYSTEM_DEBUG -eq 'true' -or $Env:ACTIONS_STEP_DEBUG -eq 'true') {
            Write-Host "::debug::$Message";
        }
    }
}

#
# Check and install modules
#
$dependencyFile = Join-Path -Path $Env:GITHUB_ACTION_PATH -ChildPath 'modules.json';
$latestVersion = (Get-Content -Path $dependencyFile -Raw | ConvertFrom-Json -AsHashtable -Depth 5).dependencies.PSRule.version;
$checkParams = @{
    RequiredVersion = $latestVersion
}
if (![String]::IsNullOrEmpty($Version)) {
    $checkParams['RequiredVersion'] = $Version;
    if ($PreRelease -eq 'true') {
        $checkParams['AllowPrerelease'] = $True;
    }
}

# Look for existing versions of PSRule
$installed = @(Get-InstalledModule -Name PSRule @checkParams -ErrorAction Ignore)
if ($installed.Length -eq 0) {
    Write-Host "[info] Installing PSRule: $($checkParams.RequiredVersion)";
    $Null = Install-Module -Name PSRule @checkParams -Scope CurrentUser -Force;
}
foreach ($m in $installed) {
    Write-Host "[info] Using existing module $($m.Name): $($m.Version)";
}

# Look for existing modules
Write-Host '';
$moduleNames = @()
if (![String]::IsNullOrEmpty($Modules)) {
    $moduleNames = $Modules.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries);
}
$moduleParams = @{
    Scope = 'CurrentUser'
    Force = $True
}
if ($PreRelease -eq 'true') {
    $moduleParams['AllowPrerelease'] = $True;
}

# Install each module if not already installed
foreach ($m in $moduleNames) {
    $m = $m.Trim();
    Write-Host "> Checking module: $m";
    try {
        if ($Null -eq (Get-InstalledModule -Name $m -ErrorAction Ignore)) {
            Write-Host '  - Installing module';
            $Null = Install-Module -Name $m @moduleParams -AllowClobber -ErrorAction Stop;
        }
        else {
            Write-Host '  - Already installed';
        }
        # Check
        if ($Null -eq (Get-InstalledModule -Name $m)) {
            Write-Host "  - Failed to install";
        }
        else {
            Write-Host "  - Using version: $((Get-InstalledModule -Name $m).Version)";
        }
    }
    catch {
        Write-Host "::error::An error occurred installing a dependency module '$m'. $($_.Exception.Message)";
        $Host.SetShouldExit(1);
    }
}

try {
    $checkParams = @{ RequiredVersion = $checkParams.RequiredVersion.Split('-')[0] }
    $Null = Import-Module PSRule @checkParams -ErrorAction Stop;
    $version = (Get-Module PSRule).Version;
}
catch {
    Write-Host "::error::An error occurred importing module 'PSRule'. $($_.Exception.Message)";
    $Host.SetShouldExit(1);
}

#
# Run assert pipeline
#
Write-Host '';
Write-Host "[info] Using Version: $version";
Write-Host "[info] Using Action: $Env:GITHUB_ACTION";
Write-Host "[info] Using Workspace: $workspacePath"
Write-Host "[info] Using PWD: $PWD";
Write-Host "[info] Using Path: $Path";
Write-Host "[info] Using Source: $Source";
Write-Host "[info] Using Baseline: $Baseline";
Write-Host "[info] Using Conventions: $Conventions";
Write-Host "[info] Using InputType: $InputType";
Write-Host "[info] Using InputPath: $InputPath";
Write-Host "[info] Using OutputFormat: $OutputFormat";
Write-Host "[info] Using OutputPath: $OutputPath";

try {
    Push-Location -Path $Path;
    $invokeParams = @{
        Path = $Source
        Style = 'GitHubActions'
        ErrorAction = 'Stop'
    }
    WriteDebug "Preparing command-line:";
    WriteDebug ([String]::Concat('-Path ''', $Source, ''''));
    if (![String]::IsNullOrEmpty($Baseline)) {
        $invokeParams['Baseline'] = $Baseline;
        WriteDebug ([String]::Concat('-Baseline ''', $Baseline, ''''));
    }
    if ($Conventions.Length -gt 0) {
        $invokeParams['Convention'] = $Conventions;
        WriteDebug ([String]::Concat('-Convention ', [String]::Join(', ', $Conventions)));
    }
    if (![String]::IsNullOrEmpty($Modules)) {
        $moduleNames = $Modules.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries);
        $invokeParams['Module'] = $moduleNames;
        WriteDebug ([String]::Concat('-Module ', [String]::Join(', ', $moduleNames)));
    }
    if (![String]::IsNullOrEmpty($OutputFormat) -and ![String]::IsNullOrEmpty($OutputPath) -and $OutputFormat -ne 'None') {
        $invokeParams['OutputFormat'] = $OutputFormat;
        $invokeParams['OutputPath'] = $OutputPath;
        WriteDebug ([String]::Concat('-OutputFormat ', $OutputFormat, ' -OutputPath ''', $OutputPath, ''''));
    }

    # repository
    if ($InputType -eq 'repository') {
        WriteDebug 'Running ''Assert-PSRule'' with repository as input.';
        Write-Host '';
        Write-Host '---';
        Assert-PSRule @invokeParams -InputPath $InputPath -Format File;
    }
    # inputPath
    elseif ($InputType -eq 'inputPath') {
        WriteDebug 'Running ''Assert-PSRule'' with input from path.';
        Write-Host '';
        Write-Host '---';
        Assert-PSRule @invokeParams -InputPath $InputPath;
    }
}
catch {
    Write-Host "::error::One or more assertions failed.";
    $Host.SetShouldExit(1);
}
finally {
    Pop-Location;
}
Write-Host '---';
