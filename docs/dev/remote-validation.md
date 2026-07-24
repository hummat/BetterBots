# AirGPU remote validation

## Scope

Use this workflow when the local machine cannot run the required Darktide test. The
June 27 v1.2.2 run used an AirGPU Windows 11 machine, Moonlight for gameplay, and
FreeRDP folder redirection for file transfer.

The connection workflow is recovered from the June session history. The original
helper script and transfer directory no longer exist, so the commands below replace
them. The existing Moonlight pairing still lives in the local Flatpak configuration,
but the original pairing steps were not recorded.

## Roles

- AirGPU dashboard: start and stop the Windows machine; obtain its current host,
  username, and password.
- Moonlight: launch Darktide and play the validation mission.
- FreeRDP: move the test build and logs between Linux and Windows.
- `bb-log`: analyze the returned console logs on Linux.

Do not put the AirGPU password on the command line. FreeRDP prompts for it when
`/p:` is omitted.

## Prepare the exact build

Run the static gate and package the tree that will be tested:

```zsh
make check-ci
make package
git rev-parse HEAD
sha256sum BetterBots.zip
```

Record the commit and checksum in `docs/dev/validation-tracker.md`.

On an AirGPU machine that already has the mod loader, DMF, SoloPlay, and the current
Tertium compatibility mod, transfer `BetterBots.zip`. Extract it into the
Darktide `mods` directory so the archive's `BetterBots/` directory replaces the
installed copy.

A fresh AirGPU machine needs a local game-root bundle containing the current mod
loader and dependencies. The June bundle combined the loader, DMF, SoloPlay, and
Tertium4Or5 archives, overlaid the Tertium6 archive onto Tertium4Or5, and copied
BetterBots into the result. Build this bundle from current verified downloads. Keep
it local because it contains third-party mods; do not attach it to a GitHub or Nexus
release.

## Open the transfer session

Create the local redirected folder:

```zsh
mkdir -p "$HOME/transfer"
```

Copy the package into it, then connect:

```zsh
cp BetterBots.zip "$HOME/transfer/"

xfreerdp3 \
  /v:HOST \
  /u:USER \
  /drive:transfer,"$HOME/transfer" \
  +clipboard \
  +dynamic-resolution \
  +auto-reconnect \
  /cert:tofu \
  /network:auto
```

Use the current host and username from the AirGPU dashboard. Leave the domain blank
unless the dashboard supplies one. Enter the password at FreeRDP's prompt.

The redirected folder appears in Windows as:

```text
\\tsclient\transfer
```

The June run established one important sequencing constraint: opening RDP ended the
active Moonlight session. Use RDP for transfer, disconnect it, and then reconnect
with Moonlight for the game. Do not leave both sessions open.

## Install and cold boot

Use Steam's "Browse local files" action to open the Darktide game root. For a
game-root bundle, extract it there and confirm that it merges `binaries/`, `bundle/`,
`tools/`, and `mods/`. For `BetterBots.zip`, extract it inside `mods/`.

Run `toggle_darktide_mods.bat` from the game root after each install or game update.
Confirm that `mods/mod_load_order.txt` contains the current user mods. DMF does not
need an entry.

The pre-release gate requires two independent cold boots:

1. Put BetterBots before the sibling gameplay mods, exit Darktide, relaunch
   through Moonlight, and run the mission.
2. Put BetterBots after the sibling gameplay mods, exit Darktide, relaunch,
   and repeat the mission.

Follow the active checklist in `docs/dev/validation-tracker.md`. For the v1.2.3
animation-slot regression, use an Ogryn bot with Rock and Gunlugger stance. Run
`/bb_scenario poxburster_push` to force a bot-targeted Poxburster test, and try to
interrupt a grenade wield with the catapult.

Quit Darktide before reopening RDP so the console log is complete.

## Return the console log

Reconnect with FreeRDP. In Windows PowerShell, copy the newest log to the redirected
folder:

```powershell
$log = Get-ChildItem "$env:APPDATA\Fatshark\Darktide\console_logs\console-*.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

Copy-Item $log.FullName "\\tsclient\transfer\$($log.Name)"
```

The file then appears under `$HOME/transfer` on Linux. Analyze it with the project
tool instead of raw grep:

```zsh
BB_LOG_DIR="$HOME/transfer" ./bb-log list
BB_LOG_DIR="$HOME/transfer" ./bb-log summary 0
BB_LOG_DIR="$HOME/transfer" ./bb-log warnings 0
BB_LOG_DIR="$HOME/transfer" ./bb-log raw \
  'animation_event failed|airtime_bwd|mid_reload_finished|Lua Error|CRASH' 0
```

Use the log index printed by `bb-log list` when both load-order logs are present.
Each run must have `Error lines: 0`, `BB warnings: 0`, no animation-event crash
signature, and the expected coordination markers from the active validation entry.

Record both runs in `docs/dev/validation-tracker.md`, including the commit, log
filename, bot build, load order, and result.

## Finish

Stop the AirGPU machine in its dashboard and confirm that its status changes from
running. Remove credentials from copied commands or notes. Keep the console logs
until the release decision is recorded.

## Recovered June reference

The June 27 run used a local-only, game-root-shaped
`BetterBots-full-modpack-v1.2.2-test.2.zip` with this user-mod order:

```text
SoloPlay
Tertium4Or5
BetterBots
```

The transferred log was
`console-2026-06-27-15.03.17-28b4576c-7ef4-4e68-94a3-7db109049ce4.log`.
Its recorded result is in `docs/dev/validation-tracker.md`. The archive and log are
no longer present on disk.
