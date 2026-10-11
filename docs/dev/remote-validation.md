# AirGPU remote validation

## Scope

Use this workflow when the local machine cannot run the required Darktide test. The
October 11, 2026 #118 run established the current setup: an AirGPU Windows 10
machine played over Moonlight, with Tailscale and OpenSSH giving the Linux side a
shell on it. With that shell an agent can install the mods, switch the load order,
and fetch logs, so the human only plays the missions.

The June 27 v1.2.2 run used FreeRDP for file transfer instead. Current AirGPU
machines do not expose RDP: a port scan of the October machine found only the four
Moonlight ports (47984, 47989, 47990, 48010) open, with 22 and 3389 filtered. The
dashboard has no RDP setting and shows no Windows password. Treat RDP as gone and
use the Tailscale route below.

## Roles

- AirGPU dashboard: start and stop the machine. It shows the public IP, which only
  Moonlight needs.
- Moonlight: play the missions, and type the one-time Windows setup commands. The
  stream has no clipboard, so every Windows command in this file is meant to be typed.
- Tailscale: connects this PC and the Windows machine from both ends, so AirGPU's
  inbound firewall does not matter.
- OpenSSH on Windows: shell and `scp` for the install, load-order switch, and log
  retrieval.
- `bb-log`: analyze the returned console logs on Linux.

## Prepare the exact build

Run the static gate and package the tree that will be tested:

```zsh
make check-ci
make package
git rev-parse HEAD
sha256sum BetterBots.zip
```

Record the commit and checksum in `docs/dev/validation-tracker.md`.

A fresh AirGPU machine has Darktide but no mods, so build a game-root bundle. Download
the current Nexus files into `~/Downloads`: Darktide Mod Loader (mod 19), Darktide Mod
Framework (mod 8), SoloPlay (mod 176), and the Tertium variant you want (Tertium 6/7
is mod 725 and ships as a `.rar`; Tertium4Or5 is mod 183). DMF and SoloPlay also
live on GitHub (`Darktide-Mod-Framework/Darktide-Mod-Framework`,
`deluxghost/darktide-mods/SoloPlay`), but the GitHub copy of SoloPlay can lag
the Nexus release by a version.

Assemble the bundle in a scratch directory:

```zsh
W=$(mktemp -d) && cd "$W" && mkdir root t
unzip -q ~/Downloads/Darktide\ Mod\ Loader*.zip -d root
unzip -q ~/Downloads/Darktide\ Mod\ Framework*.zip -d root/mods
unzip -q ~/Downloads/SoloPlay*.zip -d root/mods
bsdtar -xf ~/Downloads/Tertium\ 7*.rar -C root/mods
unzip -q ~/git/BetterBots/BetterBots.zip -d root/mods
```

The Tertium 6, Tertium 7, and Tertium4Or5 26.09.05 archives all index
`Personalities[profile.lore.backstory.personality]` and
`profile.archetype.archetype_name` without nil checks in its `fetch_all_profiles`
hook (see `docs/dev/known-issues.md`). Before zipping, guard those two lookups in
`root/mods/Tertium4Or5/scripts/mods/Tertium4Or5/Tertium4Or5.lua` so a missing
personality or archetype falls back to an empty string, then syntax-check the file
with `luajit -bl <file> >/dev/null`.

Append the user mods to the loader's `root/mods/mod_load_order.txt` below its comment
header, BetterBots first for the first cold boot:

```text
BetterBots
SoloPlay
Tertium4Or5
```

Zip and check it:

```zsh
(cd root && zip -qr -X ~/transfer/BetterBots-airgpu-<tag>-bundle.zip .)
unzip -tq ~/transfer/BetterBots-airgpu-<tag>-bundle.zip
sha256sum ~/transfer/BetterBots-airgpu-<tag>-bundle.zip
```

Keep the bundle local because it contains third-party mods; do not attach it to a
GitHub or Nexus release.

## One-time access setup

### Linux side

Install Tailscale (`pacman -S tailscale`), start it, and log in:

```zsh
sudo systemctl enable --now tailscaled
sudo tailscale up --operator=$USER
```

**`tailscale up` fails with `503 Service Unavailable: no backend`.** The journal shows
`modprobe: FATAL: Module tun not found`: the kernel was updated without a reboot, so
the running kernel has no matching `tun` module. Reboot, or run tailscaled in
userspace mode until the next reboot by setting
`FLAGS="--tun=userspace-networking"` in `/etc/default/tailscaled`, then
`sudo systemctl reset-failed tailscaled && sudo systemctl restart tailscaled`.
Userspace mode creates no `tailscale0` interface, so plain `ssh <tailscale-ip>`
does not route; reach peers through `tailscale nc` as shown below, which works in
both modes.

### Windows side (typed over Moonlight)

Open PowerShell as administrator. Install Tailscale (`winget install
Tailscale.Tailscale` or the installer from tailscale.com) and sign in with the same
account as the Linux side. Then enable the SSH server and restrict its built-in
firewall rule to the tailnet:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic
Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress 100.64.0.0/10
```

Installing the capability creates `OpenSSH-Server-In-TCP`, which allows port 22 from
any address. A second allow rule would restrict nothing, so narrow the built-in one.
Today AirGPU's edge filter also blocks 22 from outside; the rule keeps SSH tailnet
only if that changes.

The account is `paperspace`, and the dashboard never shows
its password. Install the key from GitHub instead of setting one. `paperspace` is an
administrator, and for administrators Windows OpenSSH reads keys only from
`C:\ProgramData\ssh\administrators_authorized_keys`, which must be restricted to
Administrators and SYSTEM:

```powershell
$f = "C:\ProgramData\ssh\administrators_authorized_keys"
curl.exe -s https://github.com/hummat.keys | Add-Content -Encoding ascii $f
icacls.exe $f /inheritance:r /grant Administrators:F /grant SYSTEM:F
```

This works because the default local SSH keys include one that is registered on
GitHub. A per-user `~\.ssh\authorized_keys` is ignored for this account.

### Connect

`tailscale status` lists the Windows node as `airgpu-ps…`. Its tailnet name and
100.x address differ from the dashboard name and public IP, and a new AirGPU machine
gets a new node. Test the login:

```zsh
ssh -o ProxyCommand='tailscale nc %h %p' paperspace@<tailscale-ip> whoami
```

The first connection records the host key. Windows OpenSSH also prints a warning
about post-quantum key exchange; it is harmless, and `-o LogLevel=ERROR` hides it.
The remote shell is `cmd.exe`, so run PowerShell scripts as
`ssh … 'powershell -NoProfile -Command -' <<'EOF' … EOF` to avoid nested quoting.

## Install and cold boot

Darktide was preinstalled on the October machine. Check that Steam reports it as
complete (`StateFlags` 4) and that it has run once without mods (a log exists under
`%APPDATA%\Fatshark\Darktide\console_logs`):

```powershell
Select-String 'C:\Program Files (x86)\Steam\steamapps\appmanifest_1361210.acf' -Pattern '"(StateFlags|buildid)"'
```

Copy the bundle, compare its hash with the local `sha256sum`, extract it into the
game root, and patch the bundle database:

```zsh
O=(-o "ProxyCommand=tailscale nc %h %p" -o BatchMode=yes -o LogLevel=ERROR)
scp "${O[@]}" ~/transfer/BetterBots-airgpu-<tag>-bundle.zip paperspace@<tailscale-ip>:bundle.zip
ssh "${O[@]}" paperspace@<tailscale-ip> 'powershell -NoProfile -Command -' <<'EOF'
(Get-FileHash $HOME\bundle.zip -Algorithm SHA256).Hash
$g = 'C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE'
Expand-Archive $HOME\bundle.zip $g -Force
Set-Location $g
& .\tools\dtkit-patch.exe --patch .\bundle
EOF
```

Expect `successfully patched "bundle_database.data"`. Call `dtkit-patch --patch`
directly instead of `toggle_darktide_mods.bat`: the batch file ends in `pause`, and
`--toggle` on an already patched game prompts whether to unpatch. Both wait for
keyboard input and hang over SSH. Repatch
after every Darktide update. `mods/mod_load_order.txt` lists the user mods; DMF does
not need an entry.

The pre-release gate requires two independent cold boots:

1. Put BetterBots before the sibling gameplay mods, exit Darktide, relaunch, and
   run the mission.
2. Put BetterBots after the sibling gameplay mods, exit Darktide, relaunch,
   and repeat the mission.

Switch the order between the runs over SSH while Darktide is closed (written for the
#118 run; first use still pending):

```powershell
$f = 'C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\mod_load_order.txt'
$lines = Get-Content $f
($lines | Where-Object { $_ -ne 'BetterBots' }) + 'BetterBots' | Set-Content -Encoding ascii $f
Get-Content $f
```

Tertium 7's checkbox is labeled **Enable 4 bots** but adds three extra slots.
For a normal four-person team, keep the mod enabled, untick the checkbox, and assign
characters to Bot 1–3 (see `docs/related-mods.md`).

Follow the active checklist in `docs/dev/validation-tracker.md`. For the v1.2.3
animation-slot regression, use an Ogryn bot with Rock and Gunlugger stance. A bot's
build comes from BetterBots' own profile template unless Tertium assigns a real
character to that slot, and the built-in Ogryn template is Loyal Protector plus frag
bomb. Assign the Ogryn character in the Tertium mod's `character_N` dropdown, then
respec it in the Psykhanium to `ogryn_special_ammo` (Point-Blank Barrage) and
`ogryn_grenade_friend_rock` (Big Friendly Rock) with a reload-heavy ranged weapon.
Run `/bb_scenario poxburster_push` to force a bot-targeted Poxburster test, and try
to interrupt a grenade wield with the catapult.

For the interaction path, down the player while the Ogryn bots are throwing Rocks
under horde pressure. A successful collision prints `released grenade weapon lock
for interaction during ogryn_grenade_friend_rock`. Any `suppressed failed bot
anim_event` warning keeps the session alive but fails the release test.

Quit Darktide fully after each run so the console log is complete.

## Return the console logs

List the newest logs over SSH, then copy them by name, since a remote wildcard
may not expand on Windows OpenSSH (this step was written before its first use):

```zsh
ssh "${O[@]}" paperspace@<tailscale-ip> 'powershell -NoProfile -Command -' <<'EOF'
Get-ChildItem "$env:APPDATA\Fatshark\Darktide\console_logs\console-*.log" |
  Sort-Object LastWriteTime -Descending | Select-Object -First 2 | ForEach-Object Name
EOF
scp "${O[@]}" "paperspace@<tailscale-ip>:AppData/Roaming/Fatshark/Darktide/console_logs/<name>" ~/transfer/
```

Analyze them with the project tool instead of raw grep:

```zsh
BB_LOG_DIR="$HOME/transfer" ./bb-log list
BB_LOG_DIR="$HOME/transfer" ./bb-log summary 0
BB_LOG_DIR="$HOME/transfer" ./bb-log warnings 0
BB_LOG_DIR="$HOME/transfer" ./bb-log raw \
  'animation_event failed|airtime_bwd|mid_reload_finished|Lua Error|CRASH' 0
```

Use the log index printed by `bb-log list` when both load-order logs are present.
Each run must have `Error lines: 0`, `BB warnings: 0`, no animation-event crash
signature, and the expected markers from the active validation entry.

Record both runs in `docs/dev/validation-tracker.md`, including the commit, log
filename, bot build, load order, and result.

## Finish

Stop the machine from the dashboard; it bills $0.75/hr while running. Stopping ends
compute use but leaves its persistent storage allocated and billable. Delete the
machine if the installed environment is no longer needed, and remove its node from
the Tailscale admin console.

If you switched tailscaled to userspace mode, set `FLAGS=""` in
`/etc/default/tailscaled` before the next reboot of the Linux side; userspace mode
keeps working after a reboot, but the kernel `tun` device is the normal setup.

## Dead ends

- **RDP and direct SSH:** port 3389 and 22 are filtered on the public IP, and the
  dashboard offers no way to open them.
- **SSH inside Moonlight:** Moonlight carries only video, audio, and input. It has
  no shell, file transfer, clipboard, or port forwarding.
- **Anonymous file hosts:** 0x0.st has disabled uploads, and litterbox.catbox.moe
  returned HTTP 500. Without Tailscale, the working fallback was the Hetzner storage
  box (`ssh box`; host and port in `~/.ssh/config`): upload with `sftp`, then
  download on Windows with `scp -P <port> <user>@<host>:<path> .` using the values
  from that config entry, which prompts for the storage-box password.
- **Sunshine web admin (port 47990):** open, but it needs AirGPU's admin login.

## Recovered June reference

The June 27 staging directory, `~/Downloads/darktide_mods/`, contained the mod
loader, DMF, SoloPlay, Tertium4Or5, and Tertium6 archives; the archives are still
there but outdated. That run used FreeRDP with `/drive:transfer,"$HOME/transfer"`
for file transfer and found that opening RDP ended the active Moonlight session.
Its user-mod order was:

```text
SoloPlay
Tertium4Or5
BetterBots
```

The transferred log was
`console-2026-06-27-15.03.17-28b4576c-7ef4-4e68-94a3-7db109049ce4.log`.
Its recorded result is in `docs/dev/validation-tracker.md`. The log is no longer
present on disk.
