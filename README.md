# Finbuk

A modern Flutter **Android** application client for [Jellyfin](https://jellyfin.org/) focused on book and comic reading with offline support.

> **Note**: This app is currently Android-only.

## Features

- **Jellyfin Integration**: Connect to any Jellyfin server to access your personal media library
- **Secure Authentication**: Login with username/password, credentials stored securely via `flutter_secure_storage`
- **Library Browsing**: Browse collections, folders, and view latest additions with cover art
- **Comic Reader**: Readium-based CBZ/CBR reader with page navigation, progress tracking, and immersive fullscreen mode
- **Offline Downloads**: Download books for offline reading with concurrent download queue, progress tracking, and pause/resume support
- **Favorites & Read Status**: Mark items as favorite or played/unplayed
- **Local Database**: SQLite-based caching for faster library loading and download management
- **Dark/Light/System Theme**: Material Design 3 with dynamic theme switching
- **Responsive UI**: Adaptive layout with bottom navigation bar (mobile) or navigation rail (tablet/desktop)
- **Playback Progress**: Reports reading progress back to Jellyfin server

## Tech Stack

- **Framework**: Flutter 3.10+ (Android-only)
- **Language**: Dart
- **State Management**: Provider (ChangeNotifier)
- **HTTP Client**: Dio
- **Local Storage**: SQLite (sqflite), SharedPreferences, flutter_secure_storage, path_provider
- **Comic Reader**: flureadium (Readium toolkit)
- **Build**: Java 17 with core library desugaring

## Prerequisites

- Flutter SDK (>=3.10.8)
- Android Studio or VS Code with Flutter extensions
- A Jellyfin server with book/comic libraries

## Getting Started

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd finbuk
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Supported Formats

- **Comics**: `.cbz` (native Readium support via flureadium)
- **Coming**: `.cbr` support, `.epub` support

## Building

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle
```bash
flutter build appbundle --release
```

## Project Structure

```
lib/
├── main.dart                     # App entry, MultiProvider, AuthWrapper
├── models/                        # Data models (Item)
├── providers/                     # State management (AuthProvider, ThemeProvider)
├── repositories/                  # Business logic, API + SQLite caching
├── screens/                       # UI screens (Home, Library, Reader, etc.)
└── services/                      # Low-level operations (API, DB, files, downloads)
```

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation.

## Development

- Uses Material Design 3 with `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`
- All sensitive data stored in `flutter_secure_storage` (never in SharedPreferences)
- SQLite caches library items to reduce API calls
- Download manager supports up to 3 concurrent downloads with queue management
- Core library desugaring enabled for Java 17 compatibility

## Dependencies

Key dependencies:

- `dio`: HTTP client for Jellyfin API communication
- `flureadium`: Readium-based comic/book reading engine
- `sqflite` + `sqlite3_flutter_libs`: Local SQLite database for caching
- `provider`: Reactive state management
- `flutter_secure_storage`: Secure credential and token storage
- `cached_network_image`: Optimized image loading with auth headers
- `path_provider`: Access to internal app storage directories

See [pubspec.yaml](pubspec.yaml) for the complete dependency list.

## Contributing

Contributions are welcome. When making changes:

1. Follow the existing layered architecture (screens → repositories → services)
2. Run `flutter analyze` before committing
3. Format code with `dart format .`
4. Add tests for new features

## License

[MIT License](LICENSE)

## Acknowledgments

- [Jellyfin](https://jellyfin.org/) - Free and open-source media server
- [Readium](https://readium.org/) - Open-source toolkit for digital publications
- Flutter community for excellent packages and documentation
