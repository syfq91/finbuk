# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Finbuk is a Flutter **Android** application that serves as a Jellyfin client focused on book and comic reading. It connects to a Jellyfin server, authenticates users, and provides EPUB/comic reading with offline download support.

**Tech Stack**: Flutter 3.10+, Dart, Provider (state management), Dio (HTTP), SQLite (sqflite), flutter_secure_storage

## Development Commands

### Common Tasks
```bash
# Install dependencies
flutter pub get

# Run the app (connected device/emulator required)
flutter run

# Run all tests
flutter test

# Run a specific test file
flutter test test/widget_test.dart

# Run tests matching a name pattern
flutter test --name="App starts without crashing"

# Analyze code for issues
flutter analyze

# Format code
dart format .

# Build release APK for Android
flutter build apk --release

# Build app bundle for Play Store
flutter build appbundle --release
```

## Architecture

### High-Level Structure

The codebase follows a layered architecture with clear separation of concerns:

```
lib/
├── main.dart              # App entry, MultiProvider setup, theme config, AuthWrapper
├── models/                 # Data models (Item)
├── providers/              # State management (ChangeNotifier)
│   ├── auth_provider.dart  # Auth state, credentials storage
│   └── theme_provider.dart # Theme/dark mode state
├── repositories/           # Business logic, data aggregation, caching
│   └── book_repository.dart # Coordinates API + SQLite caching
├── services/              # Low-level operations
│   ├── jellyfin_service.dart  # Jellyfin API client (Dio)
│   ├── database_service.dart  # SQLite operations
│   ├── file_service.dart      # File system operations
│   ├── download_manager.dart  # Download queue/progress
│   └── permission_service.dart # Android permissions
└── screens/               # UI widgets
    ├── main_screen.dart   # Navigation container (bottom bar / rail)
    ├── home_screen.dart   # Dashboard with resume items
    ├── library_screen.dart # Folder/collection browser
    ├── library_items_screen.dart # Items within a folder
    ├── book_details_screen.dart # Book info + actions
    ├── epub_reader_screen.dart # EPUB reader
    ├── comic_reader_screen.dart # CBZ/CBR reader
    ├── downloads_screen.dart # Download management
    ├── settings_screen.dart # App settings
    └── login_screen.dart  # Login form
```

### Data Flow Pattern

1. **Screens** consume data from **Repositories** (via Provider/injection)
2. **BookRepository** orchestrates:
   - Check SQLite cache (via DatabaseService)
   - If cached: return immediately, refresh in background
   - If not cached: call **JellyfinService** API
   - Transform JSON → **Item** models
   - Save to SQLite cache
   - Return data
3. **JellyfinService** handles all HTTP calls with Dio, including:
   - Authentication
   - Library browsing
   - Download URLs
   - Playback progress reporting

### State Management

- **Provider** pattern with `ChangeNotifier`
- `AuthProvider` stores credentials in `flutter_secure_storage` and provides:
  - `isAuthenticated`, `serverUrl`, `token`, `userId`, `username`
  - `login()` method with URL auto-detection (tries https, http, :8096)
  - `logout()` clears token only (keeps username/serverUrl for convenience)
- `ThemeProvider` manages light/dark/system theme mode

### Navigation

- `AuthWrapper` in `main.dart` routes to `MainScreen` or `LoginScreen`
- `MainScreen` uses bottom `NavigationBar` (mobile) or `NavigationRail` (tablet) via `LayoutBuilder`
- Named routes: push with `MaterialPageRoute` for screen transitions
- Settings accessed via profile avatar in AppBar

### Caching Strategy

- SQLite stores items by "category" (e.g., `user_views`, `resume`, `latest_all`, `items_{parentId}`)
- First page of paginated results cached; deeper pages bypass cache
- On API failure, returns cached data if available
- Background refresh after returning cached data

### API Client

- Base Jellyfin client identification: `MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"`
- Headers: `X-Emby-Token` for auth, `X-Emby-Authorization` for client info
- Key endpoints:
  - `/Users/AuthenticateByName` → auth
  - `/Users/{userId}/Views` → library collections (filtered to `CollectionType == 'books'`)
  - `/Users/{userId}/Items` → browse folders/items
  - `/Users/{userId}/Items/Latest` → latest additions
  - `/Items/{itemId}/Download` → file download
  - `/Sessions/Playing` etc. → playback progress

### Reader Notes

- **EPUB**: `flutter_epub_viewer` package (see `epub_reader_screen.dart`)
- **Comics**: `manga_page_view` package with page-by-page navigation (see `comic_reader_screen.dart`)
- Both support offline files from downloads

## Testing

- Widget tests in `test/` using `flutter_test`
- Tests wrap widgets with `MultiProvider` matching `main.dart` setup
- Example pattern: `tester.pumpWidget(MultiProvider(...))` → `tester.pumpAndSettle()` → `find.byType(...)`

## Configuration Files

- `pubspec.yaml`: Dependencies, Flutter SDK ^3.10.8
- `analysis_options.yaml`: Uses `package:flutter_lints/flutter.yaml`
- `android/`: Standard Flutter Android project (gradle properties for build config)

## Important Conventions

- All sensitive data stored in `flutter_secure_storage` (never in SharedPreferences)
- Network calls use error handling that returns empty lists on failure (graceful degradation)
- URL normalization: strip trailing slashes consistently
- `Item` model stores raw JSON in `rawJson` for flexible access to Jellyfin fields
- Images: use `cached_network_image` for remote, with auth headers when needed

## Notes for Development

- When working on API changes, update `JellyfinService` methods first, then repositories, then screens
- Add new screens to the appropriate navigation (MainScreen tabs or separate push)
- For new cached data, decide on a "category" key for SQLite storage
- Theme colors use `ColorScheme.fromSeed(seedColor: Colors.deepPurple)` - modify in `main.dart`
- The app assumes books/comics only; `getUserViews` filters `CollectionType == 'books'`
