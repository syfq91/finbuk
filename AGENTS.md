# AGENTS.md

Guidance for AI coding assistants working in this repository.

## Project Overview

Finbuk is a Flutter **Android-only** Jellyfin client for reading comics (CBZ) and EPUBs, and playing video and audio (Music/Audiobooks), with offline support. It connects to a Jellyfin server, authenticates users, and provides a premium experience with local caching and download capabilities.

- **Tech Stack**: Flutter 3.10+, Dart, Provider (state management), Dio (HTTP), SQLite (sqflite), flutter_secure_storage
- **Build**: Java 21 with core library desugaring enabled
- **Target OS**: Android only (iOS is NOT supported)
- **Reading Engine**: flureadium (Readium toolkit) for both comics and EPUBs
- **Media Engine**: media_kit for Video, Music, and Audiobook playback

## Development Commands

```bash
# Install dependencies
flutter pub get

# Run the app (connected device/emulator required)
flutter run

# Run all tests
flutter test

# Analyze code for issues
flutter analyze

# Format code
dart format .

# Build release APK for Android
flutter build apk --release
```

## Architecture & Navigation

The codebase follows a layered architecture: **screens → repositories → services** (never skip layers).

### Directory Structure

- `lib/main.dart`: App entry, MultiProvider setup, theme config, AuthWrapper
- `lib/models/`: Data models (notably `item.dart` which wraps Jellyfin JSON)
- `lib/providers/`: State management (`AuthProvider`, `ThemeProvider`)
- `lib/repositories/`: Business logic, data aggregation, caching (`BookRepository`)
- `lib/services/`: Low-level operations
  - `jellyfin_service.dart`: Jellyfin API client (Dio)
  - `database_service.dart`: SQLite operations
  - `file_service.dart`: File system operations
  - `download_manager.dart`: Background download queue with progress
- `lib/screens/`: UI widgets and screen layouts

### Key Files
- `lib/services/jellyfin_service.dart`: All API interactions.
- `lib/services/download_manager.dart`: Singleton managing download tasks and streams.
- `lib/services/file_service.dart`: Handles file I/O and path resolution.

## Code Conventions

- **State Management**: Use `ChangeNotifier` + `Provider`. Never use `setState` outside of simple UI toggles.
- **Auth Access**: Always get via `Provider.of<AuthProvider>(context, listen: false)` or `context.watch<AuthProvider>()`.
- **Null Safety**: Avoid `!` on nullable fields. Use `?.` or check before use.
- **Async**: Prefer `try/catch` over `.catchError()`. Always check `mounted` before `setState`.
- **Error Handling**: GET endpoints should return empty lists on failure (graceful degradation); POSTs should throw.
- **Images**: Use `CachedNetworkImage` with `httpHeaders: {'X-Emby-Token': auth.token!}`.
- **URL Normalization**: Strip trailing slashes consistently in all service methods.
- **Constants**: Keep magic strings (API fields, cache categories) in one place if possible.

## Data Flow & Patterns

### Data Flow
1. **Screens** consume data from **Repositories** (via Provider).
2. **BookRepository** orchestrates:
   - Check SQLite cache (via `DatabaseService`).
   - If cached: return immediately, refresh in background.
   - If not cached: call `JellyfinService` API, transform JSON → `Item` models, save to cache, return data.
3. **JellyfinService** handles all HTTP calls with Dio (Auth, Library, Downloads, Progress).

### Adding a new API call
1. Add method to `JellyfinService`.
2. Add wrapper to `BookRepository` with caching logic.
3. Consume in screen via `FutureBuilder` or `StreamBuilder`.

### Adding a new screen
1. Create widget in `lib/screens/new_screen.dart`.
2. Add route in `main.dart` or push via `MaterialPageRoute`.
3. If a main tab, add to `MainScreen` navigation lists.

### Caching Strategy
1. Choose a unique `category` string (e.g., `"my_new_data"`).
2. Use `BookRepository` or add a new repository method.
3. The `DatabaseService` pattern: `getItemsByCategory(category, parentId?)` / `saveItems(items, category)`.
4. Composite PK `(id, category)` in SQLite allows the same item in multiple cache categories.

### Download Feature
1. `DownloadManager` is a singleton - use `DownloadManager()` constructor.
2. Start: `DownloadManager().startDownload(...)`.
3. Listen: `DownloadManager().getDownloadStream(itemId)`.
4. Cancel: `DownloadManager().cancelDownload(itemId)`.
5. File I/O MUST go through `FileService`, never directly. Books are stored in internal app storage.

## Testing

- Tests are in `test/` using `flutter_test`.
- Wrap widgets with `MultiProvider` including `AuthProvider` and `ThemeProvider`.
- To test a screen that needs auth, set up `AuthProvider` first and `pumpWidget`.
- Adding tests for `BookRepository` and `JellyfinService` is high priority.

## What to Avoid

- **Do not** introduce new state management (no BLoC, no Riverpod, no GetX).
- **Do not** add iOS support changes (Android-only app).
- **Do not** store credentials in SharedPreferences (always use `flutter_secure_storage`).
- **Do not** disable core library desugaring in `android/app/build.gradle.kts`.
- **Do not** use raw `http` package directly - always go through `Dio` via `JellyfinService`.
- **Do not** change the SQLite schema without incrementing version and adding `onUpgrade`.
- **Do not** revert `analysis_options.yaml` strict checks. The project uses rigorous linting (`unreachable_from_main`, strict-casts, strict-inference) for best practices.

## Key Decisions

- `Item.rawJson`: Intentional to allow screens access to any Jellyfin field without model updates.
- `BookRepository` methods take URL/userId/token as params (not `context`) to remain testable.
- `ComicReaderScreen` modifies `SystemChrome` in `initState`/`dispose` for immersive mode.
- `DownloadManager` uses internal stream controllers per item to survive widget rebuilds.
- Background cache refresh is "fire-and-forget" (don't await the API call after returning cached data).
- **Reader Implementation (Readium/Flureadium)**:
    - Both `ComicReaderScreen` and `EpubReaderScreen` use `ReadiumReaderWidget`.
    - `ReadiumReaderWidget` MUST NOT be wrapped in `GestureDetector` or other gesture-intercepting widgets as it interferes with Android's native platform view rendering (Hybrid Composition).
    - EventChannel subscriptions (`onTextLocatorChanged`, `onErrorEvent`, `onLocatorChanged`) MUST be performed inside the `onReady` callback of `ReadiumReaderWidget` to ensure native channels are registered before listening.
    - EPUB preferences also must be applied after the native reader is ready; queue updates rather than calling `setEPUBPreferences` too early.
    - Android's `MainActivity` MUST extend `FlutterFragmentActivity` for the reader to function.
    - Hardware acceleration MUST be enabled in `AndroidManifest.xml`.
- **Media Player Implementation (media_kit)**:
    - Video/Audio playback relies on `media_kit`. Ensure `MediaKit.ensureInitialized()` runs in `main.dart`.
    - `Player` and `VideoController` instances must be correctly initialized in `initState` and actively disposed in `dispose` to prevent memory leaks.
