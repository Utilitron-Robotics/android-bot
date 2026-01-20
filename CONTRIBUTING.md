# Contributing to RobotOS Pro

Thank you for your interest in contributing to RobotOS Pro! This document provides guidelines for contributing to the project.

## Project Structure

This project contains two separate applications:

| App | Location | Language | Purpose |
|-----|----------|----------|---------|
| **Relay App** | `relay_app/` | Kotlin | Android tablet bridge (gRPC ↔ rosbridge) |
| **Flutter App** | `flutter_app/` | Dart | Cross-platform control UI |

**Important**: These are separate apps with different build systems. Don't confuse them.

## Development Setup

### Flutter App

```bash
cd flutter_app
flutter pub get
flutter run -d chrome  # For web development
```

### Relay App

1. Open `relay_app/` in Android Studio
2. Let Gradle sync
3. Connect to a robot tablet or emulator
4. Hit Run

## Making Changes

### Before You Start

1. Read `CLAUDE.md` for project context and architecture
2. Understand the transport layer (gRPC primary, WebSocket fallback)
3. Check existing issues and PRs

### Code Style

**Flutter/Dart:**
- Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Run `flutter analyze` before committing
- Use meaningful variable and function names

**Kotlin:**
- Follow [Kotlin Coding Conventions](https://kotlinlang.org/docs/coding-conventions.html)
- Use Android Studio's built-in formatter

### Commit Guidelines

- Write clear, concise commit messages
- Reference issue numbers when applicable
- Keep commits focused on single changes

### Testing

**Flutter App:**
```bash
cd flutter_app
flutter test
```

**Relay App:**
```bash
cd relay_app
./gradlew test
```

### Before Submitting

1. Test your changes on actual hardware when possible
2. Ensure both apps still build successfully
3. Update documentation if you've changed behavior
4. Run linters and fix any issues

## Architecture Guidelines

### Transport Layer

- gRPC is the primary protocol (WAN-ready, reliable)
- WebSocket is the LAN fallback
- HTTP REST is the last resort
- **Never** try to use gRPC on web/Chrome (use WebSocket instead)

### Relay Design Principle

The relay app follows a "buffer only" architecture:
- **Relay = Command queue** (no business logic)
- **Flutter = Brain** (all decision-making, retries, etc.)

See `BUFFER_ARCHITECTURE.md` for details.

### Key Files

When making significant changes, understand these files first:

**Flutter:**
- `lib/core/unified_transport.dart` - Transport selection
- `lib/core/grpc_client.dart` - gRPC client
- `lib/core/robot_connection.dart` - State management

**Relay:**
- `service/RelayService.kt` - Main service orchestrator
- `grpc/RobotControlServiceImpl.kt` - gRPC implementation
- `service/CommandBuffer.kt` - Command queue

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Test thoroughly
5. Submit a PR with a clear description

### PR Description Template

```markdown
## Summary
Brief description of changes

## Changes
- Change 1
- Change 2

## Testing
How was this tested?

## Related Issues
Fixes #123
```

## Reporting Issues

When reporting bugs, include:
- Device/platform information
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (filter with `adb logcat | grep -E "Relay|Grpc|Robot"`)

## Questions?

- Check existing documentation in `docs/`
- Review `CLAUDE.md` for common issues
- Open an issue for discussion

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
