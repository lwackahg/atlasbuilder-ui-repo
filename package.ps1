# Builds the Thunderstore package for Riverheim AtlasBuilder UI into Releases\.
# The mod manager installs everything except the package files into BepInEx\plugins\Wackah-Riverheim_AtlasBuilder_UI.
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$manifest = Get-Content -Raw -LiteralPath 'ThunderstorePackage\manifest.json' | ConvertFrom-Json
$packageFiles = @('ThunderstorePackage\manifest.json', 'ThunderstorePackage\README.md', 'ThunderstorePackage\CHANGELOG.md', 'ThunderstorePackage\icon.png')
$launcherFiles = @('AtlasBuilder-Launcher.ps1', 'Run-AtlasBuilder-UI.cmd', 'RiverheimConfigHook.cs', 'RiverheimSettings.cs', 'settings.json', 'LICENSE')

$missing = @($packageFiles + $launcherFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) { throw "Missing: $($missing -join ', ')" }

[void](New-Item -ItemType Directory -Path 'Releases' -Force)
$zipPath = Join-Path $PSScriptRoot ("Releases\{0}-{1}.zip" -f $manifest.name, $manifest.version_number)
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
# Every file goes to the root of the zip, as Thunderstore expects.
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $packageFiles + $launcherFiles) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Resolve-Path -LiteralPath $file).Path, (Split-Path -Leaf $file))
    }
} finally {
    $zip.Dispose()
}
Write-Host "Built $zipPath ($((Get-Item -LiteralPath $zipPath).Length) bytes)"
