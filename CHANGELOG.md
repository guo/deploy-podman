# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Moved Homebrew formula to tap repository for better package management

## [1.0.5] - 2026-01-XX

### Added
- `inspect` command to view deployment information and version details
- Enhanced deployment version info display

### Improved
- Better visibility into deployed container versions

## [1.0.4] - 2026-01-XX

### Fixed
- Hash check now always pulls latest image from registry
- Prevents deployment skips when remote image is updated with same tag

### Improved
- More reliable image updates for tags like `latest`

## [1.0.3] - 2026-01-XX

### Added
- GitHub Actions CI/CD integration guide
- Complete workflow examples for automated deployments

### Fixed
- Version display and automated version bumping in releases

## [1.0.2] - 2026-01-XX

### Changed
- Minor updates and improvements

## [1.0.1] - 2026-01-XX

### Documentation
- Updated README with clearer instructions
- Improved getting started guide

## [1.0.0] - 2026-01-XX

### Added
- First stable release
- Project renamed to "Shipd"
- Multi-target deployment support with `deploy-multi` command
- Deployment confirmation prompts (with `-y` flag to skip)
- Container change detection to skip unnecessary deployments
- Zero-downtime deployment via Caddy reverse proxy
- Docker and Docker Compose support
- Podman support as default container engine
- Target-based configuration system
- File and port mapping configuration
- GitHub Container Registry authentication
- SSH-based remote deployment
- Multiple deployment methods:
  - Direct deployment (brief downtime)
  - Zero-downtime deployment (Caddy blue-green)
  - Multi-container deployment (Compose)
- Automatic container engine installation
- Health check support for zero-downtime deployments
- Deployment hash tracking

### Features
- Deploy to multiple environments (production, staging, demo)
- Image tag/version management
- Rollback support via tag specification
- Environment variable management via `.env` files
- Volume mounting for configuration files
- Automatic HTTPS via Caddy (when using Caddy deployment)
- Parallel and sequential multi-target deployment
- Support for both Docker and Podman container engines

[Unreleased]: https://github.com/guo/shipd/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/guo/shipd/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/guo/shipd/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/guo/shipd/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/guo/shipd/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/guo/shipd/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/guo/shipd/releases/tag/v1.0.0
