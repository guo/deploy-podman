# Release Guide

Quick reference for creating new Shipd releases.

## TL;DR - One Command Release

```bash
# Complete release workflow (recommended)
./scripts/release.sh -y 1.1.0

# Then add release notes on GitHub
```

## Detailed Steps

### Option 1: Automated (Recommended)

One command does everything:

```bash
./scripts/release.sh -y <version>
```

**What it does:**
1. ✅ Creates Git tag v<version>
2. ✅ Pushes to GitHub
3. ✅ Downloads tarball and calculates SHA256
4. ✅ Updates shipd.rb formula
5. ✅ Copies formula to homebrew-tap
6. ✅ Commits and pushes to tap repository

**After running:**
- Add release notes: https://github.com/guo/shipd/releases

### Option 2: Manual Steps

If you need more control:

**Step 1: Prepare release**
```bash
./scripts/prepare-release.sh -y 1.1.0
```

**Step 2: Update tap**
```bash
./scripts/update-tap.sh
```

**Step 3: Add release notes**
- Go to: https://github.com/guo/shipd/releases/tag/v1.1.0
- Add description and publish

## Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR.MINOR.PATCH** (e.g., 1.2.3)
- **MAJOR**: Breaking changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes

Examples:
- `1.0.0` → `1.0.1` - Bug fix
- `1.0.0` → `1.1.0` - New feature
- `1.0.0` → `2.0.0` - Breaking change

## Pre-Release Checklist

Before releasing:

- [ ] All tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (if exists)
- [ ] Version bump committed and pushed
- [ ] Working directory is clean

## Post-Release Checklist

After releasing:

- [ ] GitHub release created with notes
- [ ] Homebrew tap updated
- [ ] Test installation: `brew reinstall shipd`
- [ ] Announce release (if applicable)

## Testing a Release

Before pushing to users:

```bash
# Test Homebrew formula locally
./scripts/test-homebrew-formula.sh

# Or manual test
brew uninstall shipd
brew install --build-from-source ./shipd.rb
shipd --version
```

## Rollback a Release

If something goes wrong:

```bash
# Delete local tag
git tag -d v1.1.0

# Delete remote tag
git push origin :refs/tags/v1.1.0

# Delete GitHub release
# Go to: https://github.com/guo/shipd/releases
# Delete the release manually

# Revert tap
cd ../homebrew-tap
git revert HEAD
git push
```

## Release Frequency

Suggested:
- **Patch releases**: As needed for critical bugs
- **Minor releases**: Monthly or when features accumulate
- **Major releases**: Yearly or for significant changes

## Troubleshooting

### Formula SHA256 mismatch

```bash
# Recalculate SHA256
curl -sL https://github.com/guo/shipd/archive/refs/tags/v1.1.0.tar.gz | shasum -a 256

# Update shipd.rb manually
```

### Tag already exists

```bash
# Delete and recreate
git tag -d v1.1.0
git push origin :refs/tags/v1.1.0
./scripts/release.sh -y 1.1.0
```

### Tap push fails

```bash
cd ../homebrew-tap

# Check remote
git remote -v

# Add remote if missing
git remote add origin https://github.com/guo/homebrew-tap.git

# Push
git push -u origin main
```

## GitHub Release Template

Use this template for release notes:

```markdown
## What's New

- Added feature X
- Improved Y
- Fixed Z

## Installation

### Homebrew
\`\`\`bash
brew tap guo/tap
brew install shipd
# or upgrade
brew upgrade shipd
\`\`\`

### Manual
\`\`\`bash
./install.sh
\`\`\`

## Changes

See [CHANGELOG.md](CHANGELOG.md) for full details.

## Contributors

Thanks to @username for contributions!
```

## Automation Ideas

Future improvements:
- GitHub Actions to auto-update tap
- Automated changelog generation
- Auto-publish to Homebrew Core
- Release notifications
