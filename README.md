# Riverheim AtlasBuilder UI

A point-and-click launcher for [Gurebu's Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim/),
so you can generate Riverheim map images without touching a command line.

Windows only. Two small files, ~35 KB total.

## What this is and isn't

- It **is** a UI wrapper. It builds the command line for you, runs the tool, and keeps track of what settings made which map.
- It **does not** include `Riverheim.AtlasBuilder.exe`. That's Gurebu's tool — you install it from Thunderstore. This repo only ships the launcher.
- It is **not** affiliated with or endorsed by Gurebu. It's a community convenience wrapper.
- There is no installer, no binary, and nothing that runs in the background. It's two plain-text files you can read in full before running:
  [`AtlasBuilder-Launcher.ps1`](AtlasBuilder-Launcher.ps1) and [`Run-AtlasBuilder-UI.cmd`](Run-AtlasBuilder-UI.cmd).

## Install

1. Install [Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim/) from Thunderstore if you haven't.
2. Download the two files from the [latest release](../../releases/latest) (or use **Code → Download ZIP**).
3. If you downloaded a zip: right-click it → **Properties** → tick **Unblock** → OK, *then* extract. Windows flags scripts that came from the internet, and this is how you clear it.
4. Drop `AtlasBuilder-Launcher.ps1` and `Run-AtlasBuilder-UI.cmd` into the folder that already contains `Riverheim.AtlasBuilder.exe`.

   With Thunderstore Mod Manager that's usually:

   ```
   %AppData%\Thunderstore Mod Manager\DataFolder\Valheim\profiles\<YOUR PROFILE>\BepInEx\plugins\Gurebu-Riverheim_AtlasBuilder
   ```

   Paste that into the Explorer address bar and swap in your profile name. On r2modman it's the same but under `r2modmanPlus-local`.

5. Double-click **`Run-AtlasBuilder-UI.cmd`**.

## Usage

The **AtlasBuilder** path fills itself in automatically as long as the launcher is sitting next to the exe. If it isn't, hit **Browse** and point at it.

Enter your world seed, pick an output folder (defaults to `Pictures\Riverheim Maps`), choose your map modes, and hit **Generate map**. The **Settings guide** button explains every option in the window.

**Every generated image gets a matching `.riverheim.json` sidecar** saved next to it, recording the seed and all settings used. JPGs additionally get the key settings written into EXIF `UserComment`, so they survive being shared around. **Map history** browses an output folder, previews thumbnails, filters by mode or grid, and can load any past map's settings straight back into the generator.

## About the `-ExecutionPolicy Bypass`

Fair question if you looked at the `.cmd` and got twitchy about it:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0AtlasBuilder-Launcher.ps1"
```

Windows blocks unsigned `.ps1` files by default, and code signing needs a certificate that costs real money. `Bypass` applies **only to this one launch of this one script** — it doesn't change any machine setting or persist after the window closes. `-STA` is required because the UI uses Windows Forms. `-NoProfile` means your PowerShell profile isn't loaded.

You should be skeptical of scripts from the internet. That's exactly why this is a readable text file in a public repo instead of an exe behind a Drive link — read it before you run it.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Window flashes and closes, or "running scripts is disabled" | You skipped the Unblock step. Right-click `AtlasBuilder-Launcher.ps1` → Properties → **Unblock**. |
| "Windows protected your PC" (SmartScreen) | **More info** → **Run anyway**. |
| "AtlasBuilder not found" | The launcher isn't next to the exe. Use **Browse** to point at `Riverheim.AtlasBuilder.exe`. |
| Nothing generates | Check the log pane at the bottom of the window — the exe's own output goes there. |

## Requirements

Windows 10 or 11 with Windows PowerShell 5.1 (preinstalled — you don't need to install anything). Riverheim AtlasBuilder from Thunderstore.

## License

MIT — see [LICENSE](LICENSE). Applies to the launcher only, not to AtlasBuilder itself.
