# KM0

KM0 is a driving and vehicle repair game set along an abandoned road. Rebuild the sedan in your workshop, scavenge abandoned buildings for fuel and spare parts, and see how far you can get. Play alone or share the road over LAN.

## Download and play

Get the ZIP for your operating system and processor from [GitHub Releases](https://github.com/mateo-cogeanu/km-0/releases). Builds are available for x64 and ARM64 on Windows, Linux, and macOS.

- **Windows** — Extract the ZIP and start `KM0.exe`. Keep `KM0.pck` next to it.
- **Linux** — Extract the ZIP and run `./KM0` from the extracted folder.
- **macOS** — Extract the ZIP and open `KM0.app`. The builds are ad hoc signed and may require approval on first launch.

The first time you open the game, enter a name in the main menu. You can change it in **Settings → Gameplay**.

## Controls

| Input | Action |
| --- | --- |
| WASD | Walk or drive |
| Mouse | Look around |
| Shift | Sprint on foot |
| Space | Jump on foot or handbrake while driving |
| E | Use the object under the crosshair, enter or exit a vehicle, or drop a held object |
| Left mouse and drag | Open or close a door, hood, or shutter |
| C | Crouch on foot or change the driver's camera |
| L | Toggle the headlights |
| Esc | Open the pause menu |

For multiplayer, use the same KM0 version on each computer on the same local network. One player hosts from **Multiplayer** and the others select the lobby. Everyone marks themselves ready before the host starts. Each sedan seats four, and the first person to enter takes the driver's seat.

## Run from source

Open `project.godot` in Godot 4.6.3 and press **F5**. To export a build, install the matching Godot export templates and select a preset in **Project → Export**. The macOS preset produces a universal build.

## License

KM0's original code is licensed under the [GNU General Public License v3.0](LICENSE). Third-party assets and code retain their applicable licenses. See [Third-party notices](THIRD_PARTY_NOTICES.md).
