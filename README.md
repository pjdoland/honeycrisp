# Honeycrisp

A read-only Mac disk audit tool that helps you figure out what's eating your storage. It scans your system for caches, logs, old downloads, leftover app data, and other common space hogs, then reports what it finds with size estimates and safety ratings.

It never deletes, moves, or modifies anything. It just tells you what's there.

## Quick start

```bash
chmod +x honeycrisp.sh
./honeycrisp.sh
```

For a faster scan that skips the slow deep searches (node_modules, large file finder, unused apps, language packs):

```bash
./honeycrisp.sh --quick
```

## What it scans

- System, app, and browser caches
- Logs and temporary files
- Application Support directories (flags ones where the app is no longer installed)
- iOS/iPhone backups
- Xcode DerivedData, archives, simulators, and device support files
- node_modules, npm/yarn/pnpm caches
- Python/pip/conda caches
- Homebrew cache and installed formulae
- Docker data
- Trash
- Disk images and installers (.dmg, .pkg, .iso)
- Mail and attachments
- Photos libraries and video files
- Old and large files in Downloads
- Language pack leftovers in apps
- Time Machine local snapshots
- Podcasts and music libraries
- Applications you haven't opened in 6+ months
- Any file over 500 MB (configurable)
- Top 20 largest directories in your home folder

Each finding includes a safety rating:

- **Safe** — generally fine to delete, your system or apps will rebuild it
- **Review** — probably fine, but look before you delete
- **Caution** — managed by macOS or contains important data, tread carefully

## Options

| Flag | Description |
|---|---|
| `--quick` | Skip slow deep scans for a fast overview |
| `--no-color` | Plain text output, no ANSI colors |
| `--threshold MB` | Set the large file threshold (default: 500 MB) |
| `--output FILE` | Save a copy of the report to a file |
| `--help` | Show usage info |
| `--version` | Print version |

## Requirements

- macOS
- Works on both Apple Silicon and Intel
- No dependencies beyond standard macOS command-line tools
- Does not require sudo (but notes where sudo would reveal more)

## Disclaimer

This is a personal tool that I find useful and decided to share. It comes with no warranty of any kind, express or implied. It is not guaranteed to be correct, complete, or suitable for any particular purpose.

**The script only reports — it does not delete anything.** But the "What To Do Next" section at the end includes commands and instructions you could use to actually clean things up. Before you run any of those commands, make sure you understand what you're deleting. Some of that data might matter to you even if it's "safe" in general. Back up anything you're not sure about.

I am not responsible for any data loss that results from actions you take based on this tool's output. Use your own judgment.
