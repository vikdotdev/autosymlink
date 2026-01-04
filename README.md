# `autosymlink` - zero-dependencies simple symlink manager

If you're managing dotfiles or need to maintain symlinks across machines, this tool lets you define them declaratively in a JSON config and sync them with a single command.

## Installation

### Quickstart (Linux x86_64)

```bash
mkdir -p ~/.local/bin ~/.config/autosymlink
curl -sL $(curl -s https://api.github.com/repos/vikdotdev/autosymlink/releases/latest | grep -o 'https://.*x86_64-linux-musl') -o ~/.local/bin/autosymlink && chmod +x ~/.local/bin/autosymlink
echo '{"links": []}' > ~/.config/autosymlink/links.json
```

### Manual download

Download a binary from [releases](https://github.com/vikdotdev/autosymlink/releases) or build from source.

## Usage

```bash
autosymlink link              # Create symlinks from config
autosymlink doctor            # Check health of symlinks
autosymlink --help            # Show help
```

### Links file

Default location: `~/.config/autosymlink/links.json`

```json
{
  "links": [
    {"source": "${dotfiles}/bashrc", "destination": "~/.bashrc"},
    {"source": "${dotfiles}/nvim", "destination": "~/.config/nvim"},
    {"source": "${notes}", "destination": "${project}/notes.md"}
  ]
}
```

Use `--links` or `-l` to specify a different path.

### Aliases file

Default location: `~/.config/autosymlink/aliases.json`

Aliases let you define variables that get interpolated in your links. This is useful for:
- Keeping sensitive paths out of public view
- Machine-specific configurations using `${_hostname}`

```json
{
  "dotfiles": "${_home}/.dotfiles",
  "notes": "${_home}/Documents/secret-client-project-notes.md"
  "project": "${_home}/Work/secret-client-project"
}
```

Use `--aliases` or `-a` to specify a different path.

### Variables

**Built-in:**
- `${_home}` - Home directory
- `${_user}` - Current user
- `${_hostname}` - Machine hostname

**Environment variables** work directly: `${HOME}`, `${USER}`, `${XDG_CONFIG_HOME}`, etc.

Resolution order: aliases → environment variables → error.

Variables can reference other variables and will be resolved recursively. Only `${VAR}` syntax is supported (`$VAR` without braces is treated as literal text).

### Link options

- `source` - Path to the source file (supports `~` and `${var}` expansion)
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
