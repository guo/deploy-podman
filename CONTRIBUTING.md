# Contributing to Shipd

Thank you for your interest in contributing to Shipd! This document provides guidelines and instructions for contributing.

## Ways to Contribute

- Report bugs and issues
- Suggest new features or improvements
- Improve documentation
- Submit pull requests with bug fixes or features
- Share your deployment use cases and examples

## Getting Started

### Prerequisites

- Bash shell environment
- SSH access to a test server (for testing deployments)
- Docker or Podman installed on test server
- Git for version control

### Development Setup

```bash
# Clone the repository
git clone https://github.com/guo/shipd.git
cd shipd

# Run directly from source (no installation needed)
./shipd.sh --help

# Create a test target
mkdir -p targets/test-app
cp targets/example/.config targets/test-app/.config
cp targets/example/.env targets/test-app/.env
# Edit the .config and .env files for your test environment

# Test deployment
./shipd.sh deploy test-app
```

## Making Changes

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring

### Code Style

- Follow existing code style and conventions
- Use clear, descriptive variable names in SCREAMING_SNAKE_CASE
- Add comments for complex logic
- Keep functions focused and single-purpose
- Use `set -e` for error handling in scripts
- Test your changes on both Podman and Docker if applicable

### Shell Script Guidelines

- Use bash (not sh) features when helpful
- Quote variables to prevent word splitting: `"${VARIABLE}"`
- Check for required variables before using them
- Provide helpful error messages
- Use `readonly` for constants
- Avoid global variables when possible

## Testing

Before submitting a PR, test your changes:

### Manual Testing

```bash
# Test single-container deployment
./shipd.sh deploy test-app

# Test multi-target deployment
./shipd.sh deploy-multi --all

# Test Caddy deployment (if applicable)
./shipd.sh setup-caddy test-app
./shipd.sh deploy test-app  # with USE_CADDY="true"

# Test both Docker and Podman if your change affects both
```

### Test Different Scenarios

- Fresh installation (no container engine installed)
- Existing container updates
- Image tag changes
- Port and file mappings
- Error conditions (invalid config, SSH failure, etc.)

## Submitting Changes

### Pull Request Process

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Test thoroughly (see Testing section)
5. Commit with clear, descriptive messages
6. Push to your fork
7. Open a Pull Request

### Pull Request Guidelines

- Provide a clear description of what the PR does
- Reference any related issues (Fixes #123)
- Include testing steps or evidence
- Keep PRs focused on a single change
- Update documentation if needed
- Add examples if introducing new features

### Commit Messages

Follow conventional commit format:

```
type(scope): brief description

Longer explanation if needed

Fixes #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Test additions or changes
- `chore`: Maintenance tasks

Examples:
```
feat(deploy): add support for custom health check endpoints

fix(caddy): handle port conflicts during blue-green deployment

docs(readme): add troubleshooting section for SSH issues
```

## Reporting Issues

### Bug Reports

Include:
- Clear description of the issue
- Steps to reproduce
- Expected behavior vs actual behavior
- Your environment (OS, Bash version, Docker/Podman version)
- Relevant config files (remove sensitive data)
- Error messages and logs

### Feature Requests

Include:
- Clear description of the feature
- Use case and problem it solves
- Proposed implementation (if you have ideas)
- Examples of how it would work

## Documentation

- Update README.md for user-facing changes
- Update CLAUDE.md for architectural changes
- Add examples for new features
- Keep documentation clear and concise
- Test documentation steps to ensure they work

## Good First Issues

Look for issues labeled `good first issue` if you're new to the project. These are typically:
- Small bug fixes
- Documentation improvements
- Adding examples
- Improving error messages

## Questions?

- Open a GitHub issue for questions
- Check existing issues and documentation first
- Be respectful and patient

## Code of Conduct

- Be respectful and welcoming
- Focus on the code, not the person
- Accept constructive criticism gracefully
- Help others learn and grow

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing to Shipd!
