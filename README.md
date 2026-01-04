# autosymlink

Symlink manager based on a JSON config file.

## Installation

### Quick install (Linux x86_64)

```bash
curl -sL $(curl -s https://api.github.com/repos/vikdotdev/autosymlink/releases/latest | grep -o 'https://.*x86_64-linux-musl') -o ~/.local/bin/autosymlink && chmod +x ~/.local/bin/autosymlink
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
