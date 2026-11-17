# surf-touch

[surf](https://surf.suckless.org/) with a rudimentary touch UI, for tablets
without a keyboard. Two small patches on top of Debian's surf package:

- **touchbar**: a row of large buttons above (or below) the page:
  back, forward, reload/stop, an address field that also searches,
  zoom out, zoom in and home.
- **wayland**: run on Wayland natively when it is available, instead of
  Debian's forced X11. Besides sharper rendering, real touch input and the
  GNOME on-screen keyboard for the address field, this works around a crash
  in WebKitGTK 2.54 on 32-bit systems (see [Why Wayland](#why-wayland)).

Everything else is plain surf: same keybindings, same `~/.surf` directory,
same `config.h` way of configuring it.

Written for a Reeder A8iW (8" Bay Trail tablet, 32-bit Debian 13 userland,
GNOME on Wayland, touch only), but nothing in it is specific to that tablet.

## The touchbar

```
[ ◀ ][ ▶ ][ ⟳ ][ address or search ............ ][ − ][ + ][ ⌂ ]
```

| Button | Does |
|---|---|
| ◀ / ▶ | back / forward (greyed out when there is no history) |
| ⟳ / ✕ | reload; while a page loads it turns into ✕ (stop) |
| address field | shows the current address. Tapping it selects everything, so typing replaces it. Enter loads it. Input without a dot or `://` (or with spaces) is sent to the search engine. While a page loads the field fills up as a progress bar |
| − / + | zoom out / in (surf's own zoom) |
| ⌂ | home page |

The buttons never take keyboard focus, so surf's own keybindings keep
working when a keyboard is attached.

### Configuration (`config.h`)

| Option | Default | Meaning |
|---|---|---|
| `touchbar` | `1` | `0` gives you plain surf without the bar |
| `touchbarbottom` | `0` | `1` puts the bar at the bottom (thumb reach) |
| `touchbarheight` | `44` | button height in pixels; fonts scale with it |
| `touchhome` | `https://html.duckduckgo.com/html/` | the ⌂ page |
| `touchsearch` | `https://html.duckduckgo.com/html/?q=%s` | search URL, `%s` is the escaped query |
| `usewayland` | `1` | prefer Wayland; `0` keeps surf on X11 |

DuckDuckGo's HTML version is the default because it is light enough for an
Atom tablet. Any search URL with `%s` works.

## Install (Debian 13 / trixie)

The patches apply on top of Debian's `surf 2.1+git20250419-1` packaging
(they expect its `force-x11.patch` to be applied first).

With Docker, build a package for your architecture:

```sh
git clone https://github.com/ardyln/surf-touch
cd surf-touch
./build-deb.sh i386        # or amd64, arm64
sudo apt install ./out/surf_2.1+git20250419-1+touch2_i386.deb
```

Without Docker, on a Debian machine with `deb-src` enabled:

```sh
apt-get source surf && sudo apt-get build-dep surf
cd surf-2.1+git20250419
cp /path/to/surf-touch/patches/*.patch debian/patches/
printf 'touchbar.patch\nwayland.patch\n' >> debian/patches/series
dch -v 2.1+git20250419-1+touch2 'surf-touch'
dpkg-buildpackage -us -uc -b
```

To change `config.h` options, edit `config.def.h` in the source tree before
building (surf copies it to `config.h` at build time).

Debian's surf has no menu entry. A minimal launcher,
`~/.local/share/applications/surf.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Surf
GenericName=Web Browser
Exec=surf %u
Icon=web-browser
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
```

## Why Wayland

Debian patches surf to always use GTK's X11 backend (`force-x11.patch`),
because surf calls Xlib directly in a few places. On a 32-bit system under
Xwayland that now crashes surf at start-up with `SIGFPE`. Every other
WebKitGTK (GTK 3) program run on X11 there crashes the same way:

1. **GTK 3's X11 backend overflows the monitor refresh rate on 32-bit.**
   GTK 3.24.49 (Debian 13) computes the rate in millihertz as
   `(1000 * dotClock) / (hTotal * vTotal)` in 32-bit arithmetic. With a
   224 MHz dot clock (Xwayland's 1280×2048 mode for a scaled 800×1280
   panel) `1000 × 224 000 000` wraps around, and GTK reports **177 mHz**
   (0.177 Hz) for a 59.98 Hz display. Any dot clock above about 4.3 MHz
   overflows. Upstream GTK fixed this in March 2026
   ([`05fc3f45`](https://gitlab.gnome.org/GNOME/gtk/-/commit/05fc3f45),
   "x11: fix overflow in refresh_rate calculation on 32-bit systems");
   Debian 13's 3.24.49 does not have the fix yet.
2. **WebKitGTK divides by the refresh rate.**
   `DisplayLink::platformInitialize()`
   (`Source/WebKit/UIProcess/glib/DisplayLinkGLib.cpp`, added with
   "[GTK][WPE] FPS throttling in DisplayLink", November 2025) rounds
   177 mHz down to 0 fps and computes
   `refreshRate / m_displayNominalFramesPerSecond`, which is `0 / 0`.
   WebKit's main branch still divides unguarded, so any source of a 0 Hz
   refresh rate crashes it. WebKitGTK versions before that change did not
   divide here.

`WEBKIT_DISPLAY_REFRESH_THROTTLE_FPS=60` avoids the division, but WebKit
still believes the display runs at 0 Hz, never gets a frame callback and
leaves the page blank. So it is no workaround.

On Wayland, GTK takes the refresh rate straight from the compositor
(`wl_output`, already in mHz) and gets it right (60 025 mHz on the tablet),
so the bug never triggers. The `wayland` patch makes surf's Xlib code
X11-only and lets GDK choose Wayland first:

- `_SURF_GO`, `_SURF_FIND` and `_SURF_URI` window properties (used by the
  dmenu go/find keybindings and by scripts) only exist on X11.
- Embedding with `-e` (for `tabbed`) only works on X11.
- Everything else, including all other keybindings, works on both.

Set `usewayland = 0` to get the old behaviour.

Found with gdb and Debian's debug symbols for
`libwebkit2gtk-4.1-0 2.54.0-1~deb13u3` (i386). Once Debian ships a GTK 3
with the overflow fix, surf works on X11 again too; the WebKit division by
zero is not reported upstream from here.

## Files

- `patches/touchbar.patch`: the touch UI
- `patches/wayland.patch`: Wayland first, Xlib only on X11
- `build-deb.sh`: builds the Debian package in a container
- `LICENSE`: GPL-3.0 for the patches and scripts in this repository
- `LICENSE.surf`: surf's own MIT licence

## License

The patches and scripts here are GPL-3.0-or-later. surf itself is MIT
licensed (`LICENSE.surf`); a surf binary built with these patches is
distributed under the GPL-3.0.
