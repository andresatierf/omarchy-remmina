# omarchy-remmina

An [Omarchy](https://omarchy.org) shell plugin: a picker for your
[Remmina](https://remmina.org) connection profiles.

## What it does

- Fuzzy-search your Remmina profiles by name, address or group from a
  fullscreen overlay.
- Lists the profiles you connected to last first, so `Enter` on an empty filter
  reconnects to the one you most likely want.
- Single-key actions:

  | Key | Action |
  | --- | --- |
  | `Enter` | connect |
  | `Alt+e` | edit the profile in Remmina |
  | `Alt+n` | new profile, with whatever you typed as the server |
  | `Alt+f` | forget a recent profile |
  | `Alt+o` | open Remmina's main window |
  | `Alt+r` | reload the list |

The list only ever carries a profile's name, protocol, server, username and
group. A `.remmina` file stores the saved password right beside those, so the
helper reads the named keys and nothing else, and the overlay hands back only
the profile's path — which the helper refuses unless it is a `.remmina` file
inside Remmina's own profiles folder.

Profiles are read from the folder Remmina itself uses: `datadir_path` in
`~/.config/remmina/remmina.pref`, then `~/.local/share/remmina`, then
`~/.remmina`. Recent connections are kept in
`$XDG_STATE_HOME/omarchy-remmina/recent.json`; set `OMARCHY_REMMINA_RECENT` to
change how many are lifted to the top (default 5).

## Requirements

- Omarchy shell (plugin schema v1)
- [Remmina](https://remmina.org) and `jq`

## Install

```bash
omarchy plugin add https://github.com/andresatierf/omarchy-remmina.git --enable
```

Summon it with:

```bash
omarchy-shell shell summon io.github.andresatierf.remmina '{}'
```

or bind it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + R", "Remote desktops", "omarchy-shell shell toggle io.github.andresatierf.remmina")
```

## Layout

The plugin follows the Omarchy [plugin development
guide](https://plugins.omarchy.org/develop.html): one `overlay` kind, whose entry
point is named for its kind.

```
io.github.andresatierf.remmina/
├── manifest.json
├── Overlay.qml          the view: lifecycle, keys, geometry, the card
├── Model.js             the display model: parsing, filtering, ordering
├── test/
│   ├── model.test.js    node --test
│   └── list.test.sh     what the helper lists, and what it refuses
└── bin/
    └── omarchy-remmina  profiles, recents and every action
```

- **`Model.js`** is pure — no `Process`, no `Quickshell`, no filesystem — so it
  can be `require`d from node and its ordering rules tested.
- **`Overlay.qml`** owns everything stateful: the surface, the keys, the
  `Process` calls.
- **`bin/omarchy-remmina`** reads profiles and launches Remmina. It is also a
  CLI in its own right (`omarchy-remmina --help`); with no arguments it summons
  the overlay, so it is safe to use as an `omarchy-menu` action.

`Overlay.qml` finds the helper through the `__sourceDir` the shell stamps onto
every manifest it loads, so `bin/` does not need to be on `PATH`. To use it from
a terminal or a menu extension, link it somewhere that is:

```bash
ln -s ~/.config/omarchy/plugins/io.github.andresatierf.remmina/bin/omarchy-remmina \
      ~/.config/omarchy/bin/omarchy-remmina
```

Keep that link outside the plugin folder — `omarchy plugin validate` refuses
symlinks inside one.

## Development

```bash
git clone https://github.com/andresatierf/omarchy-remmina ~/dev/omarchy-remmina
ln -s ~/dev/omarchy-remmina ~/.config/omarchy/plugins/io.github.andresatierf.remmina
```

Validate, lint and test:

```bash
omarchy plugin validate ~/dev/omarchy-remmina
qmllint -I "$OMARCHY_PATH/shell" ~/dev/omarchy-remmina/Overlay.qml
node --test                    # from the repo root; no dependencies
./test/list.test.sh            # against fixture profiles; no Remmina needed
```

The shell watches `~/.config/omarchy/plugins` with `inotifywait -r`, which does
not follow symlinks, so edits in a symlinked checkout are not picked up live —
run `omarchy-shell shell rescanPlugins` or restart the shell.

## License

MIT. See [LICENSE](LICENSE).
