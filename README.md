# systemd-trusted-ssid-unlock

Unlock your screen automatically when you resume from suspend near a Wi-Fi
network you trust — before you've had time to start typing your password.

Made for **swaylock** on Linux with **NetworkManager** and **systemd**, but
the unlock command is configurable.

> [!WARNING]
> This was vibecoded (written with an AI assistant) and has only been
> tested on one machine: Arch Linux, swaylock, NetworkManager and an Intel
> `iwlwifi` card. It hasn't been tested on other distros, drivers or screen
> lockers. Read the scripts before installing — they run as root — and read
> the [Security](#security) section.

## Why

The obvious approach is a NetworkManager dispatcher script that unlocks when
you connect to a trusted SSID. It works, but it's slow: after resume,
NetworkManager scans every channel, associates and runs DHCP before the
script fires. That typically takes ~5 seconds, so you end up typing your
password anyway.

systemd-trusted-ssid-unlock doesn't wait to connect. It only needs to know that a trusted
access point is *in range*:

- A systemd sleep hook runs as soon as the kernel resumes — before your
  session is thawed and before NetworkManager wakes up and takes the radio.
- It scans only the channels your trusted APs were last seen on (~0.1 s,
  instead of ~3.5 s for a full scan) and matches APs by **BSSID** (MAC
  address), not by name.
- If a trusted AP is found, the screen locker gets the unlock signal before
  your session is even thawed.

Typical result: unlocked ~0.7 s after opening the lid, versus ~5 s.

## How it works

| Piece | When it runs | What it does |
|---|---|---|
| `systemd-trusted-ssid-unlock hook` (`/usr/lib/systemd/system-sleep/systemd-trusted-ssid-unlock`) | Right after resume, before the session thaws | Brings the interface up, scans the known channels, unlocks if a trusted BSSID is found |
| `systemd-trusted-ssid-unlock watch` (`systemd-trusted-ssid-unlock.service`) | After resume, if the hook didn't unlock | Watches scan results for up to 15 s, including NetworkManager's own full scan. Catches APs that changed channel |
| `systemd-trusted-ssid-unlock refresh` (`/etc/NetworkManager/dispatcher.d/90-systemd-trusted-ssid-unlock`) | Whenever Wi-Fi connects | Updates the stored channel of any trusted AP that has moved |
| `systemd-trusted-ssid-unlock-add` | When you run it | Trusts every AP broadcasting the SSID you're connected to |

Routers on automatic channel selection move around. When that happens the
quick scan misses, the fallback finds the AP during NetworkManager's scan
(slower, a few seconds), and the new channel is saved so the next resume is
fast again.

Only APs actually seen **since this resume** count. `iw` also returns
cached and pre-suspend results, which are ignored.

## Requirements

- Linux with systemd and NetworkManager
- `iw`, `iproute2` (`ip`), `util-linux` (`logger`, `flock`)
- A screen locker that can be unlocked from a command. swaylock unlocks on
  `SIGUSR1`, which is the default.

## Install

```sh
git clone https://github.com/neilbags/systemd-trusted-ssid-unlock.git
cd systemd-trusted-ssid-unlock
./install.sh            # uses sudo
```

Then connect to each network you want to trust and run:

```sh
systemd-trusted-ssid-unlock-add
```

That adds every AP with the current SSID (both bands, all mesh nodes) to
`/etc/systemd-trusted-ssid-unlock/trusted`. Run it again later to pick up new APs.

Uninstall with `./install.sh --uninstall`.

## Configuration

`/etc/systemd-trusted-ssid-unlock/config` (all optional):

```sh
DEV=wlan0                               # default: first interface from `iw dev`
UNLOCK_CMD='pkill -USR1 -x swaylock'    # runs as root
HOOK_TRIES=20                           # quick scans right after resume, 0.1 s apart
WATCH_SECONDS=15                        # how long the fallback keeps looking
```

`/etc/systemd-trusted-ssid-unlock/trusted` is plain text, one AP per line; edit it by hand
to remove networks:

```
<bssid> <frequency MHz> <ssid>
aa:bb:cc:dd:ee:ff 5180 HomeNetwork
```

### Finding old networks in your logs

You can trust networks you aren't connected to right now if you've used them
before. wpa_supplicant logs the BSSID and frequency on every connection:

```sh
journalctl -t wpa_supplicant | grep "Trying to associate with"
```

NetworkManager also keeps every BSSID it has used for each saved connection
in `/var/lib/NetworkManager/seen-bssids` (keyed by connection UUID; see
`nmcli -f NAME,UUID connection`).

## Debugging

Everything is logged to the journal:

```sh
journalctl -t systemd-trusted-ssid-unlock -b
```

A healthy resume looks like:

```
hook: try 1: nothing found
hook: trusted AP in range (aa:bb:cc:dd:ee:ff), unlocking
```

If you see `Device or resource busy`, something else (usually
NetworkManager) is scanning; the fallback service will handle it.

## Security

Read this before you use it.

- **A BSSID is not a secret.** Anyone near your trusted network can see it
  and make a device broadcast the same one. systemd-trusted-ssid-unlock checks that an AP
  with that address is in range; it does not authenticate the AP. Someone
  with physical access to your laptop and a spoofed AP can unlock it.
- This is still stronger than unlocking on SSID alone, where any hotspot
  with a matching name would do.
- Only trust places where you'd be comfortable leaving the laptop unlocked.
- The trusted list and config are root-owned, and `UNLOCK_CMD` runs as
  root. Keep `/etc/systemd-trusted-ssid-unlock` writable only by root.

## Notes

- The sleep hook lives in `/usr/lib/systemd/system-sleep/`, the only
  directory systemd reads hooks from. Package updates won't remove it.
- Hooks run in parallel and the scan is short, so resume isn't noticeably
  slower. If no trusted AP is around, the hook gives up after `HOOK_TRIES`.
- Tested with swaylock, NetworkManager and Intel `iwlwifi`. Other drivers
  should work as long as `iw scan` works while NetworkManager is asleep.

## License

MIT — see [LICENSE](LICENSE).
