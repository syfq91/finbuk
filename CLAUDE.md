# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Finbuk is a Flutter **Android** application that serves as a Jellyfin client focused on comic reading. It connects to a Jellyfin server, authenticates users, and provides comic reading with offline download support.

**Tech Stack**: Flutter 3.10+, Dart, Provider (state management), Dio (HTTP), SQLite (sqflite), flutter_secure_storage
**Build**: Java 17 with core library desugaring enabled

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
├── main.dart                      # App entry, MultiProvider setup, theme config, AuthWrapper
├── models/                        # Data models
│   └── item.dart                 # Media item model (stores rawJson)
├── providers/                     # State management (ChangeNotifier)
│   ├── auth_provider.dart        # Auth state, credentials in flutter_secure_storage
│   └── theme_provider.dart       # Theme/dark mode state
├── repositories/                  # Business logic, data aggregation, caching
│   └── book_repository.dart      # Coordinates API + SQLite caching
├── services/                      # Low-level operations
│   ├── jellyfin_service.dart     # Jellyfin API client (Dio)
│   ├── database_service.dart     # SQLite operations
│   ├── file_service.dart         # File system operations
│   ├── download_manager.dart     # Download queue/progress
│   └── permission_service.dart   # Android permissions
└── screens/                       # UI widgets
    ├── main_screen.dart          # Navigation container (bottom bar / rail)
    ├── home_screen.dart          # Dashboard with resume items
    ├── library_screen.dart       # Folder/collection browser
    ├── library_items_screen.dart # Items within a folder
    ├── book_details_screen.dart  # Book info + actions
    ├── comic_reader_screen.dart  # CBZ/CBR reader (manga_page_view)
    ├── downloads_screen.dart     # Download management
    ├── settings_screen.dart      # App settings
    └── login_screen.dart         # Login form
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

### Repository Public API

BookRepository provides the following methods (all return `Future<List<Item>>` or `Future<Map<String, dynamic>>`):

| Method | Purpose | Cache Category |
|--------|---------|----------------|
| `getUserViews()` | Library collections | `user_views` |
| `getResumeItems()` | Books in progress | `resume` |
| `getLatestMedia(parentId?)` | Latest additions | `latest_{parentId}` or `latest_all` |
| `getItems(parentId, recursive, limit, startIndex)` | Browse folders/items | `items_{parentId}_{recursive}` (first page only) |
| `getItemDetails(itemId)` | Item metadata | `details` |
| All methods support `forceRefresh` parameter to bypass cache |

### State Management

- **Provider** pattern with `ChangeNotifier`
- `AuthProvider` stores credentials in `flutter_secure_storage` and provides:
  - `isAuthenticated`, `serverUrl`, `token`, `userId`, `username`, `downloadPath`
  - `login(url, username, password)` with URL auto-detection (tries https, http, :8096)
  - `logout()` clears token only (keeps username/serverUrl for convenience)
  - `setDownloadPath(path)` persists download location
- `ThemeProvider` manages light/dark/system theme mode (`themeMode`)

### Navigation

- `AuthWrapper` in `main.dart` routes to `MainScreen` or `LoginScreen`
- `MainScreen` uses bottom `NavigationBar` (mobile) or `NavigationRail` (tablet) via `LayoutBuilder`
- Named routes: push with `MaterialPageRoute` for screen transitions
- Settings accessed via profile avatar in AppBar

### Caching Strategy

- SQLite stores items by "category" (e.g., `user_views`, `resume`, `latest_all`, `items_{parentId}`)
- First page of paginated results cached; deeper pages bypass cache
- On API failure, returns cached data if available
- Background refresh after returning cached data (fire-and-forget)

### Database Schema

**Table: `items`**
| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT | Jellyfin item ID (part of composite PK) |
| `name` | TEXT | Item display name |
| `type` | TEXT | Jellyfin type (Book, Folder, etc.) |
| `collectionType` | TEXT | Collection category (books) |
| `parentId` | TEXT | Parent folder ID |
| `category` | TEXT | Cache category key (part of composite PK) |
| `json` | TEXT | Full item JSON (serialized) |
| `updatedAt` | INTEGER | Timestamp for ordering |

Composite PK: `(id, category)` - allows same item in multiple cache categories.

**Table: `downloads`**
| Column | Type | Description |
|--------|------|-------------|
| `itemId` | TEXT | Jellyfin item ID (PK) |
| `filename` | TEXT | Local filename |
| `downloadedAt` | INTEGER | Download timestamp |

Database version: 2 (downloads table added in v2).

### API Client

- Base Jellyfin client identification: `MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"`
- Headers: `X-Emby-Token` for auth, `X-Emby-Authorization` for client info
- Key endpoints:
  - `/Users/AuthenticateByName` → auth
  - `/Users/{userId}/Views` → library collections (filtered to `CollectionType == 'books'`)
  - `/Users/{userId}/Items` → browse folders/items
  - `/Users/{userId}/Items/Latest` → latest additions
  - `/Items/{itemId}/Download` → file download
  - `/Sessions/Playing` → playback progress reporting

All GET endpoints return `[]` on failure (graceful degradation). POST endpoints throw exceptions.

### Item Model

The `Item` class wraps Jellyfin JSON responses:

```dart
class Item {
  final String id;
  final String? name;
  final String? type;
  final String? collectionType;
  final Map<String, dynamic>? userData;
  final String? parentId;
  final double? primaryImageAspectRatio;
  final String? sortName;
  final Map<String, dynamic> rawJson; // Full original JSON
}
```

- `rawJson` preserves all Jellyfin fields for flexible access in screens
- `fromJson()` maps common fields; unknown fields stay in `rawJson`
- `toDbMap(category)` serializes for SQLite storage
- `fromDbMap()` reconstructs from database

### Reader Notes

- **Comics**: `manga_page_view` package with page-by-page navigation
  - Loading state displays book title
  - See `comic_reader_screen.dart` for implementation
- Supports offline files from downloads

## Testing

- Widget tests in `test/` using `flutter_test`
- Tests wrap widgets with `MultiProvider` matching `main.dart` setup
- Standard pattern:
  ```dart
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const FinbukApp(),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(MaterialApp), findsOneWidget);
  ```
- To test a screen directly, match the provider setup in your app
- Current tests: basic smoke tests (app startup, title, theme configuration)

## Configuration Files

- `pubspec.yaml`: Dependencies, Flutter SDK ^3.10.8
- `analysis_options.yaml`: Uses `package:flutter_lints/flutter.yaml`
- `android/app/build.gradle.kts`: Android build config with:
  - Java 17 compatibility (sourceCompatibility, targetCompatibility = VERSION_17)
  - Core library desugaring enabled (`isCoreLibraryDesugaringEnabled = true`)
  - Kotlin JVM target 17

## Important Conventions

- All sensitive data stored in `flutter_secure_storage` (never in SharedPreferences)
- Network calls use error handling that returns empty lists on failure (graceful degradation)
- URL normalization: strip trailing slashes consistently in all service methods
- `Item` model stores raw JSON in `rawJson` for flexible access to Jellyfin fields
- Images: use `cached_network_image` for remote, with auth headers when needed (see `JellyfinService.getPageImageUrl()`)
- Background cache refresh: fire-and-forget `.then()` without awaiting, errors silently caught
- Composite cache keys: `category` + optional `parentId` in items table

## Android-Specific Notes

- Android-only app (iOS not supported)
- Core library desugaring required for Java 17 features - do not disable
- Permissions handled via `permission_handler` (storage access for downloads)
- Download paths stored securely; use `AuthProvider.downloadPath` to retrieve

## Notes for Development

- When working on API changes, update `JellyfinService` methods first, then repositories, then screens
- Add new screens to the appropriate navigation (MainScreen tabs or separate push)
- For new cached data, decide on a "category" key for SQLite storage
- Theme colors use `ColorScheme.fromSeed(seedColor: Colors.deepPurple)` - modify in `main.dart`
- The app assumes books/comics only; `getUserViews` filters `CollectionType == 'books'`
- URL auto-detection in login: tries https://, http://, then http://:8096
- All pagination parameters: `parentId`, `recursive`, `limit`, `startIndex`
