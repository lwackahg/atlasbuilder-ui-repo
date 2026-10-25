# Riverheim AtlasBuilder launcher. Run with Windows PowerShell in STA mode.
[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
# AtlasBuilder sits next to the launcher when copied in by hand. A mod manager installs the launcher in its own folder,
# so also look in the other folders of the same BepInEx\plugins folder (Gurebu-Riverheim_AtlasBuilder).
$defaultExe = Join-Path $scriptRoot 'Riverheim.AtlasBuilder.exe'
if (-not (Test-Path -LiteralPath $defaultExe -PathType Leaf)) {
    try {
        $siblingExe = Get-ChildItem -LiteralPath (Split-Path -Parent $scriptRoot) -Directory -ErrorAction Stop |
            Sort-Object { $_.Name -notlike '*AtlasBuilder*' } |
            ForEach-Object { Join-Path $_.FullName 'Riverheim.AtlasBuilder.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ($siblingExe) { $defaultExe = $siblingExe }
    } catch { }
}
$defaultOutput = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Riverheim Maps'
$hookSource = Join-Path $scriptRoot 'RiverheimConfigHook.cs'
# RiverheimSettings.cs and settings.json come from the Riverheim Config mod repository (github.com/lwackahg/Riverheim_Config):
# the .cs is the mod's own settings table and is compiled into the hook, the .json is exported from it and builds the fields below.
$settingsSource = Join-Path $scriptRoot 'RiverheimSettings.cs'
$settingsSchemaPath = Join-Path $scriptRoot 'settings.json'
$hookCacheRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'RiverheimAtlasBuilderUI'
$launcherStatePath = Join-Path $hookCacheRoot 'launcher-state.json'
$engineInstalledText = 'Installed (matches your game)'
$engineBundledText = 'Bundled (older, can differ)'
$presetNames = [string[]]@('Default', 'Experimental', 'Mini', 'MiniExp', 'Token', 'HugeWorld')
# From AtlasBuilder 1.0.0's preset definitions (Riverheim.Configuration.ConfigManagerExtension).
$presetDescriptions = [ordered]@{
    Default = 'Normal Riverheim world, 10.5 km radius.'
    Experimental = 'Same world as Default, drawn with the newer Ashlands lava look.'
    Mini = 'Small 4 km world with its own simpler landmass layout.'
    MiniExp = 'The Mini world, drawn with the newer Ashlands lava look.'
    Token = 'Tiny 2 km world made of a single landmass.'
    HugeWorld = 'Huge 25 km world with the poles and landmass layout rescaled to fit.'
}
$defaultWorldRadius = 10500

# World settings shown in the launcher, read from settings.json (exported from the Riverheim Config mod's
# RiverheimSettings.cs, so new mod settings appear here without launcher changes). Sections and keys match the
# mod's config file; defaults are Riverheim 1.2.1's. Each entry: Group (section title), Section, Key, Label,
# Default, Decimals, Step, Min, Max, Tip, Optional (not in AtlasBuilder 1.0.0's older Riverheim).
$worldFields = @()
$settingsSchemaError = ''
try {
    if (-not (Test-Path -LiteralPath $settingsSchemaPath -PathType Leaf)) { throw 'settings.json was not found next to the launcher.' }
    $settingsSchema = Get-Content -LiteralPath $settingsSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sectionTitles = @{}
    foreach ($schemaSection in $settingsSchema.sections) { $sectionTitles[[string]$schemaSection.name] = [string]$schemaSection.title }
    $worldFields = @(foreach ($schemaSetting in $settingsSchema.settings) {
        $tip = [string]$schemaSetting.description
        if ($schemaSetting.previewNote) { $tip = "$tip $($schemaSetting.previewNote)" }
        $group = if ($sectionTitles.ContainsKey([string]$schemaSetting.section)) { $sectionTitles[[string]$schemaSetting.section] } else { [string]$schemaSetting.section }
        [pscustomobject]@{
            Group = $group; Section = [string]$schemaSetting.section; Key = [string]$schemaSetting.key; Label = [string]$schemaSetting.label
            Default = [double]$schemaSetting.default; Decimals = [int]$schemaSetting.decimals; Step = [double]$schemaSetting.step
            Min = [double]$schemaSetting.min; Max = [double]$schemaSetting.max; Tip = $tip; Optional = [bool]$schemaSetting.optional
        }
    })
    if ($worldFields.Count -eq 0) { throw 'settings.json lists no settings.' }
} catch {
    $settingsSchemaError = $_.Exception.Message
    $worldFields = @()
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 105)
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X, $Y)
    $label.Size = [System.Drawing.Size]::new($Width, 23)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $label
}

function Quote-Argument {
    param([string]$Value)
    '"' + ($Value -replace '(\\*)"', '$1$1\\"' -replace '(\\*)$', '$1$1') + '"'
}

function Format-SettingValue {
    param([decimal]$Value)
    $Value.ToString('0.#####', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-AtlasImages {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
    Get-ChildItem -LiteralPath $Directory -File -Recurse | Where-Object {
        $_.Extension -in '.jpg', '.jpeg', '.png'
    }
}

function Add-JpegComment {
    param([string]$ImagePath, [string]$Comment)

    if ([System.IO.Path]::GetExtension($ImagePath).ToLowerInvariant() -notin '.jpg', '.jpeg') { return $false }
    $image = $null
    $temporaryPath = "$ImagePath.atlasbuilder.tmp.jpg"
    try {
        $image = [System.Drawing.Image]::FromFile($ImagePath)
        $property = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Drawing.Imaging.PropertyItem])
        $property.Id = 37510 # EXIF UserComment
        $property.Type = 7
        $property.Value = [System.Text.Encoding]::UTF8.GetBytes("ASCII`0`0`0$Comment")
        $property.Len = $property.Value.Length
        $image.SetPropertyItem($property)
        $image.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $image.Dispose()
        $image = $null
        Move-Item -LiteralPath $temporaryPath -Destination $ImagePath -Force
        return $true
    } catch {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        return $false
    } finally {
        if ($null -ne $image) { $image.Dispose() }
    }
}

function Add-MapCaption {
    param([string]$ImagePath, [string[]]$Lines)

    # Adds a caption strip below the map (the map itself is not covered).
    $extension = [System.IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
    $format = if ($extension -eq '.png') { [System.Drawing.Imaging.ImageFormat]::Png } else { [System.Drawing.Imaging.ImageFormat]::Jpeg }
    $temporaryPath = "$ImagePath.caption.tmp"
    $source = $null
    $canvas = $null
    $graphics = $null
    $font = $null
    try {
        $source = [System.Drawing.Image]::FromFile($ImagePath)
        $width = $source.Width
        $height = $source.Height
        $padding = [Math]::Max(6, [int]($width / 80))
        $font = [System.Drawing.Font]::new('Segoe UI', [single][Math]::Max(11, $width / 60), [System.Drawing.GraphicsUnit]::Pixel)
        $text = $Lines -join [Environment]::NewLine

        $probe = [System.Drawing.Bitmap]::new(1, 1)
        $probeGraphics = [System.Drawing.Graphics]::FromImage($probe)
        $textSize = $probeGraphics.MeasureString($text, $font, $width - 2 * $padding)
        $probeGraphics.Dispose()
        $probe.Dispose()
        $bandHeight = [int][Math]::Ceiling($textSize.Height) + 2 * $padding

        $canvas = [System.Drawing.Bitmap]::new($width, $height + $bandHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        $graphics.Clear([System.Drawing.Color]::FromArgb(28, 30, 34))
        $graphics.DrawImage($source, 0, 0, $width, $height)
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $layout = [System.Drawing.RectangleF]::new($padding, $height + $padding, $width - 2 * $padding, $bandHeight - $padding)
        $graphics.DrawString($text, $font, [System.Drawing.Brushes]::WhiteSmoke, $layout)
        $graphics.Dispose()
        $graphics = $null
        $source.Dispose()
        $source = $null
        $canvas.Save($temporaryPath, $format)
        $canvas.Dispose()
        $canvas = $null
        Move-Item -LiteralPath $temporaryPath -Destination $ImagePath -Force
        return $true
    } catch {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        return $false
    } finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
        if ($null -ne $canvas) { $canvas.Dispose() }
        if ($null -ne $font) { $font.Dispose() }
    }
}

function Save-AtlasMetadata {
    param([pscustomobject]$Run)

    # AtlasBuilder names images after the seed only and wrote them into a private incoming folder. Move each one
    # into the mode folder under a name with the mode, tag, settings and time, so runs never overwrite each other.
    $images = @(Get-AtlasImages -Directory $Run.IncomingPath)
    [void](New-Item -ItemType Directory -Path $Run.OutputPath -Force)

    $count = 0
    foreach ($incoming in $images) {
        $seedPart = $incoming.BaseName
        $nameParts = @($seedPart, $Run.Settings.Mode)
        if ($Run.Settings.Tag) { $nameParts += $Run.Settings.Tag }
        $nameParts += $Run.Settings.SettingsId
        $nameParts += $Run.StartedAtUtc.ToLocalTime().ToString('yyyyMMdd-HHmmss')
        $baseName = $nameParts -join '_'
        $targetPath = Join-Path $Run.OutputPath "$baseName$($incoming.Extension)"
        $suffix = 2
        while (Test-Path -LiteralPath $targetPath) {
            $targetPath = Join-Path $Run.OutputPath "$baseName-$suffix$($incoming.Extension)"
            $suffix++
        }
        Move-Item -LiteralPath $incoming.FullName -Destination $targetPath
        $image = Get-Item -LiteralPath $targetPath

        $captioned = $false
        if ($Run.CaptionDetail) {
            $seedText = if ($seedPart -like 'atlas_*') { "Atlas of $($Run.Settings.Count) worlds from seed $($Run.Settings.Seed)" } else { "Seed $seedPart" }
            $headline = "$seedText  |  $($Run.Settings.Mode)  |  Preset $($Run.Settings.Preset)"
            if ($Run.Settings.CustomWorldSettings) { $headline += "  |  Settings $($Run.Settings.SettingsId)" }
            if ($Run.Settings.Tag) { $headline += "  |  $($Run.Settings.Tag)" }
            $captioned = Add-MapCaption -ImagePath $image.FullName -Lines (@($headline) + @($Run.CaptionDetail))
        }
        $metadata = [ordered]@{
            SchemaVersion = 2
            ImageFileName = $image.Name
            ImagePath = $image.FullName
            GeneratedAtUtc = $Run.StartedAtUtc.ToString('o')
            CaptionStamped = $captioned
            Settings = $Run.Settings
        }
        $metadataPath = "$($image.FullName).riverheim.json"
        $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
        $comment = "Riverheim AtlasBuilder | Seed=$($Run.Settings.Seed); Mode=$($Run.Settings.Mode); Resolution=$($Run.Settings.Resolution); Grid=$($Run.Settings.Grid); Whole=$($Run.Settings.Whole); Preset=$($Run.Settings.Preset); CustomWorld=$(if ($Run.Settings.CustomWorldSettings) { 'On' } else { 'Off' })"
        [void](Add-JpegComment -ImagePath $image.FullName -Comment $comment)
        $count++
    }
    Remove-Item -LiteralPath $Run.IncomingPath -Recurse -Force -ErrorAction SilentlyContinue
    return $count
}

function Find-RiverheimConfig {
    param([string]$AtlasExe)
    # AtlasBuilder sits in <profile>\BepInEx\plugins\<package>; the mod config is in <profile>\BepInEx\config.
    try {
        $directory = Split-Path -Parent $AtlasExe
        while ($directory) {
            $candidate = Join-Path $directory 'config\com.valheim.riverheim.config.cfg'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            $parent = Split-Path -Parent $directory
            if ($parent -eq $directory) { break }
            $directory = $parent
        }
    } catch { }
    return ''
}

function Get-CSharpCompiler {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    if (-not (Test-Path -LiteralPath $compiler)) { throw 'The C# compiler included with Windows (.NET Framework 4) was not found.' }
    return $compiler
}

function Invoke-CSharpCompiler {
    param([string]$Output, [string[]]$Sources, [string]$ReferenceDirectory, [string[]]$References)
    # Builds a startup hook DLL against AtlasBuilder's own .NET assemblies with the C# compiler that ships with Windows.
    $arguments = @('-nologo', '-nostdlib+', '-noconfig', '-target:library', ('-out:' + (Quote-Argument $Output)))
    foreach ($name in $References) {
        $arguments += '-reference:' + (Quote-Argument (Join-Path $ReferenceDirectory "$name.dll"))
    }
    foreach ($source in $Sources) { $arguments += Quote-Argument $source }

    $build = [System.Diagnostics.ProcessStartInfo]::new((Get-CSharpCompiler), ($arguments -join ' '))
    $build.UseShellExecute = $false
    $build.CreateNoWindow = $true
    $build.RedirectStandardOutput = $true
    $build.RedirectStandardError = $true
    $buildProcess = [System.Diagnostics.Process]::Start($build)
    $buildOutput = $buildProcess.StandardOutput.ReadToEnd() + $buildProcess.StandardError.ReadToEnd()
    $buildProcess.WaitForExit()
    if ($buildProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Output)) {
        throw "Could not build $(@($Sources | ForEach-Object { Split-Path -Leaf $_ }) -join ' and '):`n$buildOutput"
    }
}

function Test-WindowsExecutable {
    param([string]$Path)
    # Windows programs start with "MZ"; the Linux AtlasBuilder in the same package does not.
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try { return ($stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A) } finally { $stream.Dispose() }
    } catch { return $false }
}

function Get-AtlasBundle {
    param([string]$AtlasExe)
    # AtlasBuilder is a single-file app. Starting it once with no arguments (it only prints its help) unpacks its
    # assemblies into the cache folder, so hooks can be compiled against them and the installed engine can copy them.
    # Returns the cache folder for this AtlasBuilder build and the folder holding the unpacked assemblies.
    $exeInfo = Get-Item -LiteralPath $AtlasExe
    $cacheDir = Join-Path $hookCacheRoot ('{0}-{1}' -f $exeInfo.Length, $exeInfo.LastWriteTimeUtc.Ticks)
    $bundleRoot = Join-Path $cacheDir 'bundle'
    $core = Get-ChildItem -LiteralPath $bundleRoot -Filter 'Riverheim.Core.dll' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $core) {
        [void](New-Item -ItemType Directory -Path $bundleRoot -Force)
        $unpack = [System.Diagnostics.ProcessStartInfo]::new($AtlasExe)
        $unpack.UseShellExecute = $false
        $unpack.CreateNoWindow = $true
        $unpack.RedirectStandardOutput = $true
        $unpack.RedirectStandardError = $true
        $unpack.EnvironmentVariables['DOTNET_BUNDLE_EXTRACT_BASE_DIR'] = $bundleRoot
        $unpackProcess = [System.Diagnostics.Process]::Start($unpack)
        [void]$unpackProcess.StandardOutput.ReadToEndAsync()
        [void]$unpackProcess.StandardError.ReadToEndAsync()
        if (-not $unpackProcess.WaitForExit(60000)) {
            $unpackProcess.Kill()
            throw 'AtlasBuilder did not finish unpacking within 60 seconds.'
        }
        $core = Get-ChildItem -LiteralPath $bundleRoot -Filter 'Riverheim.Core.dll' -File -Recurse | Select-Object -First 1
        if ($null -eq $core) { throw 'Could not find the unpacked AtlasBuilder assemblies.' }
    }
    return [pscustomobject]@{ CacheDir = $cacheDir; Root = $bundleRoot; AssemblyDir = $core.DirectoryName }
}

function Get-RiverheimConfigHook {
    param([string]$AtlasExe, [pscustomobject]$Engine)
    # Builds RiverheimConfigHook.cs together with RiverheimSettings.cs (the mod's settings table) into a small DLL,
    # against the Riverheim that will draw the map (the installed one, or AtlasBuilder's own). Rebuilt only when
    # AtlasBuilder, that Riverheim or one of the .cs files changes.
    if (-not (Test-Path -LiteralPath $hookSource -PathType Leaf)) {
        throw 'RiverheimConfigHook.cs was not found next to the launcher.'
    }
    if (-not (Test-Path -LiteralPath $settingsSource -PathType Leaf)) {
        throw 'RiverheimSettings.cs was not found next to the launcher.'
    }
    if ($Engine -and $Engine.Installed) {
        $hookDll = Join-Path $Engine.Dir 'RiverheimConfigHook.dll'
        $referenceDir = $Engine.AssemblyDir
    } else {
        $bundle = Get-AtlasBundle -AtlasExe $AtlasExe
        $hookDll = Join-Path $bundle.CacheDir 'RiverheimConfigHook.dll'
        $referenceDir = $bundle.AssemblyDir
    }
    $newestSource = @((Get-Item -LiteralPath $hookSource).LastWriteTimeUtc, (Get-Item -LiteralPath $settingsSource).LastWriteTimeUtc) | Sort-Object -Descending | Select-Object -First 1
    if ((Test-Path -LiteralPath $hookDll) -and (Get-Item -LiteralPath $hookDll).LastWriteTimeUtc -ge $newestSource) {
        return $hookDll
    }
    # netstandard: the installed Riverheim.dll targets .NET Standard 2.1.
    Invoke-CSharpCompiler -Output $hookDll -Sources @($hookSource, $settingsSource) -ReferenceDirectory $referenceDir `
        -References @('System.Private.CoreLib', 'System.Runtime', 'System.Console', 'System.Collections', 'netstandard', 'Riverheim.Core')
    return $hookDll
}

# ---- Riverheim engine --------------------------------------------------------------------------------------------
# AtlasBuilder 1.0.0 bundles an older Riverheim than the one players run, so its maps can differ from the game.
# With the "Installed Riverheim" engine the launcher makes AtlasBuilder draw with the player's own Riverheim.dll:
#   1. AtlasBuilder's unpacked assemblies are copied to a cache folder, with Riverheim.Core.dll replaced by the
#      installed Riverheim.dll (renamed, since AtlasBuilder looks for "Riverheim.Core"), and AtlasBuilder's Default
#      preset pointed at the preset version that Riverheim gives new worlds. Both are done with Mono.Cecil, which
#      BepInEx already ships in BepInEx\core.
#   2. AtlasBuilder's own, unmodified exe is started with DOTNET_BUNDLE_EXTRACT_BASE_DIR pointing at that folder,
#      so it loads those files, and with a small startup hook that finds the BepInEx and Unity assemblies
#      Riverheim.dll refers to (in BepInEx\core and Valheim's Managed folder; nothing is copied from them).
# Nothing is downloaded, and no game, mod or AtlasBuilder file is changed. Everything lives under %LocalAppData%.
$engineFormat = 'e1'
$depsHookCode = @'
// Lets AtlasBuilder load an installed Riverheim.dll: resolves the BepInEx, Harmony and Unity assemblies it refers
// to from the folders listed in RIVERHEIM_DEPS_DIR (separated by ';'). Written by the Riverheim AtlasBuilder UI.
using System;
using System.IO;
using System.Reflection;

public static class StartupHook
{
    public static void Initialize()
    {
        string list = Environment.GetEnvironmentVariable("RIVERHEIM_DEPS_DIR");
        if (string.IsNullOrEmpty(list)) return;
        string[] directories = list.Split(';');
        AppDomain.CurrentDomain.AssemblyResolve += delegate(object sender, ResolveEventArgs args)
        {
            string file = new AssemblyName(args.Name).Name + ".dll";
            foreach (string directory in directories)
            {
                if (directory.Length == 0) continue;
                string path = Path.Combine(directory, file);
                if (File.Exists(path)) return Assembly.LoadFrom(path);
            }
            return null;
        };
    }
}
'@
$engineBuilderCode = @'
using System;
using System.IO;
using Mono.Cecil;
using Mono.Cecil.Cil;

public static class RiverheimEngineBuilder
{
    // Writes riverheimDll as Riverheim.Core.dll and AtlasBuilder's Riverheim.Dev.dll with its Default preset version
    // set to the one Riverheim gives new worlds. Returns that preset version.
    public static int Build(string riverheimDll, string devDll, string outDir, string[] searchDirs)
    {
        DefaultAssemblyResolver resolver = new DefaultAssemblyResolver();
        foreach (string dir in searchDirs) { if (Directory.Exists(dir)) resolver.AddSearchDirectory(dir); }
        ReaderParameters parameters = new ReaderParameters();
        parameters.InMemory = true;
        parameters.AssemblyResolver = resolver;

        AssemblyDefinition core = AssemblyDefinition.ReadAssembly(riverheimDll, parameters);
        TypeDefinition manager = core.MainModule.GetType("Riverheim.Configuration.ConfigManager");
        if (manager == null) throw new InvalidOperationException("this Riverheim.dll has no ConfigManager, so AtlasBuilder cannot use it (Riverheim 1.1 or newer is needed)");
        FieldDefinition versionField = null;
        foreach (FieldDefinition field in manager.Fields) { if (field.Name == "PRESET_DEFAULT_VERSION") versionField = field; }
        if (versionField == null || !versionField.HasConstant) throw new InvalidOperationException("this Riverheim.dll does not say which preset version new worlds get");
        int version = Convert.ToInt32(versionField.Constant);
        core.Name.Name = "Riverheim.Core";
        core.MainModule.Name = "Riverheim.Core.dll";
        core.Write(Path.Combine(outDir, "Riverheim.Core.dll"));

        AssemblyDefinition dev = AssemblyDefinition.ReadAssembly(devDll, parameters);
        int patched = 0;
        foreach (TypeDefinition type in dev.MainModule.GetTypes())
        {
            foreach (MethodDefinition method in type.Methods)
            {
                if (!method.HasBody) continue;
                Mono.Collections.Generic.Collection<Instruction> instructions = method.Body.Instructions;
                for (int i = 0; i + 2 < instructions.Count; i++)
                {
                    MethodReference constructor = instructions[i + 2].Operand as MethodReference;
                    if (instructions[i].OpCode == OpCodes.Ldstr && (instructions[i].Operand as string) == "builtin.amur" &&
                        constructor != null && constructor.DeclaringType.Name == "WorldSettings")
                    {
                        instructions[i + 1].OpCode = OpCodes.Ldc_I4;
                        instructions[i + 1].Operand = version;
                        patched++;
                    }
                }
            }
        }
        if (patched == 0) throw new InvalidOperationException("could not find AtlasBuilder's Default preset, so this AtlasBuilder version is not supported");
        dev.Write(Path.Combine(outDir, "Riverheim.Dev.dll"));
        return version;
    }
}
'@

function Get-LauncherState {
    try {
        if (Test-Path -LiteralPath $launcherStatePath -PathType Leaf) { return (Get-Content -LiteralPath $launcherStatePath -Raw | ConvertFrom-Json) }
    } catch { }
    return [pscustomobject]@{}
}

function Save-LauncherState {
    param([string]$Name, [string]$Value)
    try {
        $state = Get-LauncherState
        $state | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
        [void](New-Item -ItemType Directory -Path $hookCacheRoot -Force)
        $state | ConvertTo-Json | Set-Content -LiteralPath $launcherStatePath -Encoding UTF8
    } catch { }
}

function Get-RiverheimVersion {
    param([string]$Path)
    try {
        $version = [System.Reflection.AssemblyName]::GetAssemblyName($Path).Version
        return '{0}.{1}.{2}' -f $version.Major, $version.Minor, $version.Build
    } catch { return '' }
}

function Find-InstalledRiverheim {
    param([string]$AtlasExe)
    # The launcher sits next to AtlasBuilder in <profile>\BepInEx\plugins\Gurebu-Riverheim_AtlasBuilder, so the
    # Riverheim mod of the same profile is normally in plugins\Gurebu-Riverheim.
    $saved = (Get-LauncherState).RiverheimDll
    if ($saved -and (Test-Path -LiteralPath $saved -PathType Leaf)) { return $saved }
    try {
        $plugins = Split-Path -Parent (Split-Path -Parent $AtlasExe)
        $candidate = Join-Path $plugins 'Gurebu-Riverheim\Riverheim.dll'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        foreach ($folder in @(Get-ChildItem -LiteralPath $plugins -Directory -ErrorAction SilentlyContinue)) {
            $candidate = Join-Path $folder.FullName 'Riverheim.dll'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    } catch { }
    return ''
}

function Find-BepInExCore {
    param([string]$RiverheimDll)
    # Walks up from the Riverheim mod to the profile's BepInEx\core.
    try {
        $directory = Split-Path -Parent $RiverheimDll
        while ($directory) {
            foreach ($candidate in @((Join-Path $directory 'core'), (Join-Path $directory 'BepInEx\core'))) {
                if (Test-Path -LiteralPath (Join-Path $candidate 'Mono.Cecil.dll') -PathType Leaf) { return $candidate }
            }
            $parent = Split-Path -Parent $directory
            if ($parent -eq $directory) { break }
            $directory = $parent
        }
    } catch { }
    return ''
}

function Test-ValheimDir {
    param([string]$Path)
    # [IO.Path] rather than Join-Path here and below: Join-Path fails on a drive that is not connected, and Steam's
    # library list can name one.
    if (-not $Path) { return $false }
    try { return [System.IO.File]::Exists([System.IO.Path]::Combine($Path, 'valheim_Data\Managed\assembly_valheim.dll')) } catch { return $false }
}

function Find-ValheimDir {
    # The folder that holds valheim.exe: remembered from last time, or found through Steam's library list.
    $saved = (Get-LauncherState).ValheimDir
    if (Test-ValheimDir $saved) { return $saved }
    $libraries = [System.Collections.Generic.List[string]]::new()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $properties = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($name in 'SteamPath', 'InstallPath') {
                if ($properties.$name) { $libraries.Add(($properties.$name -replace '/', '\')) }
            }
        } catch { }
    }
    foreach ($steam in @($libraries)) {
        try {
            $vdf = [System.IO.Path]::Combine($steam, 'steamapps\libraryfolders.vdf')
            if ([System.IO.File]::Exists($vdf)) {
                foreach ($match in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                    $libraries.Add(($match.Groups[1].Value -replace '\\\\', '\'))
                }
            }
        } catch { }
    }
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne 'Fixed' -or -not $drive.IsReady) { continue }
        foreach ($relative in 'SteamLibrary', 'Steam', 'Program Files (x86)\Steam', 'Program Files\Steam', 'Games\Steam') {
            $libraries.Add([System.IO.Path]::Combine($drive.RootDirectory.FullName, $relative))
        }
    }
    foreach ($library in $libraries) {
        try { $candidate = [System.IO.Path]::Combine($library, 'steamapps\common\Valheim') } catch { continue }
        if (Test-ValheimDir $candidate) { return $candidate }
    }
    return ''
}

function Get-EngineSources {
    param([string]$AtlasExe)
    # Everything the installed engine needs, found automatically. Missing lists what could not be found.
    $riverheimDll = Find-InstalledRiverheim -AtlasExe $AtlasExe
    $bepInExCore = if ($riverheimDll) { Find-BepInExCore -RiverheimDll $riverheimDll } else { '' }
    $valheimDir = Find-ValheimDir
    $missing = @()
    if (-not $riverheimDll) { $missing += 'Riverheim' }
    elseif (-not $bepInExCore) { $missing += 'BepInEx' }
    if (-not $valheimDir) { $missing += 'Valheim' }
    return [pscustomobject]@{
        RiverheimDll = $riverheimDll
        Version = if ($riverheimDll) { Get-RiverheimVersion $riverheimDll } else { '' }
        BepInExCore = $bepInExCore
        ValheimDir = $valheimDir
        Missing = $missing
    }
}

function Get-FileShortHash {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $bytes = $sha.ComputeHash($stream)
        return (-join ($bytes[0..5] | ForEach-Object { $_.ToString('x2') }))
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Start-AtlasBuilderProcess {
    param([string]$AtlasExe, [string]$Arguments, [hashtable]$Environment, [string]$WindowStyle = 'Normal')
    # AtlasBuilder needs a real console window (its progress display crashes on redirected output), so it is started
    # through the shell. It inherits the launcher's environment, so the variables are set only around the start.
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $AtlasExe
    $process.StartInfo.Arguments = $Arguments
    $process.StartInfo.UseShellExecute = $true
    $process.StartInfo.WindowStyle = $WindowStyle
    try {
        foreach ($name in $Environment.Keys) { Set-Item -LiteralPath "Env:$name" -Value $Environment[$name] }
        [void]$process.Start()
    } finally {
        foreach ($name in $Environment.Keys) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
    }
    return $process
}

function Get-InstalledEngine {
    param([string]$AtlasExe, [pscustomobject]$Sources)
    # Prepares (once per AtlasBuilder and Riverheim build) and returns the installed Riverheim engine.
    if ($Sources.Missing.Count -gt 0) { throw "Not found: $($Sources.Missing -join ', '). Click Find... next to the Riverheim choice to point the launcher at it." }
    $bundle = Get-AtlasBundle -AtlasExe $AtlasExe
    $key = '{0}-{1}-{2}' -f $engineFormat, (Get-FileShortHash $Sources.RiverheimDll), (Split-Path -Leaf $bundle.CacheDir)
    $engineDir = Join-Path $hookCacheRoot "engines\$key"
    $extractRoot = Join-Path $engineDir 'extract'
    $depsHook = Join-Path $engineDir 'RiverheimDepsHook.dll'
    $readyFile = Join-Path $engineDir 'ready.json'
    $depsDirs = @($Sources.BepInExCore, (Join-Path $Sources.ValheimDir 'valheim_Data\Managed')) -join ';'
    $relative = $bundle.AssemblyDir.Substring($bundle.Root.Length).TrimStart('\')
    $engine = [pscustomobject]@{
        Installed = $true
        Dir = $engineDir
        ExtractRoot = $extractRoot
        AssemblyDir = Join-Path $extractRoot $relative
        DepsHook = $depsHook
        DepsDirs = $depsDirs
        Version = $Sources.Version
        PresetVersion = 0
        Label = "Installed Riverheim $($Sources.Version)"
    }
    if (Test-Path -LiteralPath $readyFile -PathType Leaf) {
        $ready = Get-Content -LiteralPath $readyFile -Raw | ConvertFrom-Json
        $engine.PresetVersion = [int]$ready.PresetVersion
        return $engine
    }

    if (Test-Path -LiteralPath $engineDir) { Remove-Item -LiteralPath $engineDir -Recurse -Force }
    [void](New-Item -ItemType Directory -Path $extractRoot -Force)
    Copy-Item -Path (Join-Path $bundle.Root '*') -Destination $extractRoot -Recurse -Force

    $cecil = Join-Path $Sources.BepInExCore 'Mono.Cecil.dll'
    if (-not ('RiverheimEngineBuilder' -as [type])) {
        Add-Type -Path $cecil
        Add-Type -TypeDefinition $engineBuilderCode -ReferencedAssemblies @($cecil)
    }
    try {
        $searchDirs = [string[]]@((Split-Path -Parent $Sources.RiverheimDll), $Sources.BepInExCore, (Join-Path $Sources.ValheimDir 'valheim_Data\Managed'), $bundle.AssemblyDir)
        $engine.PresetVersion = [RiverheimEngineBuilder]::Build($Sources.RiverheimDll, (Join-Path $bundle.AssemblyDir 'Riverheim.Dev.dll'), $engine.AssemblyDir, $searchDirs)
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        throw "Could not prepare Riverheim $($Sources.Version) for AtlasBuilder: $($inner.Message)"
    }

    $depsSource = Join-Path $engineDir 'RiverheimDepsHook.cs'
    Set-Content -LiteralPath $depsSource -Value $depsHookCode -Encoding UTF8
    Invoke-CSharpCompiler -Output $depsHook -Sources @($depsSource) -ReferenceDirectory $engine.AssemblyDir -References @('System.Private.CoreLib', 'System.Runtime', 'System.Console')

    # Draw one small map to prove the engine works before trusting it with real maps.
    $checkDir = Join-Path $engineDir 'check'
    [void](New-Item -ItemType Directory -Path $checkDir -Force)
    $checkArguments = @('--path', (Quote-Argument $checkDir), '--seed', 'EngineCheck', '--mode', 'Landmass', '--resolution', '256', '--count', '-1', '--preset', 'Default') -join ' '
    $check = Start-AtlasBuilderProcess -AtlasExe $AtlasExe -Arguments $checkArguments -WindowStyle 'Minimized' -Environment @{
        DOTNET_BUNDLE_EXTRACT_BASE_DIR = $extractRoot; DOTNET_STARTUP_HOOKS = $depsHook; RIVERHEIM_DEPS_DIR = $depsDirs
    }
    if (-not $check.WaitForExit(180000)) {
        try { $check.Kill() } catch { }
        throw "Riverheim $($Sources.Version) did not finish a test map within 3 minutes."
    }
    if (-not (Get-ChildItem -LiteralPath $checkDir -Filter '*.png' -File -ErrorAction SilentlyContinue)) {
        throw "AtlasBuilder could not draw a test map with Riverheim $($Sources.Version) (exit code $($check.ExitCode))."
    }
    [ordered]@{ RiverheimDll = $Sources.RiverheimDll; Version = $Sources.Version; PresetVersion = $engine.PresetVersion; PreparedAtUtc = [DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $readyFile -Encoding UTF8
    return $engine
}

function Get-ChangedWorldSettings {
    $changed = @()
    foreach ($field in $worldFields) {
        if ($field.Input.Value -ne [decimal]$field.Default) { $changed += '{0} {1}' -f $field.Label, (Format-SettingValue $field.Input.Value) }
    }
    return $changed
}

function Get-WorldSettingsSnapshot {
    $snapshot = [ordered]@{}
    foreach ($field in $worldFields) { $snapshot[$field.Key] = [double]$field.Input.Value }
    return $snapshot
}

function Write-WorldSettingsFile {
    param([string]$Path)
    # Same format as the Riverheim Config mod's config file; read by RiverheimConfigHook.cs.
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Riverheim Config settings written by Riverheim AtlasBuilder UI. The game adds descriptions the next time it starts.')
    $section = ''
    foreach ($field in $worldFields) {
        if ($field.Section -ne $section) {
            $section = $field.Section
            $lines.Add('')
            $lines.Add("[$section]")
        }
        $lines.Add("$($field.Key) = $(Format-SettingValue $field.Input.Value)")
    }
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force)
    Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
}

function ConvertTo-FileTag {
    param([string]$Text)
    $clean = ($Text.Trim() -replace '[\\/:*?"<>|]', '') -replace '\s+', '-'
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    return $clean
}

function Get-ShortHash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
        return (-join ($bytes[0..2] | ForEach-Object { $_.ToString('x2') }))
    } finally {
        $sha.Dispose()
    }
}

function Format-TipText {
    param([string]$Text, [int]$Width = 70)
    $lines = [System.Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($word in ($Text -split ' ')) {
        if ($line.Length -gt 0 -and ($line.Length + 1 + $word.Length) -gt $Width) {
            $lines.Add($line)
            $line = $word
        } elseif ($line.Length -gt 0) {
            $line = "$line $word"
        } else {
            $line = $word
        }
    }
    if ($line) { $lines.Add($line) }
    return ($lines -join "`n")
}

function ConvertTo-Number {
    param([string]$Text)
    $number = 0.0
    if ($Text -and [double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number }
    return $null
}

function Import-ExpandWorldSize {
    param([string]$Directory)
    # Reads Expand World Size's config next to the Riverheim Config file. Only the stretch is used, for the caption.
    $path = Join-Path $Directory 'expand_world_size.cfg'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $values = @{}
    foreach ($raw in (Get-Content -LiteralPath $path)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#') -or $line.StartsWith('[')) { continue }
        $equals = $line.IndexOf('=')
        if ($equals -gt 0) { $values[$line.Substring(0, $equals).Trim()] = $line.Substring($equals + 1).Trim() }
    }
    $stretch = ConvertTo-Number $values['Stretch world']
    if ($null -eq $stretch) { return @() }
    $importedEdge = ConvertTo-Number $values['World edge size']
    if ($null -ne $importedEdge) { $script:ewsEdge = $importedEdge }
    $ewsStretchBox.Value = [decimal][Math]::Min([Math]::Max($stretch, 0.1), 10)
    $notes = @("Read expand_world_size.cfg: EWS stretch set to $stretch.")
    $biomeStretch = ConvertTo-Number $values['Stretch biomes']
    if ($null -ne $biomeStretch -and $biomeStretch -ne $stretch) {
        $notes += "Stretch biomes is $biomeStretch but Stretch world is $stretch. Riverheim needs them to be equal."
    }
    $radius = ConvertTo-Number $values['World radius']
    $edge = ConvertTo-Number $values['World edge size']
    if ($null -ne $radius -and $null -ne $edge) {
        $expected = [Math]::Round($defaultWorldRadius * $stretch)
        if ([Math]::Abs(($radius + $edge) - $expected) -gt 1) {
            $notes += "EWS World radius + World edge size is $($radius + $edge) m. For stretch $stretch, Riverheim expects $expected m (10500 x stretch)."
        }
    }
    $radiusField = $worldFields | Where-Object { $_.Key -eq 'WorldRadius' }
    if ($stretch -ne 1 -and $radiusField.Input.Value -ne $defaultWorldRadius) {
        $notes += "Riverheim Config World radius is $(Format-SettingValue $radiusField.Input.Value), not 10500, while EWS also stretches the world. Riverheim expects the EWS stretch to do the enlarging, so this likely enlarges the world twice. World radius should usually stay at 10500."
    }
    return $notes
}

function Sync-WorldSize {
    param([string]$From)
    # In-game radius and EWS stretch are linked: radius = 10500 x stretch.
    if ($script:syncingWorldSize -or $null -eq $worldSizeBox -or $null -eq $ewsStretchBox) { return }
    $script:syncingWorldSize = $true
    try {
        if ($From -eq 'Size') {
            $stretch = [decimal][Math]::Round([double]$worldSizeBox.Value / $defaultWorldRadius, 3)
            $ewsStretchBox.Value = [Math]::Min([Math]::Max($stretch, $ewsStretchBox.Minimum), $ewsStretchBox.Maximum)
        } else {
            $size = [decimal][Math]::Round([double]$ewsStretchBox.Value * $defaultWorldRadius)
            $worldSizeBox.Value = [Math]::Min([Math]::Max($size, $worldSizeBox.Minimum), $worldSizeBox.Maximum)
        }
    } finally {
        $script:syncingWorldSize = $false
    }
    Update-WorldSettingsSummary
}

function Get-EwsSettingsLines {
    # The expand_world_size.cfg values Riverheim expects for the chosen size: World radius + World edge size = 10500 x stretch.
    $edge = if ($script:ewsEdge) { [double]$script:ewsEdge } else { 500 }
    $size = [double]$worldSizeBox.Value
    $stretch = [Math]::Round($size / $defaultWorldRadius, 4)
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    return @(
        ('World radius = ' + ($size - $edge).ToString($invariant)),
        ('World edge size = ' + $edge.ToString($invariant)),
        ('Stretch world = ' + $stretch.ToString($invariant)),
        ('Stretch biomes = ' + $stretch.ToString($invariant))
    )
}

function Import-WorldSettings {
    param([string]$Path)
    $entries = @{}
    $section = ''
    foreach ($raw in (Get-Content -LiteralPath $Path)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $section = $line.Substring(1, $line.Length - 2).Trim()
            continue
        }
        $equals = $line.IndexOf('=')
        if ($equals -lt 0) { continue }
        $entries["$section|$($line.Substring(0, $equals).Trim())"] = $line.Substring($equals + 1).Trim()
    }

    $applied = 0
    foreach ($field in $worldFields) {
        $text = $entries["$($field.Section)|$($field.Key)"]
        $number = 0.0
        if ($text -and [double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            $value = [decimal][Math]::Round($number, $field.Decimals)
            $field.Input.Value = [Math]::Min([Math]::Max($value, $field.Input.Minimum), $field.Input.Maximum)
            $applied++
        }
    }

    # Riverheim Config files from before the ocean depth split have one OceanDepth that set both depths.
    $legacyOcean = $entries['1. World|OceanDepth']
    $legacyNumber = 0.0
    if ($legacyOcean -and -not $entries.ContainsKey('1. World|SeaFloorDepth') -and -not $entries.ContainsKey('1. World|OceanBiomeDepth') -and
        [double]::TryParse($legacyOcean, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$legacyNumber)) {
        foreach ($field in @($worldFields | Where-Object { $_.Key -in 'SeaFloorDepth', 'OceanBiomeDepth' })) {
            $field.Input.Value = [Math]::Min([Math]::Max([decimal]$legacyNumber, $field.Input.Minimum), $field.Input.Maximum)
            $applied++
        }
    }
    return $applied
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'Riverheim AtlasBuilder'
$form.ClientSize = [System.Drawing.Size]::new(1400, 1336)
$form.MinimumSize = [System.Drawing.Size]::new(1100, 860)
$form.StartPosition = 'CenterScreen'
$form.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

$title = [System.Windows.Forms.Label]::new()
$title.Text = 'Riverheim AtlasBuilder'
$title.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 16)
$title.Location = [System.Drawing.Point]::new(18, 15)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = [System.Windows.Forms.Label]::new()
$subtitle.Text = 'Generate a map image from a Riverheim world seed.'
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = [System.Drawing.Point]::new(20, 43)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$form.Controls.Add((New-Label 'AtlasBuilder' 18 78))
$exeBox = [System.Windows.Forms.TextBox]::new()
$exeBox.Location = [System.Drawing.Point]::new(125, 78)
$exeBox.Size = [System.Drawing.Size]::new(430, 23)
$exeBox.Text = $defaultExe
$form.Controls.Add($exeBox)

$browseExe = [System.Windows.Forms.Button]::new()
$browseExe.Text = 'Browse...'
$browseExe.Location = [System.Drawing.Point]::new(564, 77)
$browseExe.Size = [System.Drawing.Size]::new(78, 25)
$form.Controls.Add($browseExe)

$form.Controls.Add((New-Label 'World seed' 18 115))
$seedBox = [System.Windows.Forms.TextBox]::new()
$seedBox.Location = [System.Drawing.Point]::new(125, 115)
$seedBox.Size = [System.Drawing.Size]::new(110, 23)
$form.Controls.Add($seedBox)

$form.Controls.Add((New-Label 'Tag' 244 115 30))
$tagBox = [System.Windows.Forms.TextBox]::new()
$tagBox.Location = [System.Drawing.Point]::new(276, 115)
$tagBox.Size = [System.Drawing.Size]::new(110, 23)
$form.Controls.Add($tagBox)

$form.Controls.Add((New-Label 'World count' 400 115 75))
$countBox = [System.Windows.Forms.NumericUpDown]::new()
$countBox.Location = [System.Drawing.Point]::new(475, 115)
$countBox.Size = [System.Drawing.Size]::new(78, 23)
$countBox.Minimum = -1
$countBox.Maximum = 1000
$countBox.Value = -1
$form.Controls.Add($countBox)

$form.Controls.Add((New-Label 'Output folder' 18 152))
$outputBox = [System.Windows.Forms.TextBox]::new()
$outputBox.Location = [System.Drawing.Point]::new(125, 152)
$outputBox.Size = [System.Drawing.Size]::new(430, 23)
$outputBox.Text = $defaultOutput
$form.Controls.Add($outputBox)

$browseOutput = [System.Windows.Forms.Button]::new()
$browseOutput.Text = 'Browse...'
$browseOutput.Location = [System.Drawing.Point]::new(564, 151)
$browseOutput.Size = [System.Drawing.Size]::new(78, 25)
$form.Controls.Add($browseOutput)

$allMapModes = [string[]]@('Rich', 'Landmass', 'Biomes', 'RichTerrain', 'Hdr')
$script:selectedModes = [string[]]@('Rich')
$form.Controls.Add((New-Label 'Map modes' 18 190))
$modeSummary = [System.Windows.Forms.TextBox]::new()
$modeSummary.Location = [System.Drawing.Point]::new(125, 190)
$modeSummary.Size = [System.Drawing.Size]::new(170, 23)
$modeSummary.ReadOnly = $true
$modeSummary.BackColor = [System.Drawing.Color]::White
$modeSummary.Text = 'Rich'
$form.Controls.Add($modeSummary)

$chooseModesButton = [System.Windows.Forms.Button]::new()
$chooseModesButton.Text = 'Choose...'
$chooseModesButton.Location = [System.Drawing.Point]::new(303, 189)
$chooseModesButton.Size = [System.Drawing.Size]::new(76, 25)
$form.Controls.Add($chooseModesButton)

$form.Controls.Add((New-Label 'Resolution' 400 190 72))
$resolutionBox = [System.Windows.Forms.ComboBox]::new()
$resolutionBox.Location = [System.Drawing.Point]::new(475, 190)
$resolutionBox.Size = [System.Drawing.Size]::new(100, 23)
$resolutionBox.DropDownStyle = 'DropDownList'
[void]$resolutionBox.Items.AddRange([string[]]@('256', '512', '1024', '2048', '4096'))
$resolutionBox.SelectedItem = '1024'
$form.Controls.Add($resolutionBox)

$gridBox = [System.Windows.Forms.CheckBox]::new()
$gridBox.Text = 'Draw grid'
$gridBox.Location = [System.Drawing.Point]::new(125, 225)
$gridBox.AutoSize = $true
$form.Controls.Add($gridBox)

$wholeBox = [System.Windows.Forms.CheckBox]::new()
$wholeBox.Text = 'Create one whole atlas image'
$wholeBox.Location = [System.Drawing.Point]::new(225, 225)
$wholeBox.AutoSize = $true
$form.Controls.Add($wholeBox)

$toolTip = [System.Windows.Forms.ToolTip]::new()
$toolTip.AutoPopDelay = 30000
$toolTip.InitialDelay = 250
$toolTip.ReshowDelay = 100
$toolTip.SetToolTip($seedBox, 'Your Valheim world seed. Separate several seeds with commas to make one job per seed.')
$toolTip.SetToolTip($tagBox, "Optional short name added to the image file name and caption, for example more-lakes.`nHandy for comparing the same seed with different settings.")
$toolTip.SetToolTip($wholeBox, 'Whole atlas needs World count 1 or more. Exact seed mode (-1) is not supported by AtlasBuilder for this output.')
$wholeBox.Add_CheckedChanged({
    if ($wholeBox.Checked -and $countBox.Value -lt 1) {
        $countBox.Value = 1
        $status.Text = 'Whole atlas uses a positive world count.'
    }
    $countBox.Minimum = if ($wholeBox.Checked) { 1 } else { -1 }
})

$form.Controls.Add((New-Label 'Preset' 420 223 48))
$presetBox = [System.Windows.Forms.ComboBox]::new()
$presetBox.Location = [System.Drawing.Point]::new(469, 222)
$presetBox.Size = [System.Drawing.Size]::new(173, 23)
$presetBox.DropDownStyle = 'DropDownList'
[void]$presetBox.Items.AddRange($presetNames)
$presetBox.SelectedItem = 'Default'
$form.Controls.Add($presetBox)

$presetInfo = [System.Windows.Forms.Label]::new()
$presetInfo.Location = [System.Drawing.Point]::new(420, 248)
$presetInfo.Size = [System.Drawing.Size]::new(222, 36)
$presetInfo.ForeColor = [System.Drawing.Color]::DimGray
$presetInfo.Font = [System.Drawing.Font]::new('Segoe UI', 8)
$form.Controls.Add($presetInfo)
$toolTip.SetToolTip($presetBox, (@($presetDescriptions.Keys | ForEach-Object { "$_ - $($presetDescriptions[$_])" }) -join "`n"))
$presetBox.Add_SelectedIndexChanged({ Update-PresetInfo })

$stampBox = [System.Windows.Forms.CheckBox]::new()
$stampBox.Text = 'Stamp seed and settings under each map'
$stampBox.Location = [System.Drawing.Point]::new(125, 256)
$stampBox.AutoSize = $true
$stampBox.Checked = $true
$form.Controls.Add($stampBox)
$toolTip.SetToolTip($stampBox, 'Adds a caption strip below each map image with the seed, map mode, preset and world settings, so the image explains itself when shared.')

$worldCheck = [System.Windows.Forms.CheckBox]::new()
$worldCheck.Text = 'Custom world settings'
$worldCheck.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 9.5)
$worldCheck.Location = [System.Drawing.Point]::new(18, 294)
$worldCheck.AutoSize = $true
$form.Controls.Add($worldCheck)
$toolTip.SetToolTip($worldCheck, 'Draw maps with your own world size, river, lake and biome settings, the same ones the Riverheim Config mod uses. See the Settings guide.')

$worldSummary = [System.Windows.Forms.Label]::new()
$worldSummary.Location = [System.Drawing.Point]::new(190, 292)
$worldSummary.Size = [System.Drawing.Size]::new(140, 23)
$worldSummary.AutoEllipsis = $true
$worldSummary.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$worldSummary.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($worldSummary)

$importButton = [System.Windows.Forms.Button]::new()
$importButton.Text = 'Import config...'
$importButton.Location = [System.Drawing.Point]::new(452, 291)
$importButton.Size = [System.Drawing.Size]::new(104, 25)
$form.Controls.Add($importButton)

$exportButton = [System.Windows.Forms.Button]::new()
$exportButton.Text = 'Export config...'
$exportButton.Location = [System.Drawing.Point]::new(338, 291)
$exportButton.Size = [System.Drawing.Size]::new(106, 25)
$form.Controls.Add($exportButton)
$toolTip.SetToolTip($exportButton, "Save these world settings as a Riverheim Config mod file (com.valheim.riverheim.config.cfg)`nfor your server or profile. An existing file is backed up first.")
$toolTip.SetToolTip($importButton, "Fill these fields from a Riverheim Config mod file (com.valheim.riverheim.config.cfg),`nso maps match your server. Also reads expand_world_size.cfg from the same folder.")

$resetButton = [System.Windows.Forms.Button]::new()
$resetButton.Text = 'Reset'
$resetButton.Location = [System.Drawing.Point]::new(564, 291)
$resetButton.Size = [System.Drawing.Size]::new(78, 25)
$form.Controls.Add($resetButton)
$toolTip.SetToolTip($resetButton, 'Put every world setting back to the Riverheim default.')

$settingsPanel = [System.Windows.Forms.Panel]::new()
$settingsPanel.Location = [System.Drawing.Point]::new(18, 324)
$settingsPanel.Size = [System.Drawing.Size]::new(624, 686)
$settingsPanel.Anchor = 'Top, Bottom, Left'
$settingsPanel.AutoScroll = $true
$settingsPanel.BorderStyle = 'FixedSingle'
$settingsPanel.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($settingsPanel)

# Riverheim engine row, under the AtlasBuilder row: everything placed below it moves down one row.
$engineRowShift = 34
foreach ($control in @($form.Controls)) {
    if ($control.Left -lt 660 -and $control.Top -ge 110) {
        $control.Top += $engineRowShift
        if ($control -eq $settingsPanel) { $control.Height -= $engineRowShift }
    }
}
$form.Controls.Add((New-Label 'Riverheim' 18 112))
$engineBox = [System.Windows.Forms.ComboBox]::new()
$engineBox.Location = [System.Drawing.Point]::new(125, 112)
$engineBox.Size = [System.Drawing.Size]::new(200, 23)
$engineBox.DropDownStyle = 'DropDownList'
[void]$engineBox.Items.AddRange([string[]]@($engineInstalledText, $engineBundledText))
$engineBox.SelectedItem = $engineBundledText
$form.Controls.Add($engineBox)

$engineInfo = [System.Windows.Forms.Label]::new()
$engineInfo.Location = [System.Drawing.Point]::new(331, 112)
$engineInfo.Size = [System.Drawing.Size]::new(228, 23)
$engineInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$engineInfo.AutoEllipsis = $true
$engineInfo.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($engineInfo)

$browseEngine = [System.Windows.Forms.Button]::new()
$browseEngine.Text = 'Find...'
$browseEngine.Location = [System.Drawing.Point]::new(564, 111)
$browseEngine.Size = [System.Drawing.Size]::new(78, 25)
$form.Controls.Add($browseEngine)
$engineTip = "Which Riverheim draws the map.`n`n" + (Format-TipText 'Installed: the Riverheim mod in this profile, the same one your game runs, so the map matches your world. The first map takes about half a minute longer while the launcher prepares it; after that it is as fast as before.') + "`n`n" + (Format-TipText 'Bundled: the older Riverheim inside AtlasBuilder 1.0.0. Coastlines, poles and biome edges can differ from your game.')
foreach ($target in @($engineBox, $engineInfo)) { $toolTip.SetToolTip($target, $engineTip) }
$toolTip.SetToolTip($browseEngine, "Point the launcher at a Riverheim.dll (for example from another profile),`nor at your Valheim folder if it was not found.")

# Search row between the custom world settings row and the settings list, so it stays in view while the list scrolls.
$settingsPanel.Top += 34
$settingsPanel.Height -= 34
$searchY = $settingsPanel.Top - 32
$form.Controls.Add((New-Label 'Find setting' 18 $searchY))
$settingsSearch = [System.Windows.Forms.TextBox]::new()
$settingsSearch.Location = [System.Drawing.Point]::new(125, $searchY)
$settingsSearch.Size = [System.Drawing.Size]::new(250, 23)
$form.Controls.Add($settingsSearch)
$settingsSearchInfo = New-Label '' 383 $searchY 175
$settingsSearchInfo.ForeColor = [System.Drawing.Color]::DimGray
$settingsSearchInfo.AutoEllipsis = $true
$form.Controls.Add($settingsSearchInfo)
$clearSearchButton = [System.Windows.Forms.Button]::new()
$clearSearchButton.Text = 'Clear'
$clearSearchButton.Location = [System.Drawing.Point]::new(564, $searchY - 1)
$clearSearchButton.Size = [System.Drawing.Size]::new(78, 25)
$form.Controls.Add($clearSearchButton)
$toolTip.SetToolTip($settingsSearch, "Type part of a setting's name, its name in the config file (for example LandCohesion),`nor a word from its description, such as island, river or snow. Esc clears it.")

$fieldFont = [System.Drawing.Font]::new('Segoe UI', 9)
$fieldFontChanged = [System.Drawing.Font]::new('Segoe UI Semibold', 9)
$groupFont = [System.Drawing.Font]::new('Segoe UI Semibold', 9.5)
$rowY = 8
$column = 0
$currentGroup = ''
$groupHeaders = @{}
foreach ($field in $worldFields) {
    if ($field.Group -ne $currentGroup) {
        if ($column -eq 1) { $rowY += 28; $column = 0 }
        if ($currentGroup) { $rowY += 6 }
        $header = New-Label $field.Group 8 $rowY 580
        $header.Font = $groupFont
        $settingsPanel.Controls.Add($header)
        $groupHeaders[$field.Group] = $header
        $rowY += 26
        $currentGroup = $field.Group
    }
    $fieldX = if ($column -eq 0) { 12 } else { 306 }
    $fieldLabel = New-Label $field.Label $fieldX $rowY 150
    $fieldLabel.Font = $fieldFont
    $settingsPanel.Controls.Add($fieldLabel)

    $numberBox = [System.Windows.Forms.NumericUpDown]::new()
    $numberBox.Location = [System.Drawing.Point]::new($fieldX + 152, $rowY)
    $numberBox.Size = [System.Drawing.Size]::new(112, 23)
    $numberBox.Minimum = [decimal]$field.Min
    $numberBox.Maximum = [decimal]$field.Max
    $numberBox.DecimalPlaces = $field.Decimals
    $numberBox.Increment = [decimal]$field.Step
    $numberBox.Value = [decimal]$field.Default
    $numberBox.TextAlign = 'Right'
    $numberBox.Enabled = $false
    $numberBox.Add_ValueChanged({ Update-WorldSettingsSummary })
    $settingsPanel.Controls.Add($numberBox)

    $helpIcon = New-Label '?' ($fieldX + 267) $rowY 16
    $helpIcon.Font = $groupFont
    $helpIcon.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $helpIcon.Cursor = [System.Windows.Forms.Cursors]::Help
    $settingsPanel.Controls.Add($helpIcon)

    $tip = "$($field.Label)`n$(Format-TipText $field.Tip)`nDefault: $($field.Default)"
    foreach ($target in @($fieldLabel, $numberBox, $helpIcon) + @($numberBox.Controls)) { $toolTip.SetToolTip($target, $tip) }
    $field | Add-Member -NotePropertyName Input -NotePropertyValue $numberBox
    $field | Add-Member -NotePropertyName LabelControl -NotePropertyValue $fieldLabel
    $field | Add-Member -NotePropertyName HelpControl -NotePropertyValue $helpIcon
    if ($column -eq 0) { $column = 1 } else { $column = 0; $rowY += 28 }
}
if ($column -eq 1) { $rowY += 28 }
$rowY += 6
# Bigger worlds: Riverheim World radius stays 10500 and Expand World Size stretches the whole world.
$ewsHeader = New-Label 'World size: set it here (Expand World Size stretching)' 8 $rowY 580
$ewsHeader.Font = $groupFont
$settingsPanel.Controls.Add($ewsHeader)
$rowY += 26

$worldSizeLabel = New-Label 'In-game radius (m)' 12 $rowY 150
$worldSizeLabel.Font = $fieldFont
$settingsPanel.Controls.Add($worldSizeLabel)
$worldSizeBox = [System.Windows.Forms.NumericUpDown]::new()
$worldSizeBox.Location = [System.Drawing.Point]::new(164, $rowY)
$worldSizeBox.Size = [System.Drawing.Size]::new(112, 23)
$worldSizeBox.Minimum = 1050
$worldSizeBox.Maximum = 105000
$worldSizeBox.DecimalPlaces = 0
$worldSizeBox.Increment = 500
$worldSizeBox.Value = 10500
$worldSizeBox.TextAlign = 'Right'
$settingsPanel.Controls.Add($worldSizeBox)

$ewsLabel = New-Label 'EWS stretch' 306 $rowY 150
$ewsLabel.Font = $fieldFont
$settingsPanel.Controls.Add($ewsLabel)
$ewsStretchBox = [System.Windows.Forms.NumericUpDown]::new()
$ewsStretchBox.Location = [System.Drawing.Point]::new(458, $rowY)
$ewsStretchBox.Size = [System.Drawing.Size]::new(112, 23)
$ewsStretchBox.Minimum = [decimal]0.1
$ewsStretchBox.Maximum = 10
$ewsStretchBox.DecimalPlaces = 3
$ewsStretchBox.Increment = [decimal]0.05
$ewsStretchBox.Value = 1
$ewsStretchBox.TextAlign = 'Right'
$settingsPanel.Controls.Add($ewsStretchBox)
$worldSizeBox.Add_ValueChanged({ Sync-WorldSize -From 'Size' })
$ewsStretchBox.Add_ValueChanged({ Sync-WorldSize -From 'Stretch' })

$worldSizeTip = "In-game radius (m)`n" + (Format-TipText 'The world size you want in game, bigger or smaller than normal. This is the place to set the world size. A normal world is 10500 (EWS World radius 10000 + World edge size 500). Linked to EWS stretch: changing one updates the other. Riverheim World radius should stay at 10500 so that Expand World Size does the enlarging. The map picture looks the same at any size; this only changes the caption and the EWS settings to copy.') + "`nDefault: 10500"
$ewsTip = "EWS stretch`n" + (Format-TipText 'The Stretch world and Stretch biomes values for Expand World Size (Riverheim needs them to be equal). Linked to In-game radius: stretch = radius / 10500. Stretching scales the whole normal world up, so the map picture stays the same and only the in-game size changes.') + "`nDefault: 1"
$helpSpecs = @(
    [pscustomobject]@{ Targets = @($worldSizeLabel, $worldSizeBox) + @($worldSizeBox.Controls); Tip = $worldSizeTip; X = 279 }
    [pscustomobject]@{ Targets = @($ewsLabel, $ewsStretchBox) + @($ewsStretchBox.Controls); Tip = $ewsTip; X = 573 }
)
foreach ($helpSpec in $helpSpecs) {
    $helpIcon = New-Label '?' $helpSpec.X $rowY 16
    $helpIcon.Font = $groupFont
    $helpIcon.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $helpIcon.Cursor = [System.Windows.Forms.Cursors]::Help
    $settingsPanel.Controls.Add($helpIcon)
    foreach ($target in @($helpSpec.Targets) + @($helpIcon)) { $toolTip.SetToolTip($target, $helpSpec.Tip) }
}
$rowY += 28

$ewsInfo = New-Label '' 12 $rowY 400
$ewsInfo.ForeColor = [System.Drawing.Color]::DimGray
$ewsInfo.AutoEllipsis = $true
$settingsPanel.Controls.Add($ewsInfo)
$copyEwsButton = [System.Windows.Forms.Button]::new()
$copyEwsButton.Text = 'Copy EWS settings'
$copyEwsButton.Location = [System.Drawing.Point]::new(416, $rowY - 1)
$copyEwsButton.Size = [System.Drawing.Size]::new(176, 25)
$settingsPanel.Controls.Add($copyEwsButton)
$toolTip.SetToolTip($copyEwsButton, "Copy the four matching lines for the [1. General] section of expand_world_size.cfg.`nThe launcher never changes that file itself.")
$rowY += 28

$radiusAdvice = New-Label '' 12 $rowY 400
$radiusAdvice.ForeColor = [System.Drawing.Color]::Firebrick
$radiusAdvice.AutoEllipsis = $true
$settingsPanel.Controls.Add($radiusAdvice)
$fixRadiusButton = [System.Windows.Forms.Button]::new()
$fixRadiusButton.Location = [System.Drawing.Point]::new(416, $rowY - 1)
$fixRadiusButton.Size = [System.Drawing.Size]::new(176, 25)
$fixRadiusButton.Visible = $false
$settingsPanel.Controls.Add($fixRadiusButton)

# The world size section moves as a block under whatever settings the search shows.
$ewsItems = @(foreach ($control in @($settingsPanel.Controls)) {
    if ($control.Top -ge $ewsHeader.Top) { [pscustomobject]@{ Control = $control; Offset = $control.Top - $ewsHeader.Top } }
})
$ewsSearchText = 'world size in-game radius expand world size ews stretch bigger smaller copy'

function Update-SettingsFilter {
    # Shows only the settings whose name, config key, description or section contains every typed word,
    # packed into the same two-column layout as the full list.
    $words = @($settingsSearch.Text.Trim().ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    $settingsPanel.SuspendLayout()
    try {
        $settingsPanel.AutoScrollPosition = [System.Drawing.Point]::new(0, 0)
        foreach ($header in $groupHeaders.Values) { $header.Visible = $false }
        $y = 8
        $col = 0
        $group = ''
        $shown = 0
        foreach ($field in $worldFields) {
            $text = "$($field.Label) $($field.Key) $($field.Tip) $($field.Group)".ToLowerInvariant()
            $match = $true
            foreach ($word in $words) { if (-not $text.Contains($word)) { $match = $false; break } }
            foreach ($control in @($field.LabelControl, $field.Input, $field.HelpControl)) { $control.Visible = $match }
            if (-not $match) { continue }
            $shown++
            if ($field.Group -ne $group) {
                if ($col -eq 1) { $y += 28; $col = 0 }
                if ($group) { $y += 6 }
                $groupHeaders[$field.Group].Top = $y
                $groupHeaders[$field.Group].Visible = $true
                $y += 26
                $group = $field.Group
            }
            $x = if ($col -eq 0) { 12 } else { 306 }
            $field.LabelControl.Location = [System.Drawing.Point]::new($x, $y)
            $field.Input.Location = [System.Drawing.Point]::new($x + 152, $y)
            $field.HelpControl.Location = [System.Drawing.Point]::new($x + 267, $y)
            if ($col -eq 0) { $col = 1 } else { $col = 0; $y += 28 }
        }
        if ($col -eq 1) { $y += 28 }
        if ($shown -gt 0) { $y += 6 } else { $y = 8 }

        $showEws = $true
        foreach ($word in $words) { if (-not $ewsSearchText.Contains($word)) { $showEws = $false; break } }
        foreach ($item in $ewsItems) {
            $item.Control.Top = $y + $item.Offset
            if ($item.Control -ne $fixRadiusButton) { $item.Control.Visible = $showEws }
        }
        if ($showEws) { Update-WorldSettingsSummary } else { $fixRadiusButton.Visible = $false }
    } finally {
        $settingsPanel.ResumeLayout()
    }
    $settingsSearchInfo.Text = if ($words.Count -eq 0) {
        ''
    } elseif ($shown -eq 0 -and -not $showEws) {
        'No setting matches'
    } else {
        "$shown of $($worldFields.Count) settings" + $(if ($showEws) { ' + world size' } else { '' })
    }
}
$settingsSearch.Add_TextChanged({ Update-SettingsFilter })
$settingsSearch.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $settingsSearch.Text = ''; $_.SuppressKeyPress = $true }
})
$clearSearchButton.Add_Click({ $settingsSearch.Text = ''; [void]$settingsSearch.Focus() })

$runButton = [System.Windows.Forms.Button]::new()
$runButton.Text = 'Generate map'
$runButton.Location = [System.Drawing.Point]::new(18, 1022)
$runButton.Size = [System.Drawing.Size]::new(120, 32)
$runButton.Anchor = 'Bottom, Left'
$runButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$runButton.ForeColor = [System.Drawing.Color]::White
$runButton.FlatStyle = 'Flat'
$form.Controls.Add($runButton)
$toolTip.SetToolTip($runButton, 'Add the current settings to the queue and run everything in it.')

$queueButton = [System.Windows.Forms.Button]::new()
$queueButton.Text = 'Add to queue'
$queueButton.Location = [System.Drawing.Point]::new(146, 1022)
$queueButton.Size = [System.Drawing.Size]::new(110, 32)
$queueButton.Anchor = 'Bottom, Left'
$form.Controls.Add($queueButton)
$toolTip.SetToolTip($queueButton, "Save the current settings as a job (one per seed) without running it.`nChange settings and add more, then use Run queue.")

$openButton = [System.Windows.Forms.Button]::new()
$openButton.Text = 'Open output folder'
$openButton.Location = [System.Drawing.Point]::new(264, 1022)
$openButton.Size = [System.Drawing.Size]::new(130, 32)
$openButton.Anchor = 'Bottom, Left'
$form.Controls.Add($openButton)

$historyButton = [System.Windows.Forms.Button]::new()
$historyButton.Text = 'Map history'
$historyButton.Location = [System.Drawing.Point]::new(402, 1022)
$historyButton.Size = [System.Drawing.Size]::new(95, 32)
$historyButton.Anchor = 'Bottom, Left'
$form.Controls.Add($historyButton)

$guideButton = [System.Windows.Forms.Button]::new()
$guideButton.Text = 'Settings guide'
$guideButton.Location = [System.Drawing.Point]::new(505, 1022)
$guideButton.Size = [System.Drawing.Size]::new(100, 32)
$guideButton.Anchor = 'Bottom, Left'
$form.Controls.Add($guideButton)

$status = [System.Windows.Forms.Label]::new()
$status.Text = 'Ready'
$status.Location = [System.Drawing.Point]::new(18, 1062)
$status.Size = [System.Drawing.Size]::new(624, 23)
$status.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$status.AutoEllipsis = $true
$status.Anchor = 'Bottom, Left'
$form.Controls.Add($status)

$bottomTabs = [System.Windows.Forms.TabControl]::new()
$bottomTabs.Location = [System.Drawing.Point]::new(18, 1088)
$bottomTabs.Size = [System.Drawing.Size]::new(624, 230)
$bottomTabs.Anchor = 'Bottom, Left'
$form.Controls.Add($bottomTabs)

$queuePage = [System.Windows.Forms.TabPage]::new()
$queuePage.Text = 'Queue'
[void]$bottomTabs.TabPages.Add($queuePage)
$logPage = [System.Windows.Forms.TabPage]::new()
$logPage.Text = 'Log'
[void]$bottomTabs.TabPages.Add($logPage)

$queueList = [System.Windows.Forms.ListView]::new()
$queueList.Location = [System.Drawing.Point]::new(4, 4)
$queueList.Size = [System.Drawing.Size]::new(606, 158)
$queueList.View = 'Details'
$queueList.FullRowSelect = $true
$queueList.HideSelection = $false
$queueList.MultiSelect = $true
foreach ($queueColumn in @(@('#', 30), @('Seed', 90), @('Tag', 90), @('Modes', 115), @('Size', 50), @('Settings', 110), @('Status', 95))) {
    [void]$queueList.Columns.Add($queueColumn[0], $queueColumn[1])
}
$queuePage.Controls.Add($queueList)

$runQueueButton = [System.Windows.Forms.Button]::new()
$runQueueButton.Text = 'Run queue'
$runQueueButton.Location = [System.Drawing.Point]::new(4, 168)
$runQueueButton.Size = [System.Drawing.Size]::new(90, 28)
$queuePage.Controls.Add($runQueueButton)
$toolTip.SetToolTip($runQueueButton, 'Run every pending job, one map at a time.')

$stopQueueButton = [System.Windows.Forms.Button]::new()
$stopQueueButton.Text = 'Stop'
$stopQueueButton.Location = [System.Drawing.Point]::new(100, 168)
$stopQueueButton.Size = [System.Drawing.Size]::new(70, 28)
$stopQueueButton.Enabled = $false
$queuePage.Controls.Add($stopQueueButton)
$toolTip.SetToolTip($stopQueueButton, 'Stop after the map that is generating now. Jobs that have not started stay pending.')

$removeJobButton = [System.Windows.Forms.Button]::new()
$removeJobButton.Text = 'Remove'
$removeJobButton.Location = [System.Drawing.Point]::new(176, 168)
$removeJobButton.Size = [System.Drawing.Size]::new(80, 28)
$queuePage.Controls.Add($removeJobButton)
$toolTip.SetToolTip($removeJobButton, 'Remove the selected jobs. The running job cannot be removed.')

$clearDoneButton = [System.Windows.Forms.Button]::new()
$clearDoneButton.Text = 'Clear finished'
$clearDoneButton.Location = [System.Drawing.Point]::new(262, 168)
$clearDoneButton.Size = [System.Drawing.Size]::new(105, 28)
$queuePage.Controls.Add($clearDoneButton)
$toolTip.SetToolTip($clearDoneButton, 'Remove jobs that are done, failed or stopped.')

$queueSummary = New-Label '' 375 170 235
$queueSummary.ForeColor = [System.Drawing.Color]::DimGray
$queuePage.Controls.Add($queueSummary)

$logBox = [System.Windows.Forms.TextBox]::new()
$logBox.Dock = 'Fill'
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.BackColor = [System.Drawing.Color]::White
$logBox.Font = [System.Drawing.Font]::new('Cascadia Mono', 9)
$logPage.Controls.Add($logBox)

$previewTitle = [System.Windows.Forms.Label]::new()
$previewTitle.Text = 'Maps (newest first)'
$previewTitle.Location = [System.Drawing.Point]::new(680, 18)
$previewTitle.AutoSize = $true
$previewTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 9)
$form.Controls.Add($previewTitle)

$mainPreview = [System.Windows.Forms.PictureBox]::new()
$mainPreview.Location = [System.Drawing.Point]::new(680, 42)
$mainPreview.Size = [System.Drawing.Size]::new(702, 1240)
$mainPreview.BorderStyle = 'FixedSingle'
$mainPreview.SizeMode = 'Zoom'
$mainPreview.BackColor = [System.Drawing.Color]::FromArgb(236, 238, 241)
$mainPreview.Anchor = 'Top, Bottom, Left, Right'
$form.Controls.Add($mainPreview)

$previewInfo = [System.Windows.Forms.Label]::new()
$previewInfo.Text = 'No map selected'
$previewInfo.Location = [System.Drawing.Point]::new(764, 1292)
$previewInfo.Size = [System.Drawing.Size]::new(528, 23)
$previewInfo.AutoEllipsis = $true
$previewInfo.Anchor = 'Bottom, Left, Right'
$form.Controls.Add($previewInfo)

$openPreviewButton = [System.Windows.Forms.Button]::new()
$openPreviewButton.Text = 'Open'
$openPreviewButton.Location = [System.Drawing.Point]::new(1302, 1289)
$openPreviewButton.Size = [System.Drawing.Size]::new(80, 28)
$openPreviewButton.Anchor = 'Bottom, Right'
$openPreviewButton.Enabled = $false
$form.Controls.Add($openPreviewButton)

$newerButton = [System.Windows.Forms.Button]::new()
$newerButton.Text = '<'
$newerButton.Location = [System.Drawing.Point]::new(680, 1289)
$newerButton.Size = [System.Drawing.Size]::new(36, 28)
$newerButton.Anchor = 'Bottom, Left'
$newerButton.Enabled = $false
$form.Controls.Add($newerButton)
$toolTip.SetToolTip($newerButton, 'Newer map')

$olderButton = [System.Windows.Forms.Button]::new()
$olderButton.Text = '>'
$olderButton.Location = [System.Drawing.Point]::new(720, 1289)
$olderButton.Size = [System.Drawing.Size]::new(36, 28)
$olderButton.Anchor = 'Bottom, Left'
$olderButton.Enabled = $false
$form.Controls.Add($olderButton)
$toolTip.SetToolTip($olderButton, 'Older map')

$appendLog = {
    param([string]$Text)
    if ($Text) { $logBox.AppendText($Text + [Environment]::NewLine) }
}

$script:engineSources = $null
function Update-EngineInfo {
    # Finds the installed Riverheim, BepInEx and Valheim again and shows the result next to the engine choice.
    $script:engineSources = Get-EngineSources -AtlasExe $exeBox.Text.Trim()
    $sources = $script:engineSources
    $installed = $engineBox.SelectedItem -eq $engineInstalledText
    if ($sources.Missing.Count -eq 0) {
        $engineInfo.Text = "Riverheim $($sources.Version) found"
        $engineInfo.ForeColor = if ($installed) { [System.Drawing.Color]::FromArgb(16, 124, 16) } else { [System.Drawing.Color]::DimGray }
        $detail = "Riverheim $($sources.Version): $($sources.RiverheimDll)`nBepInEx: $($sources.BepInExCore)`nValheim: $($sources.ValheimDir)"
    } else {
        $engineInfo.Text = switch ($sources.Missing[0]) {
            'Riverheim' { 'Riverheim mod not found' }
            'BepInEx' { 'BepInEx not found' }
            default { 'Valheim folder not found' }
        }
        $engineInfo.ForeColor = if ($installed) { [System.Drawing.Color]::Firebrick } else { [System.Drawing.Color]::DimGray }
        $detail = switch ($sources.Missing[0]) {
            'Riverheim' { 'The Riverheim mod was not found next to AtlasBuilder. Click Find... and choose Riverheim.dll from the profile you play with (BepInEx\plugins\Gurebu-Riverheim).' }
            'BepInEx' { "BepInEx\core was not found above $($sources.RiverheimDll). Click Find... and choose the Riverheim.dll inside a Thunderstore or r2modman profile." }
            default { 'Your Valheim install was not found. Click Find... and choose the folder that holds valheim.exe (in Steam: right-click Valheim, Manage, Browse local files).' }
        }
    }
    $toolTip.SetToolTip($engineInfo, $detail)
}

$engineBox.Add_SelectedIndexChanged({
    Save-LauncherState -Name 'Engine' -Value $(if ($engineBox.SelectedItem -eq $engineInstalledText) { 'Installed' } else { 'Bundled' })
    if ($null -ne $script:engineSources) { Update-EngineInfo }
})

$browseEngine.Add_Click({
    if ($null -eq $script:engineSources) { Update-EngineInfo }
    $sources = $script:engineSources
    if ($sources.RiverheimDll -and $sources.BepInExCore -and -not $sources.ValheimDir) {
        $folderDialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $folderDialog.Description = 'Choose your Valheim folder, the one that holds valheim.exe (in Steam: right-click Valheim > Manage > Browse local files).'
        if ($folderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $chosen = $folderDialog.SelectedPath
        # Accept a pick of valheim_Data or Managed too.
        foreach ($candidate in @($chosen, (Split-Path -Parent $chosen), (Split-Path -Parent (Split-Path -Parent $chosen)))) {
            if (Test-ValheimDir $candidate) { Save-LauncherState -Name 'ValheimDir' -Value $candidate; break }
        }
        if (-not (Test-ValheimDir (Get-LauncherState).ValheimDir)) {
            [System.Windows.Forms.MessageBox]::Show("That folder does not contain Valheim.`nChoose the folder that holds valheim.exe.", 'Valheim folder', 'OK', 'Warning') | Out-Null
            return
        }
    } else {
        $fileDialog = [System.Windows.Forms.OpenFileDialog]::new()
        $fileDialog.Title = 'Choose Riverheim.dll from the profile you play with (BepInEx\plugins\Gurebu-Riverheim)'
        $fileDialog.Filter = 'Riverheim mod|Riverheim.dll'
        if ($sources.RiverheimDll) { $fileDialog.InitialDirectory = Split-Path -Parent $sources.RiverheimDll }
        if ($fileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        if (-not (Get-RiverheimVersion $fileDialog.FileName)) {
            [System.Windows.Forms.MessageBox]::Show('That file is not the Riverheim mod.', 'Riverheim', 'OK', 'Warning') | Out-Null
            return
        }
        Save-LauncherState -Name 'RiverheimDll' -Value $fileDialog.FileName
    }
    $engineBox.SelectedItem = $engineInstalledText
    Update-EngineInfo
    $status.Text = if ($script:engineSources.Missing.Count -eq 0) { "Maps will be drawn with Riverheim $($script:engineSources.Version)." } else { $engineInfo.Text }
})

function Update-WorldSettingsSummary {
    $changedCount = 0
    foreach ($field in $worldFields) {
        $isChanged = $field.Input.Value -ne [decimal]$field.Default
        if ($isChanged) {
            $changedCount++
            $field.LabelControl.Font = $fieldFontChanged
            $field.LabelControl.ForeColor = [System.Drawing.Color]::FromArgb(0, 95, 184)
        } else {
            $field.LabelControl.Font = $fieldFont
            $field.LabelControl.ForeColor = [System.Drawing.SystemColors]::ControlText
        }
    }
    $worldSummary.Text = if (-not $worldCheck.Checked) {
        'Off'
    } elseif ($changedCount -eq 0) {
        'On: all defaults'
    } else {
        "On: $changedCount changed"
    }

    if ($null -ne $fixRadiusButton) {
        $lines = @(Get-EwsSettingsLines)
        $stretching = [double]$ewsStretchBox.Value -ne 1
        $ewsInfo.Text = if ($stretching) {
            $edgeValue = if ($script:ewsEdge) { [double]$script:ewsEdge } else { 500 }
            $invariant = [System.Globalization.CultureInfo]::InvariantCulture
            'EWS: radius ' + ([double]$worldSizeBox.Value - $edgeValue).ToString($invariant) + ', edge ' + $edgeValue.ToString($invariant) + ', stretch ' + [Math]::Round([double]$worldSizeBox.Value / $defaultWorldRadius, 4).ToString($invariant) + ' (world + biomes)'
        } else {
            'Normal size. Change In-game radius for a bigger or smaller world.'
        }
        $toolTip.SetToolTip($ewsInfo, ($lines -join "`n"))

        $radiusField = $worldFields | Where-Object { $_.Key -eq 'WorldRadius' }
        $riverheimRadius = if ($worldCheck.Checked) { $radiusField.Input.Value } else { [decimal]$defaultWorldRadius }
        if ($riverheimRadius -eq $defaultWorldRadius) {
            $radiusAdvice.Text = ''
            $fixRadiusButton.Visible = $false
        } elseif ($stretching) {
            $radiusAdvice.Text = "World radius is $(Format-SettingValue $riverheimRadius). With EWS stretching it should stay 10500."
            $fixRadiusButton.Text = 'Set World radius to 10500'
            $fixRadiusButton.Visible = $true
        } else {
            $radiusAdvice.Text = "World radius $(Format-SettingValue $riverheimRadius) distorts the layout; EWS stretching keeps it."
            $fixRadiusButton.Text = "Use EWS for $(Format-SettingValue $riverheimRadius) m"
            $fixRadiusButton.Visible = $true
        }
    }
}

function Update-MainPreview {
    param([string]$Directory)
    $script:previewRoot = $Directory
    $script:previewImages = @(Get-AtlasImages -Directory $Directory | Sort-Object LastWriteTimeUtc -Descending)
    Show-PreviewImage -Index 0
}

function Show-PreviewImage {
    param([int]$Index)
    $count = @($script:previewImages).Count
    if ($count -eq 0) {
        if ($null -ne $mainPreview.Image) { $mainPreview.Image.Dispose() }
        $mainPreview.Image = $null
        $previewInfo.Text = 'No generated map found'
        $openPreviewButton.Enabled = $false
        $newerButton.Enabled = $false
        $olderButton.Enabled = $false
        $script:mainPreviewPath = $null
        return
    }
    $Index = [Math]::Max(0, [Math]::Min($Index, $count - 1))
    $script:previewIndex = $Index
    $file = $script:previewImages[$Index]
    $newerButton.Enabled = $Index -gt 0
    $olderButton.Enabled = $Index -lt ($count - 1)
    $script:mainPreviewPath = $file.FullName
    $openPreviewButton.Enabled = $true
    $name = $file.FullName
    $root = if ($script:previewRoot) { $script:previewRoot.TrimEnd('\') + '\' } else { '' }
    if ($root -and $name.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { $name = $name.Substring($root.Length) }
    try {
        $source = [System.Drawing.Image]::FromFile($file.FullName)
        $replacement = [System.Drawing.Bitmap]::new($source)
        $source.Dispose()
        if ($null -ne $mainPreview.Image) { $mainPreview.Image.Dispose() }
        $mainPreview.Image = $replacement
        $previewInfo.Text = "$($Index + 1) of $count   $name"
    } catch {
        $previewInfo.Text = "$($Index + 1) of $count   $name (preview unavailable)"
    }
}

function Update-PresetInfo {
    if ($worldCheck.Checked) {
        $presetInfo.Text = 'Locked to Default: custom world settings build on the Default world.'
    } else {
        $presetInfo.Text = $presetDescriptions[[string]$presetBox.SelectedItem]
    }
}

function Update-ModeSummary {
    if ($script:selectedModes.Count -eq $allMapModes.Count) {
        $modeSummary.Text = 'All 5 modes'
    } elseif ($script:selectedModes.Count -eq 1) {
        $modeSummary.Text = $script:selectedModes[0]
    } else {
        $modeSummary.Text = "$($script:selectedModes.Count) modes selected"
    }
}

function Show-MapModeChooser {
    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = 'Choose Map Modes'
    $dialog.ClientSize = [System.Drawing.Size]::new(280, 290)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $list = [System.Windows.Forms.CheckedListBox]::new()
    $list.Location = [System.Drawing.Point]::new(16, 16)
    $list.Size = [System.Drawing.Size]::new(248, 165)
    $list.CheckOnClick = $true
    [void]$list.Items.AddRange($allMapModes)
    for ($index = 0; $index -lt $list.Items.Count; $index++) {
        $list.SetItemChecked($index, $script:selectedModes -contains $list.Items[$index])
    }
    $dialog.Controls.Add($list)

    $allButton = [System.Windows.Forms.Button]::new()
    $allButton.Text = 'Select all'
    $allButton.Location = [System.Drawing.Point]::new(16, 194)
    $allButton.Size = [System.Drawing.Size]::new(90, 28)
    $dialog.Controls.Add($allButton)

    $clearButton = [System.Windows.Forms.Button]::new()
    $clearButton.Text = 'Clear'
    $clearButton.Location = [System.Drawing.Point]::new(114, 194)
    $clearButton.Size = [System.Drawing.Size]::new(70, 28)
    $dialog.Controls.Add($clearButton)

    $applyButton = [System.Windows.Forms.Button]::new()
    $applyButton.Text = 'Apply'
    $applyButton.Location = [System.Drawing.Point]::new(174, 242)
    $applyButton.Size = [System.Drawing.Size]::new(90, 30)
    $dialog.Controls.Add($applyButton)

    $allButton.Add_Click({ for ($index = 0; $index -lt $list.Items.Count; $index++) { $list.SetItemChecked($index, $true) } })
    $clearButton.Add_Click({ for ($index = 0; $index -lt $list.Items.Count; $index++) { $list.SetItemChecked($index, $false) } })
    $applyButton.Add_Click({
        $selected = @($list.CheckedItems | ForEach-Object { $_.ToString() })
        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Choose at least one map mode.', 'Map mode required', 'OK', 'Warning') | Out-Null
            return
        }
        $script:selectedModes = [string[]]$selected
        Update-ModeSummary
        $dialog.Close()
    })
    [void]$dialog.ShowDialog($form)
}

function Show-SettingsGuide {
    $guide = [System.Windows.Forms.Form]::new()
    $guide.Text = 'AtlasBuilder Settings Guide'
    $guide.ClientSize = [System.Drawing.Size]::new(640, 560)
    $guide.StartPosition = 'CenterParent'
    $guide.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $text = [System.Windows.Forms.TextBox]::new()
    $text.Dock = 'Fill'
    $text.Multiline = $true
    $text.ReadOnly = $true
    $text.ScrollBars = 'Vertical'
    $text.BackColor = [System.Drawing.Color]::White
    $text.Font = [System.Drawing.Font]::new('Segoe UI', 10)
    $text.Text = @'
AtlasBuilder
The Riverheim.AtlasBuilder.exe program used to create maps. Leave this on its detected path unless your Thunderstore profile moved.

Riverheim
Which Riverheim draws the map.
- Installed (matches your game): the Riverheim mod in this profile, the same one your game runs, so maps match your worlds. The launcher finds it next to AtlasBuilder, plus your Valheim install through Steam. The first map with a new Riverheim version takes about half a minute longer while the launcher prepares it; after that it is as fast as before. If your antivirus asks about AtlasBuilder or PowerShell during that first map, allow it.
- Bundled (older, can differ): the Riverheim inside AtlasBuilder 1.0.0. Coastlines, poles and biome edges can differ from your game, and the lowland Black Forest settings do nothing.
The text next to the choice says which Riverheim was found. If it says something was not found, click Find... and pick it: Riverheim.dll (in your profile's BepInEx\plugins\Gurebu-Riverheim), or your Valheim folder (in Steam: right-click Valheim, Manage, Browse local files). Find... also lets you point at the Riverheim.dll of another profile. Every map records which Riverheim drew it, in its caption, its .riverheim.json file and Map history.
How it works: the launcher copies AtlasBuilder's unpacked files to %LocalAppData%\RiverheimAtlasBuilderUI, swaps in your Riverheim.dll and points AtlasBuilder's Default preset at the version Riverheim gives new worlds (using Mono.Cecil, which BepInEx already includes), then starts AtlasBuilder's own exe on those files. Nothing is downloaded, and no game, mod or AtlasBuilder files are changed.

World seed
Your Valheim world seed. With World count set to -1, AtlasBuilder renders this exact seed. Separate several seeds with commas to make one job per seed.

Tag
Optional short name for this run, such as more-lakes. It goes into the file name and the caption.

Map file names
Maps are saved as seed_mode_tag_settings_time, for example 400_Rich_more-lakes_custom-a1b2c3_20260914-213045.png. The settings part is the preset name, or custom- plus a short code that is the same whenever the world settings are the same. Runs never overwrite each other, so the same seed with different settings can sit side by side.

Map modes
Choose one or more render styles. The launcher renders the selected styles one after another with the same seed, placing each style in its own output subfolder so no image is overwritten. Rich is the normal detailed colour view; Landmass focuses on land and water shapes; Biomes visualizes biome regions; RichTerrain emphasizes terrain; Hdr is the tool's high-dynamic-range style.

Resolution
The output size in pixels. Larger values are sharper but need more time and memory.

World count
-1 renders the exact seed once. A positive number renders that many derived seeds. Whole atlas needs a positive count because it combines those generated maps.

Draw grid
Adds a coordinate grid on top of each map image.

Create one whole atlas image
Combines generated maps into one image. It cannot be used with exact-seed mode (-1) in AtlasBuilder 1.0.0.

Preset
The world preset AtlasBuilder generates. Default matches a normal Riverheim world; the others are extra presets built into AtlasBuilder:
- Default: normal Riverheim world, 10.5 km radius.
- Experimental: same world as Default, drawn with the newer Ashlands lava look.
- Mini: small 4 km world with its own simpler landmass layout.
- MiniExp: the Mini world, drawn with the newer Ashlands lava look.
- Token: tiny 2 km world made of a single landmass.
- HugeWorld: huge 25 km world with the poles and landmass layout rescaled to fit.
The preset is locked to Default while custom world settings are on.

Stamp seed and settings under each map
Adds a caption strip below each map image (the map itself is not covered) with the seed, map mode, preset and world settings, so the picture explains itself when shared. Untick it for clean map images.

Custom world settings
Tick this to draw maps with your own world settings: world size and depths, rivers, lakes, biome bias, biome amounts (how much contested land each biome takes), biome bands (how far from spawn each biome appears), landmass shape, mountains, river features, sub-biomes and terrain feel. These are exactly the settings the Riverheim Config mod has (the list comes from the mod's own settings file), and every field starts at the Riverheim 1.2.1 default. A field left at its default leaves Riverheim's own value alone. Changed fields turn blue; hover the blue ? next to a field to see what it does. The lowland Black Forest settings only show with the Installed choice; the Riverheim bundled with AtlasBuilder is too old to have them.
Import config fills the fields from a Riverheim Config mod file (com.valheim.riverheim.config.cfg in your profile's BepInEx\config folder), so maps match your server. Reset puts every field back to its default. Export config saves the fields as a Riverheim Config mod file for your server or profile, backing up any existing file first; restart the game or server to use it.

How custom world settings work: the first time you use them, the launcher builds RiverheimConfigHook.cs together with RiverheimSettings.cs (two small, readable files next to the launcher; the second one is the Riverheim Config mod's own settings table) into a DLL with the C# compiler that ships with Windows, and keeps it in %LocalAppData%\RiverheimAtlasBuilderUI. When generating, it writes your settings to a file in that folder and tells .NET to load the DLL into AtlasBuilder (a .NET startup hook). The hook fills AtlasBuilder's Experimental preset slot with the Default world plus your settings, and the launcher runs that preset. Nothing is downloaded, and no game, mod or AtlasBuilder files are changed.

World size: Expand World Size stretching
This is where you set the world size, bigger or smaller. Keep World radius (in the World group) at 10500 and let Expand World Size stretch the whole world; a stretch below 1 makes it smaller. Set In-game radius or EWS stretch (they are linked: stretch = radius / 10500), then click Copy EWS settings and paste the four lines into the [1. General] section of expand_world_size.cfg. The launcher never edits that file. Stretching scales the whole normal world, so the map picture looks the same and the caption shows the in-game size. If World radius is also changed, a button offers to set it back to 10500, or to move that size into EWS stretching. Import config reads expand_world_size.cfg from the same folder too, and warns about combinations Riverheim does not support.
Why not World radius for a bigger world? World radius changes how far Riverheim itself generates. Biome bands scale with it, but the Ashlands and Deep North poles, the landmass swirl and the rainfall pattern stay fixed in metres (the HugeWorld preset rescales those by hand), so the layout gets distorted. For a bigger world with the normal layout, keep World radius at 10500 and use EWS stretching.

Maps are a preview: AtlasBuilder 1.0.0 bundles an older Riverheim than 1.2, so maps may not match your in-game world exactly, with or without custom world settings. The settings themselves map onto the same Riverheim fields in both.

Maps (newest first)
The large preview shows the maps in the output folder, newest first. Use < and > to step through them, and Open to view one full size.

Generate map, Add to queue and the Queue tab
Add to queue saves everything currently set in the window as a job (one job per seed), so you can change settings and add more. Generate map adds the job and runs the whole queue. The Queue tab lists every job with its settings code and status: Run queue starts the pending jobs, Stop finishes the map that is generating and then stops, Remove deletes the selected jobs, and Clear finished removes done, failed and stopped jobs. If a job fails, the queue carries on with the next one.

Map history
Saved image settings, including custom world settings, are stored beside each image. Filter the thumbnail stack by Map mode or grid state, open a map, or load its settings back into the launcher.
'@
    $guide.Controls.Add($text)
    [void]$guide.ShowDialog($form)
}

# Queue state. Each job is one seed with a snapshot of the window's settings; each job runs one map per mode.
$script:jobs = [System.Collections.Generic.List[object]]::new()
$script:jobCounter = 0
$script:queueRunning = $false
$script:stopRequested = $false
$script:currentJob = $null
$script:modeQueue = [System.Collections.Generic.Queue[string]]::new()

$completionTimer = [System.Windows.Forms.Timer]::new()
$completionTimer.Interval = 500
$completionTimer.Add_Tick({
    $process = $script:activeProcess
    if ($null -eq $process -or -not $process.HasExited) { return }

    $completionTimer.Stop()
    $exitCode = $process.ExitCode
    $script:activeProcess = $null
    $job = $script:currentJob
    if ($exitCode -eq 0) {
        & $appendLog "Finished $($script:activeGeneration.Settings.Mode) for seed $($job.Seed)."
        try {
            $saved = Save-AtlasMetadata -Run $script:activeGeneration
            if ($saved -gt 0) {
                & $appendLog "Saved $saved map(s)."
                Update-MainPreview -Directory $job.OutputPath
            } else {
                & $appendLog 'AtlasBuilder finished, but no JPG or PNG files were found.'
            }
        } catch {
            & $appendLog "Could not save map metadata: $($_.Exception.Message)"
        }
        $job.CompletedModes++
        if ($script:modeQueue.Count -gt 0 -and -not $script:stopRequested) {
            Update-QueueList
            Start-NextGeneration
            return
        }
        $job.Status = if ($script:modeQueue.Count -gt 0) { 'Stopped' } else { 'Done' }
    } else {
        Remove-Item -LiteralPath $script:activeGeneration.IncomingPath -Recurse -Force -ErrorAction SilentlyContinue
        $job.Status = 'Failed'
        & $appendLog "AtlasBuilder stopped with exit code $exitCode for seed $($job.Seed). Check its console window for details."
    }
    $script:modeQueue.Clear()
    Update-QueueList
    Start-NextJob
})

function Update-QueueList {
    $queueList.BeginUpdate()
    $queueList.Items.Clear()
    foreach ($job in $script:jobs) {
        $modeCount = @($job.Modes).Count
        $statusText = if ($job.Status -eq 'Running') { "Running $([Math]::Min($job.CompletedModes + 1, $modeCount))/$modeCount" } else { $job.Status }
        $item = [System.Windows.Forms.ListViewItem]::new([string]$job.Number)
        foreach ($value in @($job.Seed, $job.Tag, (@($job.Modes) -join ', '), $job.Resolution, $job.SettingsId, $statusText)) {
            [void]$item.SubItems.Add([string]$value)
        }
        $item.Tag = $job
        if ($job.Status -eq 'Failed') {
            $item.ForeColor = [System.Drawing.Color]::Firebrick
        } elseif ($job.Status -in 'Done', 'Stopped') {
            $item.ForeColor = [System.Drawing.Color]::DimGray
        } elseif ($job.Status -eq 'Running') {
            $item.Font = $fieldFontChanged
        }
        [void]$queueList.Items.Add($item)
    }
    $queueList.EndUpdate()
    $pending = @($script:jobs | Where-Object { $_.Status -eq 'Pending' }).Count
    $queueSummary.Text = "$pending pending of $($script:jobs.Count) job(s)"
    $runQueueButton.Enabled = (-not $script:queueRunning) -and $pending -gt 0
    $stopQueueButton.Enabled = $script:queueRunning -and -not $script:stopRequested
    $runButton.Enabled = -not $script:queueRunning
}

function Start-Queue {
    if ($script:queueRunning) { return }
    if (@($script:jobs | Where-Object { $_.Status -eq 'Pending' }).Count -eq 0) { return }
    $script:queueRunning = $true
    $script:stopRequested = $false
    $logBox.Clear()
    Start-NextJob
}

function Start-NextJob {
    $next = $null
    if (-not $script:stopRequested) { $next = $script:jobs | Where-Object { $_.Status -eq 'Pending' } | Select-Object -First 1 }
    if ($null -eq $next) {
        $done = @($script:jobs | Where-Object { $_.Status -eq 'Done' }).Count
        $failed = @($script:jobs | Where-Object { $_.Status -eq 'Failed' }).Count
        $status.Text = if ($script:stopRequested) { "Queue stopped: $done done, $failed failed." } else { "Queue finished: $done done, $failed failed." }
        $script:queueRunning = $false
        $script:stopRequested = $false
        $script:currentJob = $null
        Update-QueueList
        return
    }

    $script:currentJob = $next
    $next.Status = 'Running'
    $next.CompletedModes = 0
    $script:modeQueue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($mode in @($next.Modes)) { $script:modeQueue.Enqueue($mode) }
    $tagText = if ($next.Tag) { " ($($next.Tag))" } else { '' }
    & $appendLog "--- Job $($next.Number): seed $($next.Seed)$tagText, $(@($next.Modes).Count) mode(s), settings $($next.SettingsId) ---"
    & $appendLog $(if ($next.Engine) { "Riverheim: installed $($next.Engine.Version)" } else { 'Riverheim: bundled with AtlasBuilder 1.0.0 (older)' })
    if ($next.CustomWorld) {
        $changedText = if (@($next.ChangedSettings).Count -gt 0) { @($next.ChangedSettings) -join ', ' } else { 'none (Riverheim defaults)' }
        & $appendLog "Custom world settings changed: $changedText"
    }
    Update-QueueList
    Start-NextGeneration
}

function Start-NextGeneration {
    if ($script:modeQueue.Count -eq 0) { return }

    $mode = $script:modeQueue.Dequeue()
    $batch = $script:currentJob
    $modeOutputPath = Join-Path $batch.OutputPath $mode
    [void](New-Item -ItemType Directory -Path $modeOutputPath -Force)
    # AtlasBuilder writes into a private folder; Save-AtlasMetadata moves the result into $modeOutputPath under a unique name.
    $incomingPath = Join-Path $hookCacheRoot ('incoming\' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $incomingPath -Force)
    # With custom world settings, the hook fills the Experimental preset slot with Default + those settings.
    $presetArgument = if ($batch.CustomWorld) { 'Experimental' } else { $batch.Preset }
    $arguments = @(
        '--path', (Quote-Argument $incomingPath),
        '--seed', (Quote-Argument $batch.Seed),
        '--mode', $mode,
        '--resolution', $batch.Resolution,
        '--count', $batch.Count,
        '--preset', (Quote-Argument $presetArgument)
    )
    if ($batch.Grid) { $arguments += '--grid' }
    if ($batch.Whole) { $arguments += '--whole' }

    $script:activeGeneration = [pscustomobject]@{
        StartedAtUtc = [DateTime]::UtcNow
        OutputPath = $modeOutputPath
        IncomingPath = $incomingPath
        CaptionDetail = $batch.CaptionDetail
        Settings = [ordered]@{
            Seed = $batch.Seed
            Mode = $mode
            Resolution = [int]$batch.Resolution
            Count = [int]$batch.Count
            Grid = $batch.Grid
            Whole = $batch.Whole
            Preset = $batch.Preset
            Tag = $batch.Tag
            SettingsId = $batch.SettingsId
            CustomWorldSettings = $batch.CustomWorld
            ChangedWorldSettings = $batch.ChangedSettings
            WorldSettings = $batch.WorldSettings
            ExpandWorldSizeStretch = $batch.EwsStretch
            Executable = $batch.Executable
            Engine = if ($batch.Engine) { 'Installed' } else { 'Bundled' }
            RiverheimVersion = if ($batch.Engine) { $batch.Engine.Version } else { 'AtlasBuilder 1.0.0 bundled' }
        }
    }

    $modeCount = @($batch.Modes).Count
    $waiting = @($script:jobs | Where-Object { $_.Status -eq 'Pending' }).Count
    & $appendLog "Running $mode ($($batch.CompletedModes + 1)/$modeCount): $($batch.Executable) $($arguments -join ' ')"
    $status.Text = "Job $($batch.Number): seed $($batch.Seed), $mode ($($batch.CompletedModes + 1) of $modeCount). $waiting job(s) waiting."

    # AtlasBuilder inherits these from the launcher; they are removed again as soon as it has started.
    $environment = @{}
    $hooks = @()
    if ($batch.Engine) {
        $environment['DOTNET_BUNDLE_EXTRACT_BASE_DIR'] = $batch.Engine.ExtractRoot
        $environment['RIVERHEIM_DEPS_DIR'] = $batch.Engine.DepsDirs
        $hooks += $batch.Engine.DepsHook
    }
    if ($batch.CustomWorld) {
        $hooks += $batch.HookPath
        $environment['RIVERHEIM_CONFIG_PATH'] = $batch.SettingsFile
    }
    if ($hooks.Count -gt 0) { $environment['DOTNET_STARTUP_HOOKS'] = $hooks -join ';' }
    try {
        $script:activeProcess = Start-AtlasBuilderProcess -AtlasExe $batch.Executable -Arguments ($arguments -join ' ') -Environment $environment
        $completionTimer.Start()
    } catch {
        Remove-Item -LiteralPath $incomingPath -Recurse -Force -ErrorAction SilentlyContinue
        & $appendLog "ERROR: could not start AtlasBuilder for seed $($batch.Seed): $($_.Exception.Message)"
        $batch.Status = 'Failed'
        $script:modeQueue.Clear()
        Update-QueueList
        Start-NextJob
    }
}

function Show-MapHistory {
    $browser = [System.Windows.Forms.Form]::new()
    $browser.Text = 'Riverheim Map History'
    $browser.ClientSize = [System.Drawing.Size]::new(900, 530)
    $browser.MinimumSize = [System.Drawing.Size]::new(760, 480)
    $browser.StartPosition = 'CenterParent'
    $browser.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $browser.Controls.Add((New-Label 'Map folder' 14 15 70))
    $folderBox = [System.Windows.Forms.TextBox]::new()
    $folderBox.Location = [System.Drawing.Point]::new(88, 15)
    $folderBox.Size = [System.Drawing.Size]::new(620, 23)
    $folderBox.Anchor = 'Top, Left, Right'
    $folderBox.Text = $outputBox.Text.Trim()
    $browser.Controls.Add($folderBox)

    $chooseFolder = [System.Windows.Forms.Button]::new()
    $chooseFolder.Text = 'Browse...'
    $chooseFolder.Location = [System.Drawing.Point]::new(716, 14)
    $chooseFolder.Size = [System.Drawing.Size]::new(78, 25)
    $chooseFolder.Anchor = 'Top, Right'
    $browser.Controls.Add($chooseFolder)

    $refresh = [System.Windows.Forms.Button]::new()
    $refresh.Text = 'Refresh'
    $refresh.Location = [System.Drawing.Point]::new(802, 14)
    $refresh.Size = [System.Drawing.Size]::new(82, 25)
    $refresh.Anchor = 'Top, Right'
    $browser.Controls.Add($refresh)

    $browser.Controls.Add((New-Label 'Mode' 14 50 38))
    $modeFilter = [System.Windows.Forms.ComboBox]::new()
    $modeFilter.Location = [System.Drawing.Point]::new(54, 50)
    $modeFilter.Size = [System.Drawing.Size]::new(126, 23)
    $modeFilter.DropDownStyle = 'DropDownList'
    [void]$modeFilter.Items.AddRange([string[]]@('All modes', 'Rich', 'Landmass', 'Biomes', 'RichTerrain', 'Hdr'))
    $modeFilter.SelectedIndex = 0
    $browser.Controls.Add($modeFilter)

    $browser.Controls.Add((New-Label 'Grid' 200 50 32))
    $gridFilter = [System.Windows.Forms.ComboBox]::new()
    $gridFilter.Location = [System.Drawing.Point]::new(235, 50)
    $gridFilter.Size = [System.Drawing.Size]::new(112, 23)
    $gridFilter.DropDownStyle = 'DropDownList'
    [void]$gridFilter.Items.AddRange([string[]]@('Any grid', 'Grid on', 'Grid off'))
    $gridFilter.SelectedIndex = 0
    $browser.Controls.Add($gridFilter)

    $list = [System.Windows.Forms.ListView]::new()
    $list.Location = [System.Drawing.Point]::new(14, 86)
    $list.Size = [System.Drawing.Size]::new(510, 378)
    $list.Anchor = 'Top, Bottom, Left'
    $list.View = 'Tile'
    $list.TileSize = [System.Drawing.Size]::new(490, 82)
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $thumbnails = [System.Windows.Forms.ImageList]::new()
    $thumbnails.ImageSize = [System.Drawing.Size]::new(96, 64)
    $thumbnails.ColorDepth = 'Depth32Bit'
    $list.LargeImageList = $thumbnails
    $browser.Controls.Add($list)

    $preview = [System.Windows.Forms.PictureBox]::new()
    $preview.Location = [System.Drawing.Point]::new(540, 86)
    $preview.Size = [System.Drawing.Size]::new(344, 230)
    $preview.Anchor = 'Top, Right'
    $preview.BorderStyle = 'FixedSingle'
    $preview.SizeMode = 'Zoom'
    $browser.Controls.Add($preview)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Location = [System.Drawing.Point]::new(540, 326)
    $details.Size = [System.Drawing.Size]::new(344, 138)
    $details.Anchor = 'Top, Bottom, Right'
    $details.ReadOnly = $true
    $details.Multiline = $true
    $details.ScrollBars = 'Vertical'
    $details.BackColor = [System.Drawing.Color]::White
    $browser.Controls.Add($details)

    $load = [System.Windows.Forms.Button]::new()
    $load.Text = 'Load settings'
    $load.Location = [System.Drawing.Point]::new(14, 478)
    $load.Size = [System.Drawing.Size]::new(105, 30)
    $load.Anchor = 'Bottom, Left'
    $browser.Controls.Add($load)

    $openImage = [System.Windows.Forms.Button]::new()
    $openImage.Text = 'Open image'
    $openImage.Location = [System.Drawing.Point]::new(128, 478)
    $openImage.Size = [System.Drawing.Size]::new(95, 30)
    $openImage.Anchor = 'Bottom, Left'
    $browser.Controls.Add($openImage)

    $openFolder = [System.Windows.Forms.Button]::new()
    $openFolder.Text = 'Open folder'
    $openFolder.Location = [System.Drawing.Point]::new(232, 478)
    $openFolder.Size = [System.Drawing.Size]::new(95, 30)
    $openFolder.Anchor = 'Bottom, Left'
    $browser.Controls.Add($openFolder)

    $showSelected = {
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        $imagePath = $record.ImagePath
        if (-not (Test-Path -LiteralPath $imagePath)) { $imagePath = $record.SidecarPath -replace '\.riverheim\.json$', '' }
        $preview.Image = $null
        if (Test-Path -LiteralPath $imagePath) {
            try {
                $source = [System.Drawing.Image]::FromFile($imagePath)
                $preview.Image = [System.Drawing.Bitmap]::new($source)
                $source.Dispose()
            } catch { }
        }
        $settings = $record.Settings
        $worldText = if (-not $settings.CustomWorldSettings) {
            'AtlasBuilder preset'
        } elseif (@($settings.ChangedWorldSettings).Count -gt 0) {
            'Custom: ' + (@($settings.ChangedWorldSettings) -join ', ')
        } else {
            'Custom: all Riverheim defaults'
        }
        $details.Text = "Seed: $($settings.Seed)`r`nMode: $($settings.Mode)`r`nResolution: $($settings.Resolution)`r`nWorld count: $($settings.Count)`r`nGrid: $($settings.Grid)`r`nWhole atlas: $($settings.Whole)`r`nPreset: $($settings.Preset)`r`nTag: $($settings.Tag)`r`nSettings id: $($settings.SettingsId)`r`nWorld settings: $worldText`r`nEWS stretch: $(if ($settings.ExpandWorldSizeStretch) { $settings.ExpandWorldSizeStretch } else { 1 })`r`nRiverheim: $(if ($settings.Engine -eq 'Installed') { "$($settings.RiverheimVersion) (installed)" } else { 'bundled with AtlasBuilder (older)' })`r`nGenerated: $($record.GeneratedAtUtc)"
    }

    $refreshList = {
        $list.Items.Clear()
        $thumbnails.Images.Clear()
        if ($null -ne $preview.Image) { $preview.Image.Dispose(); $preview.Image = $null }
        $details.Clear()
        $folder = $folderBox.Text.Trim()
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return }
        $imageIndex = 0
        Get-ChildItem -LiteralPath $folder -Filter '*.riverheim.json' -File -Recurse | Sort-Object LastWriteTimeUtc -Descending | ForEach-Object {
            try {
                $record = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                $record | Add-Member -NotePropertyName SidecarPath -NotePropertyValue $_.FullName -Force
                if ($modeFilter.SelectedItem -ne 'All modes' -and $record.Settings.Mode -ne $modeFilter.SelectedItem) { return }
                if ($gridFilter.SelectedItem -eq 'Grid on' -and -not [bool]$record.Settings.Grid) { return }
                if ($gridFilter.SelectedItem -eq 'Grid off' -and [bool]$record.Settings.Grid) { return }
                $item = [System.Windows.Forms.ListViewItem]::new([string]$record.ImageFileName)
                $tagText = if ($record.Settings.Tag) { "  |  $($record.Settings.Tag)" } else { '' }
                [void]$item.SubItems.Add("Seed: $($record.Settings.Seed)$tagText")
                $gridText = if ([bool]$record.Settings.Grid) { 'Grid' } else { 'No grid' }
                $worldText = if ($record.Settings.CustomWorldSettings) { ' | Custom world' } else { '' }
                [void]$item.SubItems.Add("$($record.Settings.Mode) | $($record.Settings.Resolution) px | $gridText$worldText")
                $imagePath = $record.ImagePath
                if (-not (Test-Path -LiteralPath $imagePath)) { $imagePath = $_.FullName -replace '\.riverheim\.json$', '' }
                if (Test-Path -LiteralPath $imagePath) {
                    try {
                        $source = [System.Drawing.Image]::FromFile($imagePath)
                        $thumbnail = [System.Drawing.Bitmap]::new($source, 96, 64)
                        $source.Dispose()
                        $key = "image-$imageIndex"
                        $thumbnails.Images.Add($key, $thumbnail)
                        $item.ImageKey = $key
                        $imageIndex++
                    } catch { }
                }
                $item.Tag = $record
                [void]$list.Items.Add($item)
            } catch { }
        }
    }

    $chooseFolder.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        if (Test-Path -LiteralPath $folderBox.Text) { $dialog.SelectedPath = $folderBox.Text }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $folderBox.Text = $dialog.SelectedPath
            & $refreshList
        }
    })
    $refresh.Add_Click($refreshList)
    $modeFilter.Add_SelectedIndexChanged($refreshList)
    $gridFilter.Add_SelectedIndexChanged($refreshList)
    $list.Add_SelectedIndexChanged($showSelected)
    $list.Add_DoubleClick({ & $showSelected; $load.PerformClick() })
    $load.Add_Click({
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        $settings = $record.Settings
        $seedBox.Text = $settings.Seed
        $tagBox.Text = [string]$settings.Tag
        $script:selectedModes = [string[]]@([string]$settings.Mode)
        Update-ModeSummary
        $resolutionBox.SelectedItem = [string]$settings.Resolution
        $countBox.Value = [decimal]$settings.Count
        $gridBox.Checked = [bool]$settings.Grid
        $wholeBox.Checked = [bool]$settings.Whole
        if ($presetNames -contains [string]$settings.Preset) { $presetBox.SelectedItem = [string]$settings.Preset } else { $presetBox.SelectedItem = 'Default' }
        if ($settings.WorldSettings) {
            foreach ($field in $worldFields) {
                $saved = $settings.WorldSettings.($field.Key)
                if ($null -ne $saved) { $field.Input.Value = [Math]::Min([Math]::Max([decimal]$saved, $field.Input.Minimum), $field.Input.Maximum) }
            }
        }
        $savedStretch = if ($settings.ExpandWorldSizeStretch) { [decimal]$settings.ExpandWorldSizeStretch } else { [decimal]1 }
        $ewsStretchBox.Value = [Math]::Min([Math]::Max($savedStretch, $ewsStretchBox.Minimum), $ewsStretchBox.Maximum)
        $worldCheck.Checked = [bool]$settings.CustomWorldSettings
        $outputBox.Text = Split-Path -Parent $record.SidecarPath
        $browser.Close()
    })
    $openImage.Add_Click({
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        if (Test-Path -LiteralPath $record.ImagePath) { Start-Process -FilePath $record.ImagePath }
    })
    $openFolder.Add_Click({
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        Start-Process -FilePath explorer.exe -ArgumentList (Quote-Argument (Split-Path -Parent $record.SidecarPath))
    })
    $browser.Add_FormClosed({
        if ($null -ne $preview.Image) { $preview.Image.Dispose() }
        $thumbnails.Dispose()
    })

    & $refreshList
    [void]$browser.ShowDialog($form)
}

$browseExe.Add_Click({
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Filter = 'AtlasBuilder executable|Riverheim.AtlasBuilder.exe|Executables|*.exe'
    if (Test-Path -LiteralPath $exeBox.Text) { $dialog.InitialDirectory = Split-Path -Parent $exeBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $exeBox.Text = $dialog.FileName
        Update-EngineInfo
    }
})
$exeBox.Add_Leave({ Update-EngineInfo })

$browseOutput.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Choose where generated map images will be saved'
    if (Test-Path -LiteralPath $outputBox.Text) { $dialog.SelectedPath = $outputBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputBox.Text = $dialog.SelectedPath
        Update-MainPreview -Directory $dialog.SelectedPath
    }
})

$worldCheck.Add_CheckedChanged({
    foreach ($field in $worldFields) { $field.Input.Enabled = $worldCheck.Checked }
    $presetBox.Enabled = -not $worldCheck.Checked
    if ($worldCheck.Checked) { $presetBox.SelectedItem = 'Default' }
    Update-WorldSettingsSummary
    Update-PresetInfo
})

$importButton.Add_Click({
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = 'Import Riverheim Config mod settings - pick the profile your server or world uses'
    $dialog.Filter = 'Riverheim Config|com.valheim.riverheim.config.cfg|Config files|*.cfg'
    $found = Find-RiverheimConfig -AtlasExe $exeBox.Text.Trim()
    if ($found) {
        $dialog.InitialDirectory = Split-Path -Parent $found
        $dialog.FileName = Split-Path -Leaf $found
    }
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $applied = Import-WorldSettings -Path $dialog.FileName
        $worldCheck.Checked = $true
        $ewsNotes = @(Import-ExpandWorldSize -Directory (Split-Path -Parent $dialog.FileName))
        Update-WorldSettingsSummary
        $source = if ($dialog.FileName -match '\\profiles\\([^\\]+)\\') { "profile '$($Matches[1])'" } else { Split-Path -Leaf $dialog.FileName }
        $status.Text = "Imported $applied of $($worldFields.Count) settings from $source; $(@(Get-ChangedWorldSettings).Count) differ from the Riverheim defaults."
        if ($ewsNotes.Count -gt 0) {
            $status.Text += ' Also read expand_world_size.cfg.'
            [System.Windows.Forms.MessageBox]::Show(($ewsNotes -join ([Environment]::NewLine * 2)), 'Expand World Size', 'OK', 'Information') | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not read that file.`n$($_.Exception.Message)", 'Import config', 'OK', 'Error') | Out-Null
    }
})

$copyEwsButton.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText(((Get-EwsSettingsLines) -join [Environment]::NewLine))
    $status.Text = 'Copied. Paste over those four lines in the [1. General] section of expand_world_size.cfg.'
})

$fixRadiusButton.Add_Click({
    $radiusField = $worldFields | Where-Object { $_.Key -eq 'WorldRadius' }
    if ($ewsStretchBox.Value -eq 1) {
        # Move the size increase from Riverheim World radius to EWS stretching.
        $worldSizeBox.Value = [Math]::Min([Math]::Max($radiusField.Input.Value, $worldSizeBox.Minimum), $worldSizeBox.Maximum)
    }
    $radiusField.Input.Value = $defaultWorldRadius
    Update-WorldSettingsSummary
    $status.Text = "World radius set to 10500. In-game radius $($worldSizeBox.Value) m comes from EWS stretch $($ewsStretchBox.Value)."
})

$exportButton.Add_Click({
    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Title = 'Export Riverheim Config mod settings - pick the profile your server or world uses'
    $dialog.Filter = 'Riverheim Config|com.valheim.riverheim.config.cfg|Config files|*.cfg'
    $dialog.FileName = 'com.valheim.riverheim.config.cfg'
    $found = Find-RiverheimConfig -AtlasExe $exeBox.Text.Trim()
    if ($found) { $dialog.InitialDirectory = Split-Path -Parent $found }
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $target = $dialog.FileName
        $backupNote = ''
        if (Test-Path -LiteralPath $target) {
            $backup = "$target.backup-$([DateTime]::Now.ToString('yyyyMMdd-HHmmss'))"
            Copy-Item -LiteralPath $target -Destination $backup
            $backupNote = " Old file saved as $(Split-Path -Leaf $backup)."
        }
        Write-WorldSettingsFile -Path $target
        $status.Text = "Exported $($worldFields.Count) settings.$backupNote Restart the game or server to use them."
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not write that file.`n$($_.Exception.Message)", 'Export config', 'OK', 'Error') | Out-Null
    }
})

$resetButton.Add_Click({
    foreach ($field in $worldFields) { $field.Input.Value = [decimal]$field.Default }
    Update-WorldSettingsSummary
    $status.Text = 'World settings reset to Riverheim defaults.'
})

$historyButton.Add_Click({ Show-MapHistory })
$chooseModesButton.Add_Click({ Show-MapModeChooser })
$guideButton.Add_Click({ Show-SettingsGuide })
$newerButton.Add_Click({ Show-PreviewImage -Index ($script:previewIndex - 1) })
$olderButton.Add_Click({ Show-PreviewImage -Index ($script:previewIndex + 1) })
$openPreviewButton.Add_Click({
    if ($script:mainPreviewPath -and (Test-Path -LiteralPath $script:mainPreviewPath)) {
        Start-Process -FilePath $script:mainPreviewPath
    }
})
$form.Add_Shown({
    # Installed Riverheim when it can be found, unless the player chose Bundled last time.
    $script:engineSources = Get-EngineSources -AtlasExe $exeBox.Text.Trim()
    $savedEngine = (Get-LauncherState).Engine
    $engineBox.SelectedItem = if ($savedEngine -ne 'Bundled' -and $script:engineSources.Missing.Count -eq 0) { $engineInstalledText } elseif ($savedEngine -eq 'Installed') { $engineInstalledText } else { $engineBundledText }
    Update-EngineInfo
    Update-MainPreview -Directory $outputBox.Text.Trim()
    Update-WorldSettingsSummary
    Update-PresetInfo
    Update-QueueList
    $missingFiles = @()
    foreach ($required in @($hookSource, $settingsSource, $settingsSchemaPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { $missingFiles += Split-Path -Leaf $required }
    }
    if ($missingFiles.Count -gt 0 -or $settingsSchemaError) {
        $worldCheck.Enabled = $false
        $importButton.Enabled = $false
        $exportButton.Enabled = $false
        $resetButton.Enabled = $false
        $worldSummary.Text = if ($missingFiles.Count -gt 0) { "Missing: $($missingFiles -join ', ')" } else { 'settings.json unreadable' }
        $toolTip.SetToolTip($worldSummary, $(if ($settingsSchemaError) { $settingsSchemaError } else { 'Put all five launcher files in the same folder.' }))
    }
})
$form.Add_FormClosed({ if ($null -ne $mainPreview.Image) { $mainPreview.Image.Dispose() } })

$openButton.Add_Click({
    $path = $outputBox.Text.Trim()
    if (-not $path) { return }
    if (-not (Test-Path -LiteralPath $path)) { [void](New-Item -ItemType Directory -Path $path -Force) }
    Start-Process -FilePath explorer.exe -ArgumentList (Quote-Argument $path)
})

function New-GenerationJobs {
    # Snapshots everything set in the window into one job per seed. Outputs nothing if something is missing.
    $exe = $exeBox.Text.Trim()
    $seeds = @($seedBox.Text -split '[,;\s]+' | Where-Object { $_ })
    $output = $outputBox.Text.Trim()

    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show('Choose the Riverheim.AtlasBuilder.exe file.', 'AtlasBuilder not found', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not (Test-WindowsExecutable $exe)) {
        [System.Windows.Forms.MessageBox]::Show("$exe`n`nis not the Windows version of AtlasBuilder (the package also contains a Linux one, Riverheim.AtlasBuilder without .exe). Choose Riverheim.AtlasBuilder.exe, or reinstall Riverheim_AtlasBuilder from Thunderstore.", 'Not the Windows AtlasBuilder', 'OK', 'Warning') | Out-Null
        return
    }
    if ($seeds.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Enter your Valheim world seed. Separate several seeds with commas.', 'World seed required', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $output) {
        [System.Windows.Forms.MessageBox]::Show('Choose an output folder.', 'Output folder required', 'OK', 'Warning') | Out-Null
        return
    }
    if ($script:selectedModes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Choose at least one map mode.', 'Map mode required', 'OK', 'Warning') | Out-Null
        return
    }
    if ($wholeBox.Checked -and $countBox.Value -lt 1) {
        [System.Windows.Forms.MessageBox]::Show('Whole atlas requires World count 1 or more. AtlasBuilder cannot build it from exact seed mode (-1).', 'Whole atlas requires a count', 'OK', 'Warning') | Out-Null
        return
    }
    if ($worldCheck.Checked) {
        $radiusValue = ($worldFields | Where-Object { $_.Key -eq 'WorldRadius' }).Input.Value
        if ($radiusValue -ge 7800 -and $radiusValue -le 9000) {
            [System.Windows.Forms.MessageBox]::Show("World radius $radiusValue m is refused: from 7800 to 9000 m the world edge runs into the Ashlands and Deep North belts and Riverheim cannot generate the world. Use a radius below 7800 or above 9000 (normally 10500, and Expand World Size for a bigger world).", 'World radius', 'OK', 'Warning') | Out-Null
            return
        }
        foreach ($biome in 'Swamp', 'Plains') {
            $bandStart = ($worldFields | Where-Object { $_.Key -eq "${biome}Start" }).Input.Value
            $bandEnd = ($worldFields | Where-Object { $_.Key -eq "${biome}End" }).Input.Value
            if ($bandEnd -le $bandStart) {
                [System.Windows.Forms.MessageBox]::Show("$biome ends ($bandEnd%) must be higher than $biome starts ($bandStart%).", 'Biome bands', 'OK', 'Warning') | Out-Null
                return
            }
        }
    }

    try { [void](New-Item -ItemType Directory -Path $output -Force) }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not create the output folder.`n$($_.Exception.Message)", 'Output folder error', 'OK', 'Error') | Out-Null
        return
    }

    $engine = $null
    if ($engineBox.SelectedItem -eq $engineInstalledText) {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            if ($null -eq $script:engineSources) { Update-EngineInfo }
            $status.Text = "Preparing Riverheim $($script:engineSources.Version) for AtlasBuilder (first time only, about half a minute). If your antivirus asks about AtlasBuilder or PowerShell, allow it..."
            [System.Windows.Forms.Application]::DoEvents()
            $engine = Get-InstalledEngine -AtlasExe $exe -Sources $script:engineSources
            $status.Text = "Using installed Riverheim $($engine.Version)."
        } catch {
            $status.Text = 'Installed Riverheim is unavailable'
            $answer = [System.Windows.Forms.MessageBox]::Show("The launcher could not use your installed Riverheim.`n`n$($_.Exception.Message)`n`nDraw with the Riverheim bundled with AtlasBuilder instead? Its maps can differ from your game.", 'Installed Riverheim', 'YesNo', 'Warning')
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $engineBox.SelectedItem = $engineBundledText
            $engine = $null
        } finally {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    $customWorld = $worldCheck.Checked
    $settingsId = if ($customWorld) { 'custom-' + (Get-ShortHash (@($worldFields | ForEach-Object { "$($_.Key)=$(Format-SettingValue $_.Input.Value)" }) -join ';')) } else { $presetBox.SelectedItem.ToString() }
    $settingsFile = $null
    $hookPath = $null
    $worldSettings = $null
    $changed = @()
    if ($customWorld) {
        $status.Text = 'Preparing custom world settings...'
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $hookPath = Get-RiverheimConfigHook -AtlasExe $exe -Engine $engine
            # One file per distinct set of settings, so queued jobs with different settings do not overwrite each other.
            $settingsFile = Join-Path $hookCacheRoot "world-settings-$settingsId.cfg"
            Write-WorldSettingsFile -Path $settingsFile
            $worldSettings = Get-WorldSettingsSnapshot
            $changed = @(Get-ChangedWorldSettings)
        } catch {
            $status.Text = 'Custom world settings are unavailable'
            [System.Windows.Forms.MessageBox]::Show("Could not prepare custom world settings.`n`n$($_.Exception.Message)", 'Custom world settings', 'OK', 'Error') | Out-Null
            return
        } finally {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    $captionDetail = $null
    if ($stampBox.Checked) {
        $worldLine = if (-not $customWorld) {
            'World settings: AtlasBuilder preset'
        } elseif ($changed.Count -gt 0) {
            'World settings: ' + ($changed -join ', ')
        } else {
            'World settings: Riverheim defaults'
        }
        $captionDetail = @($worldLine)
        if ($ewsStretchBox.Value -ne 1) {
            $captionRadius = if ($customWorld) { [double]($worldFields | Where-Object { $_.Key -eq 'WorldRadius' }).Input.Value } else { $defaultWorldRadius }
            $captionDetail += 'Expand World Size: {0}x stretch, in-game radius about {1:N0} m' -f (Format-SettingValue $ewsStretchBox.Value), ($captionRadius * [double]$ewsStretchBox.Value)
        }
        $captionDetail += if ($engine) {
            "Drawn with Riverheim $($engine.Version), the Riverheim installed for the game."
        } else {
            'Drawn with the Riverheim bundled with AtlasBuilder 1.0.0, which is older than the mod, so in-game worlds can differ.'
        }
    }

    $tag = ConvertTo-FileTag $tagBox.Text
    foreach ($seed in $seeds) {
        $script:jobCounter++
        [pscustomobject]@{
            Number = $script:jobCounter
            Status = 'Pending'
            CompletedModes = 0
            Modes = [string[]]@($script:selectedModes)
            Executable = $exe
            Seed = $seed
            OutputPath = $output
            Resolution = $resolutionBox.SelectedItem.ToString()
            Count = [int]$countBox.Value
            Grid = $gridBox.Checked
            Whole = $wholeBox.Checked
            Preset = $presetBox.SelectedItem.ToString()
            CustomWorld = $customWorld
            WorldSettings = $worldSettings
            ChangedSettings = $changed
            SettingsFile = $settingsFile
            HookPath = $hookPath
            Engine = $engine
            CaptionDetail = $captionDetail
            EwsStretch = [double]$ewsStretchBox.Value
            Tag = $tag
            SettingsId = $settingsId
        }
    }
}

$queueButton.Add_Click({
    $newJobs = @(New-GenerationJobs)
    if ($newJobs.Count -eq 0) { return }
    foreach ($job in $newJobs) { $script:jobs.Add($job) }
    $bottomTabs.SelectedTab = $queuePage
    Update-QueueList
    $status.Text = "Added $($newJobs.Count) job(s) to the queue."
    if ($script:queueRunning) { $status.Text += ' They run after the current jobs.' }
})

$runButton.Add_Click({
    if ($script:queueRunning) { return }
    $newJobs = @(New-GenerationJobs)
    if ($newJobs.Count -eq 0) { return }
    foreach ($job in $newJobs) { $script:jobs.Add($job) }
    $bottomTabs.SelectedTab = $logPage
    Update-QueueList
    Start-Queue
})

$runQueueButton.Add_Click({ Start-Queue })

$stopQueueButton.Add_Click({
    if (-not $script:queueRunning) { return }
    $script:stopRequested = $true
    $status.Text = 'Stopping after the current map...'
    Update-QueueList
})

$removeJobButton.Add_Click({
    $selectedJobs = @($queueList.SelectedItems | ForEach-Object { $_.Tag } | Where-Object { $_.Status -ne 'Running' })
    foreach ($job in $selectedJobs) { [void]$script:jobs.Remove($job) }
    Update-QueueList
})

$clearDoneButton.Add_Click({
    $finished = @($script:jobs | Where-Object { $_.Status -in 'Done', 'Failed', 'Stopped' })
    foreach ($job in $finished) { [void]$script:jobs.Remove($job) }
    Update-QueueList
})

# Controls are laid out for 1400x1000; shrink the window to fit smaller screens (anchors resize the panels).
$workArea = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
$fitWidth = [Math]::Max($form.MinimumSize.Width, [Math]::Min($form.Width, $workArea.Width - 20))
$fitHeight = [Math]::Max($form.MinimumSize.Height, [Math]::Min($form.Height, $workArea.Height - 20))
$form.Size = [System.Drawing.Size]::new($fitWidth, $fitHeight)

[void]$form.ShowDialog()
