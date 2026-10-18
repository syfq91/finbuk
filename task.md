# Finbuk Development Task List

**Status**: Active  
**Last Updated**: 2026-10-15  
**Related Audit**: [Finbuk Codebase Audit Report](file:///home/syafiq/.gemini/antigravity-cli/brain/32146bb8-428c-43e5-9c50-cbbeb2c2bc0f/audit_report.md)

---

## Progress Overview

| Phase | Description | Status | Total | Done | In Progress | Pending |
|---|---|:---:|:---:|:---:|:---:|:---:|
| **Phase 1** | Compilation Blockers & Navigation | 🟢 Complete | 7 | 7 | 0 | 0 |
| **Phase 2** | Media Playback & Offline Downloads | 🟢 Complete | 4 | 4 | 0 | 0 |
| **Phase 3** | Architecture, Concurrency & Performance | 🟢 Complete | 5 | 5 | 0 | 0 |
| **Phase 4** | Policy, Database & Test Coverage | 🟢 Complete | 4 | 4 | 0 | 0 |
| **Total** | | | **20** | **20** | **0** | **0** |

---

## Phase 1: Compilation Blockers & Navigation (P0)

Resolve missing files, navigation state locking, and authentication crashes to bring the app into a clean buildable state.

- [x] **Task 1.1: Implement [`MusicPlayerProvider`](lib/providers/music_player_provider.dart)**
  - Path: `lib/providers/music_player_provider.dart`
  - Requirements:
    - Wrap `media_kit` `Player` with `ChangeNotifier`.
    - Provide getters: `currentItem` (`Map<String, dynamic>?`), `player`, `position` (`Duration`), `duration` (`Duration`), `isPlaying` (`bool`), `isFullPlayerOpen` (`bool`).
    - Provide methods: `play({required Map<String, dynamic> item, required String serverUrl, required String token, String? localFilePath})`, `seek(Duration position)`, `togglePlayPause()`, `setFullPlayerOpen(bool open)`.
    - Handle background playback and notification controls if applicable.

- [x] **Task 1.2: Implement [`HomepageProvider`](lib/providers/homepage_provider.dart)**
  - Path: `lib/providers/homepage_provider.dart`
  - Requirements:
    - Manage homepage section ordering (`sectionOrder: List<String>`) and visibility (`hiddenSections: Set<String>`).
    - Persist settings to `SharedPreferences` keys (`homepage_section_order`, `homepage_hidden_sections`).
    - Provide methods: `syncAvailableSections(List<String> availableIds)`, `isSectionVisible(String id)`, `toggleSectionVisibility(String id)`, `reorderSections(int oldIndex, int newIndex)`.

- [x] **Task 1.3: Implement [`FloatingMiniPlayer`](lib/widgets/floating_mini_player.dart)**
  - Path: `lib/widgets/floating_mini_player.dart`
  - Requirements:
    - Consume `MusicPlayerProvider`. If `currentItem == null` or `isFullPlayerOpen == true`, return `SizedBox.shrink()`.
    - Render a compact bottom card displaying album thumbnail, track title, artist name, and quick play/pause button.
    - On tap, push [`MusicPlayerScreen`](lib/screens/music_player_screen.dart) using optional `navigatorKey` or current `Navigator`.

- [x] **Task 1.4: Implement [`HomepageSettingsScreen`](lib/screens/homepage_settings_screen.dart)**
  - Path: `lib/screens/homepage_settings_screen.dart`
  - Requirements:
    - Scaffold with AppBar titled "Customize Homepage".
    - `ReorderableListView` using drag handles to reorder library sections.
    - Switch controls per row to toggle visibility via `HomepageProvider`.

- [x] **Task 1.5: Implement [`MusicLibraryScreen`](lib/screens/music_library_screen.dart)**
  - Path: `lib/screens/music_library_screen.dart`
  - Requirements:
    - Display sub-categories for Jellyfin Music libraries (Artists, Albums, Songs, Genres).
    - Route sub-categories into [`LibraryItemsScreen`](lib/screens/library_items_screen.dart) with appropriate item types (`MusicArtist`, `MusicAlbum`, `Audio`).

- [x] **Task 1.6: Fix Navigation Root Lock in [`_AppNavigatorObserver`](lib/main.dart)**
  - Path: `lib/main.dart`
  - Requirements:
    - Replace `previousRoute == null` on `didPop` with `previousRoute?.isFirst == true`.
    - Correct `didPush` and `didReplace` to accurately reflect when the top route is the root route.

- [x] **Task 1.7: Guard Unsafe Null Assertions in [`AuthProvider.login`](lib/providers/auth_provider.dart)**
  - Path: `lib/providers/auth_provider.dart`
  - Requirements:
    - Check that `token != null && userId != null` before writing to `_secureStorage`.
    - Provide fallback values or throw clean exceptions rather than throwing uncaught `TypeError` via `!`.

---

## Phase 2: Core Media Playback & Offline Downloads (P0/P1)

Fix offline media support, file format detection, and media player progress tracking.

- [x] **Task 2.1: Expand [`FileService.getExtension`](lib/services/file_service.dart) for Video and Audio**
  - Path: `lib/services/file_service.dart`
  - Requirements:
    - Support Video extensions: `.mp4`, `.mkv`, `.webm`, `.avi`, `.mov`.
    - Support Audio extensions: `.mp3`, `.flac`, `.m4a`, `.m4b`, `.aac`, `.ogg`, `.opus`.
    - Fallback to inspecting `Path` extension if `Container` is ambiguous.

- [x] **Task 2.2: Add Video & Audio Playback Routing in [`DownloadsScreen`](lib/screens/downloads_screen.dart)**
  - Path: `lib/screens/downloads_screen.dart`
  - Requirements:
    - Check item type / extension on tap.
    - If video: navigate to [`VideoPlayerScreen`](lib/screens/video_player_screen.dart) with `localFilePath`.
    - If music: navigate to [`MusicPlayerScreen`](lib/screens/music_player_screen.dart) with `localFilePath`.
    - If audiobook: navigate to [`AudiobookPlayerScreen`](lib/screens/audiobook_player_screen.dart) with `localFilePath`.

- [x] **Task 2.3: Clean Up Stream Controllers on Error in [`DownloadManager`](lib/services/download_manager.dart)**
  - Path: `lib/services/download_manager.dart`
  - Requirements:
    - Invoke `_scheduleStreamCleanup(task.itemId)` in `catch (DioException)` and `catch (e)` blocks.
    - Ensure cancelled/failed tasks do not leak memory in `_streamControllers`.

- [x] **Task 2.4: Implement Playback Reporting in Media Players**
  - Paths: `lib/screens/video_player_screen.dart`, `lib/screens/audiobook_player_screen.dart`
  - Requirements:
    - Listen to `player.stream.position` and periodically report progress via `JellyfinService.reportProgress`.
    - Report `reportPlaybackStart` on open and `reportPlaybackStopped` on dispose.

---

## Phase 3: Architecture, Concurrency & Performance (P1/P2)

Resolve architecture layer skips, DNS polling overhead, and lifecycle safety.

- [x] **Task 3.1: Hoist Connection Checking out of [`MainScreen.build`](lib/screens/main_screen.dart)**
  - Path: `lib/screens/main_screen.dart`
  - Requirements:
    - Remove `FutureBuilder` with `_checkConnection` from `build()`.
    - Check connectivity in `initState()` and on network state changes with debounce.
    - Ensure offline mode banner is displayed consistently on both mobile and tablet (`NavigationRail`) layouts.

- [x] **Task 3.2: Route Favorite & Played Toggles through [`BookRepository`](lib/repositories/book_repository.dart)**
  - Paths: `lib/repositories/book_repository.dart`, `lib/screens/item_details_screen.dart`
  - Requirements:
    - Add `toggleFavorite(...)` and `togglePlayed(...)` methods to `BookRepository`.
    - Update the local SQLite record in `DatabaseService` to ensure immediate UI consistency across tabs.
    - Remove direct `JellyfinService` calls from `ItemDetailsScreen`.

- [x] **Task 3.3: Fix Pagination Deadlock in [`BookRepository.getItems`](lib/repositories/book_repository.dart)**
  - Paths: `lib/repositories/book_repository.dart`, `lib/screens/library_items_screen.dart`
  - Requirements:
    - Avoid returning `TotalRecordCount: cached.length` when returning cached first page items.
    - Persist the real `TotalRecordCount` in cache metadata or allow subsequent pages to query without being blocked by `_hasMore = false`.

- [x] **Task 3.4: Cancel Stream Subscriptions in Media Players**
  - Paths: `lib/screens/video_player_screen.dart`, `lib/screens/audiobook_player_screen.dart`
  - Requirements:
    - Assign `StreamSubscription` instances for `player.stream.*`.
    - Cancel all active subscriptions in `dispose()`.

- [x] **Task 3.5: Guard `setState()` with `mounted` Checks**
  - Paths: `lib/screens/item_details_screen.dart`, `lib/screens/epub_reader_screen.dart`
  - Requirements:
    - Add `if (mounted)` checks around all post-await `setState()` calls.

---

## Phase 4: Policy, Security & Test Coverage (P2/P3)

Align with Play Store policies, secure multi-device sessions, and establish test coverage.

- [x] **Task 4.1: Clean Up Dangerous Permissions in [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml)**
  - Path: `android/app/src/main/AndroidManifest.xml`
  - Requirements:
    - Remove `MANAGE_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE`.
    - Keep `INTERNET` and `READ_EXTERNAL_STORAGE` (if needed for local file import).

- [x] **Task 4.2: Ensure Deterministic Item Ordering in [`DatabaseService`](lib/services/database_service.dart)**
  - Path: `lib/services/database_service.dart`
  - Requirements:
    - Add `orderBy: 'updatedAt DESC'` to `getItemById(id)`.

- [x] **Task 4.3: Implement Dynamic Device ID**
  - Paths: `lib/providers/auth_provider.dart`, `lib/services/jellyfin_service.dart`
  - Requirements:
    - Generate a unique persistent UUID stored in `FlutterSecureStorage`.
    - Use this ID in `X-Emby-Authorization` `DeviceId` instead of the hardcoded `"finbuk-android-device"`.

- [x] **Task 4.4: Add Unit Tests for Repositories and Services**
  - Paths: `test/repositories/book_repository_test.dart`, `test/services/jellyfin_service_test.dart`, `test/services/download_manager_test.dart`
  - Requirements:
    - Mock Dio and DatabaseService to test caching patterns, error handling, and download queuing.
