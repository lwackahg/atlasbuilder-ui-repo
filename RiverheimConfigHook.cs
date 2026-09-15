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
// Written for the C# 5 compiler that ships with Windows (.NET Framework 4.x).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using Riverheim;
using Riverheim.Configuration;
using Riverheim.Configuration.Extensions;
using Riverheim.Util;

public static class StartupHook
{
    public static void Initialize()
    {
        try
        {
            string path = Environment.GetEnvironmentVariable("RIVERHEIM_CONFIG_PATH");
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                Console.WriteLine("[Custom world settings] No settings file found; using stock Riverheim settings.");
                return;
            }

            ConfigValues values = ConfigValues.Load(path);
            FieldInfo field = typeof(ConfigManager).GetField("PresetHandlers", BindingFlags.NonPublic | BindingFlags.Static);
            Dictionary<string, IPresetHandler> handlers = (Dictionary<string, IPresetHandler>)field.GetValue(null);
            handlers[ConfigManager.PRESET_EXPERIMENTAL] = new RiverheimConfigPresetHandler(values);
            Console.WriteLine("[Custom world settings] Using settings from " + path);
        }
        catch (Exception exception)
        {
            Console.WriteLine("[Custom world settings] Could not apply settings, using stock settings: " + exception.Message);
        }
    }
}

internal sealed class RiverheimConfigPresetHandler : IPresetHandler
{
    private const string World = "1. World";
    private const string Rivers = "2. Rivers";
    private const string Lakes = "3. Lakes";
    private const string Biomes = "4. Biomes";
    private const string Amounts = "5. Biome Amounts";
    private const string Bands = "6. Biome Bands";

    private readonly ConfigValues values;

    public RiverheimConfigPresetHandler(ConfigValues values)
    {
        this.values = values;
    }

    public string ParentPreset() { return ConfigManager.PRESET_DEFAULT; }

    // Same base as in-game worlds and AtlasBuilder's Default preset.
    public int ParentPresetVersion(int version) { return ConfigManager.PRESET_DEFAULT_VERSION; }

    public int MaxSupportedVersion() { return int.MaxValue; }

    public WorldGenerationConfig GetConfig(int version, WorldGenerationConfig config)
    {
        ConfigValues v = values;
        config.common.worldSize = v.Get(World, "WorldRadius", config.common.worldSize);
        config.common.tileSpacing = v.Get(World, "TileSpacing", config.common.tileSpacing);
        config.common.oceanDepth = v.Get(World, "SeaFloorDepth", config.common.oceanDepth);
        config.world.biomes.conditionalPlacement.main.oceanDepth = v.Get(World, "OceanBiomeDepth", config.world.biomes.conditionalPlacement.main.oceanDepth);
        config.common.mountainHeight = v.Get(World, "MountainHeight", config.common.mountainHeight);
        config.common.startingAreaRadius = v.Get(World, "StartingAreaRadius", config.common.startingAreaRadius);

        config.world.rivers.origins.main.density = v.Get(Rivers, "OriginDensity", config.world.rivers.origins.main.density);
        config.world.rivers.origins.main.minLandNeighbors = v.Get(Rivers, "MinLandNeighbors", config.world.rivers.origins.main.minLandNeighbors);
        config.world.rivers.width.main.scale = v.Get(Rivers, "WidthScale", config.world.rivers.width.main.scale);
        config.world.rivers.width.main.power = v.Get(Rivers, "WidthPower", config.world.rivers.width.main.power);
        config.world.rivers.width.main.offset = v.Get(Rivers, "WidthOffset", config.world.rivers.width.main.offset);
        config.world.rivers.prune.main.minStrahler = v.Get(Rivers, "MinStrahler", config.world.rivers.prune.main.minStrahler);
        config.world.rivers.prune.main.minWidth = v.Get(Rivers, "MinWidth", config.world.rivers.prune.main.minWidth);
        config.world.rivers.prune.main.maxWidthDiff = v.Get(Rivers, "MaxWidthDifference", config.world.rivers.prune.main.maxWidthDiff);
        config.world.rivers.meander.main.period = v.Get(Rivers, "MeanderPeriod", config.world.rivers.meander.main.period);
        config.world.rivers.meander.main.riverAmplitude = v.Get(Rivers, "MeanderAmplitude", config.world.rivers.meander.main.riverAmplitude);

        config.world.height.lakes.main.budget = v.Get(Lakes, "Budget", config.world.height.lakes.main.budget);
        config.world.height.lakes.main.affinity.noiseScale = v.Get(Lakes, "NoiseScale", config.world.height.lakes.main.affinity.noiseScale);
        config.world.height.lakes.main.affinity.kFlatland = v.Get(Lakes, "LowlandContribution", config.world.height.lakes.main.affinity.kFlatland);
        config.world.height.lakes.main.affinity.kCuriosity = v.Get(Lakes, "CuriosityContribution", config.world.height.lakes.main.affinity.kCuriosity);

        config.world.biomes.affinity.main.meadows.bias = v.Get(Biomes, "MeadowsBias", config.world.biomes.affinity.main.meadows.bias);
        config.world.biomes.affinity.main.forest.bias = v.Get(Biomes, "ForestBias", config.world.biomes.affinity.main.forest.bias);
        config.world.biomes.affinity.main.swamp.bias = v.Get(Biomes, "SwampBias", config.world.biomes.affinity.main.swamp.bias);
        config.world.biomes.affinity.main.plains.bias = v.Get(Biomes, "PlainsBias", config.world.biomes.affinity.main.plains.bias);
        config.world.biomes.affinity.main.mistlands.bias = v.Get(Biomes, "MistlandsBias", config.world.biomes.affinity.main.mistlands.bias);

        config.world.biomes.competitivePlacement.main.biomes.meadows.weight = v.Get(Amounts, "MeadowsWeight", config.world.biomes.competitivePlacement.main.biomes.meadows.weight);
        config.world.biomes.competitivePlacement.main.biomes.forest.weight = v.Get(Amounts, "ForestWeight", config.world.biomes.competitivePlacement.main.biomes.forest.weight);
        config.world.biomes.competitivePlacement.main.biomes.swamp.weight = v.Get(Amounts, "SwampWeight", config.world.biomes.competitivePlacement.main.biomes.swamp.weight);
        config.world.biomes.competitivePlacement.main.biomes.plains.weight = v.Get(Amounts, "PlainsWeight", config.world.biomes.competitivePlacement.main.biomes.plains.weight);
        config.world.biomes.competitivePlacement.main.biomes.mistlands.weight = v.Get(Amounts, "MistlandsWeight", config.world.biomes.competitivePlacement.main.biomes.mistlands.weight);

        // Biome bands are relativeTravelDistance curves: (share of the world radius, score) points. With the
        // default percentages these rebuild exactly Riverheim's default curves. Missing values keep the defaults.
        double meadowsFade = v.Get(Bands, "MeadowsFadeEnd", double.NaN) / 100.0;
        if (!double.IsNaN(meadowsFade))
        {
            if (meadowsFade > 0)
                config.world.biomes.affinity.main.meadows.relativeTravelDistance = Curve(0, 0, meadowsFade, -40);
            else
                Console.WriteLine("[Custom world settings] Meadows fade ignored: it must be above 0%.");
        }

        double swampStart = v.Get(Bands, "SwampStart", double.NaN) / 100.0;
        double swampEnd = v.Get(Bands, "SwampEnd", double.NaN) / 100.0;
        if (!double.IsNaN(swampStart) && !double.IsNaN(swampEnd))
        {
            if (swampStart - 0.02 > 0 && swampEnd > swampStart)
                config.world.biomes.affinity.main.swamp.relativeTravelDistance = Curve(0, -1000, Round(swampStart - 0.02), -100, swampStart, 0, swampEnd, 0, Round(swampEnd + 0.02), -100);
            else
                Console.WriteLine("[Custom world settings] Swamp band ignored: it must start above 2% and end after it starts.");
        }

        double plainsStart = v.Get(Bands, "PlainsStart", double.NaN) / 100.0;
        double plainsEnd = v.Get(Bands, "PlainsEnd", double.NaN) / 100.0;
        if (!double.IsNaN(plainsStart) && !double.IsNaN(plainsEnd))
        {
            if (plainsStart - 0.02 > 0 && plainsEnd > plainsStart)
                config.world.biomes.affinity.main.plains.relativeTravelDistance = Curve(0, -1000, Round(plainsStart - 0.02), -100, plainsStart, 0, plainsEnd, 0, Round(plainsEnd + 0.02), -40);
            else
                Console.WriteLine("[Custom world settings] Plains band ignored: it must start above 2% and end after it starts.");
        }

        double mistlandsStart = v.Get(Bands, "MistlandsStart", double.NaN) / 100.0;
        if (!double.IsNaN(mistlandsStart))
        {
            if (mistlandsStart - 0.05 > 0)
                config.world.biomes.affinity.main.mistlands.relativeTravelDistance = Curve(0, -1000, Round(mistlandsStart - 0.05), -100, mistlandsStart, 0);
            else
                Console.WriteLine("[Custom world settings] Mistlands band ignored: it must start above 5%.");
        }
        return config;
    }

    private static double Round(double value)
    {
        return Math.Round(value, 6);
    }

    private static StaticArray<Rpoint2> Curve(params double[] xy)
    {
        Rpoint2[] points = new Rpoint2[xy.Length / 2];
        for (int i = 0; i < points.Length; i++)
        {
            points[i] = new Rpoint2(xy[2 * i], xy[2 * i + 1]);
        }
        return new StaticArray<Rpoint2>(points);
    }
}

// Reads a .cfg in the Riverheim Config mod's format (the launcher writes one).
// Missing or unreadable values keep the Riverheim default.
internal sealed class ConfigValues
{
    private readonly Dictionary<string, string> entries = new Dictionary<string, string>();

    public static ConfigValues Load(string path)
    {
        ConfigValues values = new ConfigValues();
        string section = "";
        foreach (string raw in File.ReadAllLines(path))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line.StartsWith("#")) continue;
            if (line.StartsWith("[") && line.EndsWith("]"))
            {
                section = line.Substring(1, line.Length - 2).Trim();
                continue;
            }
            int equals = line.IndexOf('=');
            if (equals < 0) continue;
            values.entries[section + "|" + line.Substring(0, equals).Trim()] = line.Substring(equals + 1).Trim();
        }
        return values;
    }

    public double Get(string section, string key, double fallback)
    {
        string text;
        double parsed;
        return entries.TryGetValue(section + "|" + key, out text)
            && double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out parsed) ? parsed : fallback;
    }

    public int Get(string section, string key, int fallback)
    {
        string text;
        int parsed;
        return entries.TryGetValue(section + "|" + key, out text)
            && int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed) ? parsed : fallback;
    }
}
