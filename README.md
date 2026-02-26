# Finbuk

A modern Flutter mobile application client for [Jellyfin](https://jellyfin.org/) that focuses on book and comic reading.

## Features

- **Jellyfin Integration**: Connect to any Jellyfin server to access your personal media library
- **Authentication**: Secure login with credential storage using flutter_secure_storage
- **EPUB Reader**: Full-featured EPUB reading experience with chapter navigation
- **Comic Reader**: Manga/comic reader with page-by-page navigation and zoom support
- **Offline Downloads**: Download books for offline reading with progress tracking
- **Library Organization**: Browse by collections, folders, and categories
- **Local Database**: SQLite-based caching for faster library loading and download management
- **Dark/Light Theme**: Material Design 3 with dynamic theme switching
- **Responsive UI**: Intuitive navigation with bottom tab bar and drawer menus

## Tech Stack

- **Framework**: Flutter 3.10+
- **Language**: Dart
- **State Management**: Provider
- **API**: Dio for Jellyfin API communication
- **Local Storage**: SQLite (sqflite), SharedPreferences, FlutterSecureStorage
- **Readers**: flutter_epub_viewer (EPUB), manga_page_view (comics/manga)
- **File Handling**: file_picker, permission_handler, path

## Project Structure

```
lib/
├── main.dart              # App entry point, theme configuration
├── models/                 # Data models
│   └── item.dart          # Media item model
├── screens/               # UI screens
│   ├── home_screen.dart
│   ├── library_screen.dart
│   ├── library_items_screen.dart
│   ├── book_details_screen.dart
│   ├── epub_reader_screen.dart
│   ├── comic_reader_screen.dart
│   ├── downloads_screen.dart
│   ├── settings_screen.dart
│   ├── login_screen.dart
│   └── main_screen.dart   # Main navigation container
├── providers/             # State management
│   ├── auth_provider.dart
│   └── theme_provider.dart
└── services/              # Business logic
    ├── jellyfin_service.dart  # Jellyfin API client
    ├── database_service.dart  # SQLite operations
    ├── file_service.dart      # File system operations
    ├── download_manager.dart  # Download management
    └── permission_service.dart # Device permissions
```

## Getting Started

### Prerequisites

- Flutter SDK (>=3.10.8)
- Android Studio / VS Code with Flutter extensions
- A Jellyfin server with book/comic libraries

### Installation

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

## Configuration

The app connects to a Jellyfin server specified during login. Ensure your Jellyfin server:
- Is accessible from your device
- Has user libraries containing books/comics (EPUB, PDF, CBZ, CBR formats)

### Supported Formats

- **EPUB**: `.epub`
- **Comics/Manga**: `.cbz`, `.cbr` (via archive extraction)
- **Images**: `.jpg`, `.jpeg`, `.png`, `.webp` for comic pages

## Building

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## Development Notes

- Uses Material Design 3 with dynamic color theming
- All sensitive data (credentials, tokens) stored securely with flutter_secure_storage
- SQLite database caches library items to reduce API calls
- Download manager supports pause/resume and progress tracking
- Permission handling for storage access on Android

## Dependencies

Key dependencies:
- `dio`: HTTP client for Jellyfin API
- `flutter_epub_viewer`: EPUB rendering
- `manga_page_view`: Comic/manga page viewing
- `sqflite`: Local database for caching
- `provider`: State management
- `flutter_secure_storage`: Secure credential storage
- `cached_network_image`: Optimized image loading

See [pubspec.yaml](pubspec.yaml) for complete dependency list.

## License

[MIT License](LICENSE) (add license file if applicable)

## Acknowledgments

- [Jellyfin](https://jellyfin.org/) - Free and open-source media server
- Flutter community for excellent packages and documentation
