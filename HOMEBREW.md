# Homebrew Distribution Guide

This guide explains how to distribute Shipd via Homebrew.

## Prerequisites

1. **GitHub Repository** with public access
2. **Git Tags** for versioned releases
3. **GitHub Releases** with source tarball

## Step 1: Create a GitHub Release

```bash
# Tag a release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# GitHub will automatically create a tarball at:
# https://github.com/guo/shipd/archive/refs/tags/v1.0.0.tar.gz
```

## Step 2: Calculate SHA256

```bash
# Download and calculate checksum
curl -sL https://github.com/guo/shipd/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
```

Copy the SHA256 hash - you'll need it for the formula.

## Step 3: Update the Formula

Edit `shipd.rb`:

```ruby
class Shipd < Formula
  desc "Container deployment automation tool for Docker and Podman"
  homepage "https://github.com/guo/shipd"
  url "https://github.com/guo/shipd/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PASTE_YOUR_SHA256_HERE"  # From step 2
  license "MIT"
  # ... rest of formula
end
```

## Step 4: Test Locally

```bash
# Install from local formula
brew install --build-from-source ./shipd.rb

# Test it works
shipd --version

# Uninstall
brew uninstall shipd
```

## Step 5: Publishing Options

### Option A: Homebrew Tap (Easiest)

Create your own tap (GitHub repo) to host the formula:

```bash
# Create tap repository on GitHub: homebrew-tap
# Repository name MUST be: homebrew-tap

# Add formula to repo
git clone https://github.com/guo/homebrew-tap
cd homebrew-tap
cp /path/to/shipd/shipd.rb Formula/shipd.rb
git add Formula/shipd.rb
git commit -m "Add shipd formula"
git push
```

**Users install with:**
```bash
brew tap guo/tap
brew install shipd
```

### Option B: Homebrew Core (Official)

Submit to official Homebrew repository:

1. **Requirements:**
   - Stable project (30+ days old)
   - 75+ GitHub stars OR 30+ forks
   - Notable usage (visible user base)
   - Active maintenance

2. **Submit Pull Request:**
   ```bash
   # Fork homebrew-core
   git clone https://github.com/homebrew/homebrew-core
   cd homebrew-core

   # Create formula
   cp /path/to/shipd/shipd.rb Formula/shipd.rb

   # Create PR
   git checkout -b shipd
   git add Formula/shipd.rb
   git commit -m "shipd: new formula"
   git push origin shipd
   ```

3. **Open PR** on GitHub: https://github.com/Homebrew/homebrew-core

**Users install with:**
```bash
brew install shipd
```

## Step 6: Updating Releases

When releasing a new version:

1. Create new Git tag and GitHub release
2. Calculate new SHA256
3. Update formula:
   ```ruby
   url "https://github.com/guo/shipd/archive/refs/tags/v1.1.0.tar.gz"
   sha256 "NEW_SHA256_HERE"
   ```
4. Commit and push to tap repository

## Installation Paths

Homebrew installs to different locations:

- **Apple Silicon (M1/M2/M3)**: `/opt/homebrew/`
  - Binary: `/opt/homebrew/bin/shipd`
  - Libraries: `/opt/homebrew/lib/shipd/`

- **Intel Mac**: `/usr/local/`
  - Binary: `/usr/local/bin/shipd`
  - Libraries: `/usr/local/lib/shipd/`

Shipd automatically detects both locations.

## User Data Directory

Homebrew installation creates user data at:
- `~/.shipd/targets/` - User deployment targets
- `~/.shipd/.config` - Optional global config

## Testing Checklist

Before publishing:

- [ ] Formula installs successfully
- [ ] `shipd --version` works
- [ ] `shipd deploy --help` works
- [ ] Can create and deploy to a target
- [ ] Uninstall works: `brew uninstall shipd`
- [ ] Reinstall works: `brew install shipd`
- [ ] Works on both Apple Silicon and Intel (test both if possible)

## Troubleshooting

### Formula Fails to Install

Check audit:
```bash
brew audit --strict --online shipd.rb
```

### Binary Not Found

Verify installation:
```bash
brew list shipd
which shipd
```

### Library Files Not Found

Check lib directory exists:
```bash
# Apple Silicon
ls -la /opt/homebrew/lib/shipd/

# Intel
ls -la /usr/local/lib/shipd/
```

## Resources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)
- [How to Create Taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
