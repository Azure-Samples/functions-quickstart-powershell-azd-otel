$modulesPath = Join-Path $PSScriptRoot 'Modules'

# Ensure the modules directory exists
if (-not (Test-Path $modulesPath)) {
    New-Item -ItemType Directory -Path $modulesPath | Out-Null
}

# Install required modules to the specified folder
$modules = @(
    'AzureFunctions.PowerShell.Durable.SDK',
    'AzureFunctions.PowerShell.OpenTelemetry.SDK'
)

foreach ($module in $modules) {
    Save-Module -Name $module -Force -Path $modulesPath
}