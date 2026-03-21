# Finbuk

A modern Flutter **Android** application client for [Jellyfin](https://jellyfin.org/) that focuses on book and comic reading.

> **Note**: This app is currently Android-only.

## Features

- **Jellyfin Integration**: Connect to any Jellyfin server to access your personal media library
- **Authentication**: Secure login with credential storage using flutter_secure_storage
- **Comic Reader**: Manga/comic reader with page-by-page navigation and zoom support
  - Loading state displays book title
- **Offline Downloads**: Download books for offline reading with progress tracking
- **Library Organization**: Browse by collections, folders, and categories
- **Local Database**: SQLite-based caching for faster library loading and download management
- **Dark/Light Theme**: Material Design 3 with dynamic theme switching
- **Responsive UI**: Intuitive navigation with bottom tab bar and navigation rail
- **Android-Only**: Optimized for Android with core library desugaring for modern Java compatibility

## Tech Stack

- **Framework**: Flutter 3.10+
- **Language**: Dart
- **State Management**: Provider
- **API**: Dio for Jellyfin API communication
- **Local Storage**: SQLite (sqflite), SharedPreferences, FlutterSecureStorage
- **Readers**: manga_page_view (comics/manga)
- **File Handling**: file_picker, permission_handler, path

## Project Structure

```
lib/
├── main.dart                     # App entry point, MultiProvider setup, AuthWrapper
├── models/                       # Data models
│   └── item.dart                # Media item model with rawJson
├── providers/                    # State management (ChangeNotifier)
│   ├── auth_provider.dart       # Auth state, credentials in flutter_secure_storage
│   └── theme_provider.dart      # Theme/dark mode state
├── repositories/                 # Business logic, data aggregation, caching
│   └── book_repository.dart     # Coordinates API + SQLite caching
├── services/                     # Low-level operations
│   ├── jellyfin_service.dart    # Jellyfin API client (Dio)
│   ├── database_service.dart    # SQLite operations
│   ├── file_service.dart        # File system operations
│   ├── download_manager.dart    # Download queue/progress
│   └── permission_service.dart  # Android permissions requests
└── screens/                      # UI widgets
    ├── main_screen.dart         # Navigation container (bottom bar / rail)
    ├── home_screen.dart         # Dashboard with resume items
    ├── library_screen.dart      # Folder/collection browser
    ├── library_items_screen.dart # Items within a folder
    ├── book_details_screen.dart # Book info + actions
    ├── comic_reader_screen.dart # CBZ/CBR reader with manga_page_view
    ├── downloads_screen.dart    # Download management
    ├── settings_screen.dart     # App settings
    └── login_screen.dart        # Login form
```

## Getting Started

### Prerequisites

- Flutter SDK (>=3.10.8)
- Android Studio / VS Code with Flutter extensions
- A Jellyfin server with book/comic libraries

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/syfq91/finbuk.git
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
- Has user libraries containing comics (CBZ, CBR formats)

### Supported Formats

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

## Development Notes

- Uses Material Design 3 with dynamic color theming
- All sensitive data (credentials, tokens) stored securely with flutter_secure_storage
- SQLite database caches library items to reduce API calls
- Download manager supports pause/resume and progress tracking
- Permission handling for storage access on Android
- Core library desugaring enabled for Java 17 compatibility (android/app/build.gradle.kts)

## Dependencies

Key dependencies:
- `dio`: HTTP client for Jellyfin API
- `manga_page_view`: Comic/manga page viewing
- `sqflite`: Local database for caching
- `provider`: State management
- `flutter_secure_storage`: Secure credential storage
- `cached_network_image`: Optimized image loading

See [pubspec.yaml](pubspec.yaml) for complete dependency list.

## License

[MIT License](LICENSE)

## Acknowledgments

- [Jellyfin](https://jellyfin.org/) - Free and open-source media server
- Flutter community for excellent packages and documentation
