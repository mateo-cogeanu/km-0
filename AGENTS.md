# Game versions

Update `application/config/version` in `project.godot` whenever you make a game update. Use `YY.Q-N`: the last two digits of the year, the calendar quarter (1–4), and a build number starting at 1. Increment the build number once per update within the same quarter. Reset it to 1 when the quarter changes. For example, the first update of Q4 2026 is `26.4-1` and the next is `26.4-2`.

# GitHub

Commit and push each game update to the tracked branch on GitHub. Push work in progress and experimental changes too, even if checks fail. Publish a GitHub release for every game update using the version in `project.godot`. Include x64 and ARM64 archives for Windows, Linux, and macOS and a SHA-256 checksum file. Report any failed checks or missing builds.
