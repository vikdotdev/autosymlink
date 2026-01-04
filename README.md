# `autosymlink` - zero-dependencies simple symlink manager

If you're managing dotfiles or need to maintain symlinks across machines, this tool lets you define them declaratively in a JSON config and sync them with a single command.

## Installation

### Quickstart (Linux x86_64)

```bash
mkdir -p ~/.local/bin ~/.config/autosymlink
curl -sL $(curl -s https://api.github.com/repos/vikdotdev/autosymlink/releases/latest | grep -o 'https://.*x86_64-linux-musl') -o ~/.local/bin/autosymlink && chmod +x ~/.local/bin/autosymlink
echo '{"links": []}' > ~/.config/autosymlink/config.json
```

### Manual download

Download a binary from [releases](https://github.com/vikdotdev/autosymlink/releases) or build from source.

## Usage

```bash
autosymlink link              # Create symlinks from config
autosymlink doctor            # Check health of symlinks
autosymlink --help            # Show help
```

### Config file

Default location: `~/.config/autosymlink/config.json`

```json
{
  "links": [
    {"source": "~/.dotfiles/bashrc", "destination": "~/.bashrc"},
    {"source": "~/.dotfiles/vimrc", "destination": "~/.vimrc", "force": true}
  ]
}
```

Use `--config` or `-c` to specify a different config path.

### Options

- `source` - Path to the source file (supports `~` expansion)
- `destination` - Path where symlink will be created
- `force` - Overwrite existing files (default: false)

## Building

Requires [Zig](https://ziglang.org/) 0.15.2 or [mise](https://mise.jdx.dev/).

```bash
zig build                          # Debug build
zig build -Doptimize=ReleaseSafe   # Release build
zig build test                     # Run tests
```

Binary output: `zig-out/bin/autosymlink`

## Releasing

Update version in `build.zig.zon`, then:

```bash
./scripts/release.sh
```
