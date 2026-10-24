// Riverheim Config support for Riverheim AtlasBuilder.
//
// .NET loads this compiled file before AtlasBuilder starts, because the
// launcher sets DOTNET_STARTUP_HOOKS. It does one thing: registers a Riverheim
// preset handler (the extension point Riverheim itself uses for its
// Experimental preset) that takes the normal Default world settings and
// applies the world settings from the file named in RIVERHEIM_CONFIG_PATH.
// The launcher writes that file from its Custom world settings fields, in the
// same format as the Riverheim Config mod's config file. It does not modify
// any files.
//
// The settings themselves, and how they map onto Riverheim's configuration,
// come from RiverheimSettings.cs, the same file the Riverheim Config mod is
// built from. The launcher compiles both files together, so the launcher and
// the mod can never disagree about what a setting does.
//
// Written for the C# 5 compiler that ships with Windows (.NET Framework 4.x).
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using Riverheim;
using Riverheim.Configuration;
using Riverheim.Configuration.Extensions;
using RiverheimConfig;

public static class StartupHook
{
    public static void Initialize()
    {
        try
        {
            string path = Environment.GetEnvironmentVariable("RIVERHEIM_CONFIG_PATH");
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                Console.Error.WriteLine("[Custom world settings] No settings file found; using stock Riverheim settings.");
                return;
            }

            Dictionary<string, double> values = RiverheimSettings.Parse(File.ReadAllLines(path));
            // RIVERHEIM_CONFIG_FORCE=1 writes every setting even when it equals the default (used by the test harness
            // to prove that the defaults reproduce a stock world).
            bool force = Environment.GetEnvironmentVariable("RIVERHEIM_CONFIG_FORCE") == "1";
            FieldInfo field = typeof(ConfigManager).GetField("PresetHandlers", BindingFlags.NonPublic | BindingFlags.Static);
            Dictionary<string, IPresetHandler> handlers = (Dictionary<string, IPresetHandler>)field.GetValue(null);
            handlers[ConfigManager.PRESET_EXPERIMENTAL] = new RiverheimConfigPresetHandler(values, force);
            Console.Error.WriteLine("[Custom world settings] Using settings from " + path + " (" + RiverheimSettings.Summary(values) + ")");
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine("[Custom world settings] Could not apply settings, using stock settings: " + exception.Message);
        }
    }
}

internal sealed class RiverheimConfigPresetHandler : IPresetHandler
{
    private readonly Dictionary<string, double> values;
    private readonly bool force;

    public RiverheimConfigPresetHandler(Dictionary<string, double> values, bool force)
    {
        this.values = values;
        this.force = force;
    }

    public string ParentPreset() { return ConfigManager.PRESET_DEFAULT; }

    // Same base as in-game worlds and AtlasBuilder's Default preset.
    public int ParentPresetVersion(int version) { return ConfigManager.PRESET_DEFAULT_VERSION; }

    public int MaxSupportedVersion() { return int.MaxValue; }

    public WorldGenerationConfig GetConfig(int version, WorldGenerationConfig config)
    {
        // WorldGenerationConfig is a struct; RiverheimSettings works on a boxed copy and writes nested structs back.
        object boxed = config;
        List<string> failed = new List<string>();
        List<string> skipped = new List<string>();
        RiverheimSettings.Apply(boxed, values, force, failed, skipped);
        if (skipped.Count > 0)
        {
            Console.Error.WriteLine("[Custom world settings] Not in this AtlasBuilder's Riverheim, so not previewed: " + string.Join(", ", skipped.ToArray()));
        }
        if (failed.Count > 0)
        {
            Console.Error.WriteLine("[Custom world settings] Could not apply: " + string.Join(", ", failed.ToArray()));
        }
        return (WorldGenerationConfig)boxed;
    }
}
