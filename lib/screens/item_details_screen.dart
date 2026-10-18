import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/item.dart';
import '../providers/auth_provider.dart';
import '../repositories/book_repository.dart';
import '../services/download_manager.dart';
import '../services/file_service.dart';
import 'comic_reader_screen.dart';
import 'epub_reader_screen.dart';
import 'video_player_screen.dart';
import 'music_player_screen.dart';
import 'audiobook_player_screen.dart';

class ItemDetailsScreen extends StatefulWidget {
  final String itemId;
  final Map<String, dynamic>? initialItem;

  const ItemDetailsScreen({super.key, required this.itemId, this.initialItem});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  bool? _isFavorite;
  bool? _isPlayed;
  File? _localFile;

  // Download state from DownloadManager
  StreamSubscription<DownloadTask>? _downloadSubscription;
  DownloadTask? _currentDownloadTask;

  // State for item data
  Map<String, dynamic>? _displayItem;
  bool _isLoading = false;
  bool _isFetchingDetails = false;
  List<Map<String, dynamic>> _albumTracks = [];
  bool _isLoadingTracks = false;

  final FileService _fileService = FileService();
  final DownloadManager _downloadManager = DownloadManager();
  final BookRepository _repository = BookRepository();

  @override
  void initState() {
    super.initState();
    _isLoading = true;

    // Subscribe to download manager updates for this item
    _downloadSubscription = _downloadManager
        .getDownloadStream(widget.itemId)
        .listen(_onDownloadTaskUpdated);

    if (widget.initialItem != null) {
      _displayItem = widget.initialItem;
      _updateItemData(widget.initialItem!);
      _fetchFullDetails();
    } else {
      _fetchFullDetails();
    }
  }

  Future<void> _fetchFullDetails() async {
    if (_isFetchingDetails) return;
    setState(() {
      _isLoading = true;
      _isFetchingDetails = true;
    });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final server = auth.serverUrl;
      final userId = auth.userId;
      final token = auth.token;
      if (server == null || userId == null || token == null) {
        throw Exception('Authentication credentials not available');
      }
      final item = await _repository.getItemDetails(
        server,
        userId,
        token,
        widget.itemId,
        forceRefresh: true,
      );
      if (mounted) {
        setState(() {
          _displayItem = item;
          _isLoading = false;
          _isFetchingDetails = false;
        });
        _updateItemData(item);
      }
    } catch (e) {
      if (mounted) {
        // Try to load cached details as fallback
        try {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          final server = auth.serverUrl;
          final userId = auth.userId;
          final token = auth.token;
          if (server != null && userId != null && token != null) {
            final cachedItem = await _repository.getItemDetails(
              server,
              userId,
              token,
              widget.itemId,
              forceRefresh: false, // Don't force refresh, try to get from cache
            );

            if (mounted) {
              setState(() {
                _displayItem = cachedItem;
                _isLoading = false;
                _isFetchingDetails = false;
              });
              _updateItemData(cachedItem);
            }
          } else {
            throw Exception(
              'Authentication credentials not available for cache fetch',
            );
          }
        } catch (innerError) {
          // If cache also fails, show error state
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isFetchingDetails = false;
            });
          }
        }
      }
    }
  }

  void _updateItemData(Map<String, dynamic> item) async {
    final userData = item['UserData'];
    if (userData is Map<String, dynamic>) {
      _isFavorite = userData['IsFavorite'] as bool? ?? false;
      _isPlayed = userData['Played'] as bool? ?? false;
    } else {
      _isFavorite = false;
      _isPlayed = false;
    }

    try {
      final file = await _tryFindLocalFile(widget.itemId, item);
      if (mounted) {
        setState(() {
          _localFile = file;
        });
      }
    } catch (e) {
      _localFile = null;
    }

    final itemType = (item['Type'] ?? '').toString();
    if (itemType == 'MusicAlbum' && _albumTracks.isEmpty && !_isLoadingTracks) {
      _fetchAlbumTracks();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _fetchAlbumTracks() async {
    if (_isLoadingTracks) return;
    setState(() {
      _isLoadingTracks = true;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final server = auth.serverUrl;
      final userId = auth.userId;
      final token = auth.token;
      if (server == null || userId == null || token == null) {
        if (mounted) setState(() => _isLoadingTracks = false);
        return;
      }

      final result = await _repository.getItems(
        server,
        userId,
        token,
        parentId: widget.itemId,
        includeItemTypes: 'Audio',
      );

      final items = result['Items'] as List<Item>? ?? <Item>[];
      final rawTracks = items.map((item) => item.rawJson).toList();

      rawTracks.sort((a, b) {
        final discA = (a['ParentIndexNumber'] as num?)?.toInt() ?? 1;
        final discB = (b['ParentIndexNumber'] as num?)?.toInt() ?? 1;
        if (discA != discB) {
          return discA.compareTo(discB);
        }
        final trackA = (a['IndexNumber'] as num?)?.toInt() ?? 0;
        final trackB = (b['IndexNumber'] as num?)?.toInt() ?? 0;
        return trackA.compareTo(trackB);
      });

      if (mounted) {
        setState(() {
          _albumTracks = rawTracks;
          _isLoadingTracks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTracks = false;
        });
      }
    }
  }

  String _formatDurationFromTicks(num? ticks) {
    if (ticks == null || ticks <= 0) return '--:--';
    final d = Duration(microseconds: (ticks / 10).round());
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _fileServiceGetExtensionSafe(Map<String, dynamic> item) {
    try {
      return _fileService.getExtension(item);
    } catch (_) {
      return '';
    }
  }

  Future<File?> _tryFindLocalFile(
    String itemId,
    Map<String, dynamic> item,
  ) async {
    final ext = _fileServiceGetExtensionSafe(item);
    if (ext.isNotEmpty) {
      return await _fileService.getBookFile(itemId, ext);
    }
    return null;
  }

  void _onDownloadTaskUpdated(DownloadTask task) {
    if (!mounted) return;

    setState(() {
      _currentDownloadTask = task;
      if (task.status == DownloadStatus.completed && task.file != null) {
        _localFile = task.file;
      }
    });

    // Show notifications based on status
    final messenger = ScaffoldMessenger.of(context);
    switch (task.status) {
      case DownloadStatus.completed:
        messenger.showSnackBar(
          SnackBar(content: Text('Download complete: ${task.itemName}')),
        );
        break;
      case DownloadStatus.failed:
        messenger.showSnackBar(
          SnackBar(
            content: Text('Download failed: ${task.error ?? "Unknown error"}'),
          ),
        );
        break;
      case DownloadStatus.cancelled:
        messenger.showSnackBar(
          const SnackBar(content: Text('Download cancelled')),
        );
        break;
      default:
        break;
    }
  }

  Widget _buildDownloadButton(
    BuildContext context,
    AuthProvider auth,
    Map<String, dynamic> item,
  ) {
    final task = _currentDownloadTask;

    if (task != null) {
      switch (task.status) {
        case DownloadStatus.downloading:
          return GestureDetector(
            onTap: () => _downloadManager.cancelDownload(widget.itemId),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: task.progress,
                    strokeWidth: 3,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  '${(task.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        case DownloadStatus.paused:
          return GestureDetector(
            onTap: () => _downloadManager.cancelDownload(widget.itemId),
            child: const Icon(Icons.hourglass_top, color: Colors.orange),
          );
        case DownloadStatus.failed:
          return GestureDetector(
            onTap: () {
              // Retry: clear the task and start again
              _downloadManager.cancelDownload(
                widget.itemId,
              ); // remove failed task
              _manualDownload(context, auth, item);
            },
            child: const Icon(Icons.refresh, color: Colors.red),
          );
        case DownloadStatus.completed:
          return _ActionButton(
            icon: Icons.delete,
            color: Colors.red,
            tooltip: 'Delete download',
            onPressed: () => _deleteDownloaded(context, auth, item),
          );
        case DownloadStatus.cancelled:
        case DownloadStatus.notStarted:
          break;
      }
    }

    // No active task or inactive task
    if (_localFile != null) {
      return _ActionButton(
        icon: Icons.delete,
        color: Colors.red,
        tooltip: 'Delete download',
        onPressed: () => _deleteDownloaded(context, auth, item),
      );
    }

    return _ActionButton(
      icon: Icons.download_outlined,
      tooltip: 'Download',
      onPressed: () => _manualDownload(context, auth, item),
    );
  }

  Future<void> _manualDownload(
    BuildContext context,
    AuthProvider auth,
    Map<String, dynamic> item,
  ) async {
    final ext = _fileServiceGetExtensionSafe(item);
    if (ext.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot download: unsupported file type'),
          ),
        );
      }
      return;
    }

    final serverUrl = auth.serverUrl;
    final token = auth.token;
    if (serverUrl == null || token == null) return;

    await _downloadManager.startDownload(
      itemId: widget.itemId,
      itemName: item['Name'] as String? ?? 'Unknown',
      url: serverUrl,
      token: token,
      extension: ext,
    );
    // UI updates handled by listener
  }

  Future<void> _toggleFavorite(BuildContext context, AuthProvider auth) async {
    final messenger = ScaffoldMessenger.of(context);
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;
    if (serverUrl == null || userId == null || token == null) return;

    final newState = !(_isFavorite ?? false);
    setState(() => _isFavorite = newState);
    try {
      await _repository.toggleFavorite(
        serverUrl,
        userId,
        widget.itemId,
        token,
        newState,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isFavorite = !newState);
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to update favorite status')),
        );
      }
    }
  }

  Future<void> _togglePlayed(BuildContext context, AuthProvider auth) async {
    final messenger = ScaffoldMessenger.of(context);
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;
    if (serverUrl == null || userId == null || token == null) return;

    final newState = !(_isPlayed ?? false);
    setState(() => _isPlayed = newState);
    try {
      await _repository.togglePlayed(
        serverUrl,
        userId,
        widget.itemId,
        token,
        newState,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isPlayed = !newState);
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to update read status')),
        );
      }
    }
  }

  Future<void> _navigateToReader(
    BuildContext context,
    AuthProvider auth,
    Map<String, dynamic> item,
    int pageCount,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Check if local file already exists
    if (_localFile == null) {
      final file = await _tryFindLocalFile(widget.itemId, item);
      if (file != null && mounted) {
        setState(() {
          _localFile = file;
        });
      }
    }

    if (_localFile != null) {
      _openReader(navigator, item, pageCount);
      return;
    }

    // No file - check if there is an active download
    final existingTask = _downloadManager.getTask(widget.itemId);
    if (existingTask != null && existingTask.isActive) {
      // Already downloading, wait for it to complete
      final completed = await _waitForDownloadCompletion(widget.itemId);
      if (!completed) {
        return;
      }
      if (_localFile != null) {
        _openReader(navigator, item, pageCount);
      }
      return;
    }

    // No active download, start one
    final ext = _fileServiceGetExtensionSafe(item);
    if (ext == '.pdf') {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('PDF reading is not supported')),
        );
      }
      return;
    }
    if (ext.isEmpty) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Cannot download: unsupported file type'),
          ),
        );
      }
      return;
    }

    await _downloadManager.startDownload(
      itemId: widget.itemId,
      itemName: item['Name'] as String? ?? 'Unknown',
      url: auth.serverUrl ?? '',
      token: auth.token ?? '',
      extension: ext,
    );

    // Wait for completion
    final success = await _waitForDownloadCompletion(widget.itemId);
    if (!success) {
      return;
    }

    if (_localFile != null) {
      _openReader(navigator, item, pageCount);
    }
  }

  void _openReader(
    NavigatorState navigator,
    Map<String, dynamic> item,
    int pageCount,
  ) {
    final ext = _fileServiceGetExtensionSafe(item).toLowerCase();
    if (ext == '.pdf') {
      if (navigator.context.mounted) {
        ScaffoldMessenger.of(navigator.context).showSnackBar(
          const SnackBar(content: Text('PDF reading is not supported')),
        );
      }
      return;
    }
    final type = item['Type'] as String? ?? '';
    final isVideo =
        type == 'Movie' ||
        type == 'Episode' ||
        type == 'Video' ||
        const ['.mp4', '.mkv', '.webm', '.avi', '.mov', '.m4v'].contains(ext);
    final isAudiobook = type == 'AudioBook' || ext == '.m4b';
    final isMusic =
        type == 'Audio' ||
        (!isAudiobook &&
            const [
              '.mp3',
              '.flac',
              '.m4a',
              '.aac',
              '.ogg',
              '.opus',
              '.wav',
            ].contains(ext));

    if (isVideo) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) =>
              VideoPlayerScreen(item: item, localFilePath: _localFile?.path),
        ),
      );
    } else if (isMusic) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) =>
              MusicPlayerScreen(item: item, localFilePath: _localFile?.path),
        ),
      );
    } else if (isAudiobook) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => AudiobookPlayerScreen(
            item: item,
            localFilePath: _localFile?.path,
          ),
        ),
      );
    } else if (ext == '.cbz' || ext == '.cbr') {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => ComicReaderScreen(
            itemId: item['Id'] as String? ?? '',
            title: item['Name'] as String? ?? 'Comic Reader',
            filePath: _localFile?.path,
          ),
        ),
      );
    } else if (ext == '.epub') {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => EpubReaderScreen(
            itemId: item['Id'] as String? ?? '',
            title: item['Name'] as String? ?? 'EPUB Reader',
            filePath: _localFile?.path,
          ),
        ),
      );
    } else {
      if (navigator.context.mounted) {
        ScaffoldMessenger.of(navigator.context).showSnackBar(
          const SnackBar(content: Text('Unsupported format for playback')),
        );
      }
      return;
    }
  }

  Future<bool> _waitForDownloadCompletion(String itemId) async {
    await for (final task in _downloadManager.getDownloadStream(itemId)) {
      if (mounted) {
        setState(() {
          _currentDownloadTask = task;
          if (task.status == DownloadStatus.completed && task.file != null) {
            _localFile = task.file;
          }
        });
      }

      if (task.status == DownloadStatus.completed) {
        return true;
      } else if (task.status == DownloadStatus.failed ||
          task.status == DownloadStatus.cancelled) {
        return false;
      }
    }
    return false;
  }

  Future<void> _deleteDownloaded(
    BuildContext context,
    AuthProvider auth,
    Map<String, dynamic> item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    // Cancel any active download for this item
    final task = _downloadManager.getTask(widget.itemId);
    if (task != null && task.isActive) {
      await _downloadManager.cancelDownload(widget.itemId);
      // Listener will update _currentDownloadTask to cancelled
    }

    try {
      await _fileService.deleteDownloadedItem(
        widget.itemId,
        _fileServiceGetExtensionSafe(item),
      );
      if (mounted) {
        setState(() {
          _localFile = null;
        });
        messenger.showSnackBar(
          SnackBar(content: Text('Deleted: ${item['Name']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final serverUrl = auth.serverUrl;
    final token = auth.token;

    if (_isLoading && _displayItem == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_displayItem == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Failed to load item details')),
      );
    }

    final item = _displayItem!;
    final pageCount = item['PageCount'] as int? ?? 0;
    final container = (item['Container'] ?? '').toString().toLowerCase().trim();
    final path = (item['Path'] ?? '').toString().toLowerCase().trim();
    final isComic =
        container == 'cbz' ||
        container == 'cbr' ||
        path.endsWith('.cbz') ||
        path.endsWith('.cbr');
    final isEpub = container == 'epub' || path.endsWith('.epub');
    final itemType = (item['Type'] ?? '').toString();
    final mediaType = (item['MediaType'] ?? '').toString();
    final isVideo = itemType == 'Movie' || itemType == 'Episode';
    final isAudio = mediaType == 'Audio';
    final isAudiobook = itemType == 'AudioBook';
    final isMusicAlbum = itemType == 'MusicAlbum';
    final isMusicTrack = isAudio && !isAudiobook;
    final isMusic = isMusicTrack || isMusicAlbum;
    final showActionButtons =
        isComic ||
        isEpub ||
        isVideo ||
        isAudiobook ||
        isMusicTrack ||
        isMusicAlbum;
    final playbackPositionTicks =
        (item['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks']
            as num? ??
        0;
    final hasPlaybackPosition = playbackPositionTicks > 0;

    final imageUrl = serverUrl != null
        ? '$serverUrl/Items/${item['Id']}/Images/Primary'
        : '';
    final backdropUrl =
        item['BackdropImageTags'] != null &&
            (item['BackdropImageTags'] as List).isNotEmpty &&
            serverUrl != null
        ? '$serverUrl/Items/${item['Id']}/Images/Backdrop'
        : null;

    final artistName =
        (item['Artists'] as List?)?.join(', ') ??
        (item['AlbumArtist'] as String?);
    final year = item['ProductionYear'];
    final subtitleParts = <String>[
      if (artistName != null && artistName.isNotEmpty) artistName,
      if (year != null) '$year',
    ];

    final overview = item['Overview'] as String?;
    final hasOverview = overview != null && overview.trim().isNotEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.black26,
                child: const BackButton(color: Colors.white),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildBetterHeader(
                backdropUrl ?? imageUrl,
                imageUrl,
                token ?? '',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['Name'] as String? ?? 'Unknown Title',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitleParts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitleParts.join(' • '),
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 24),

                  if (showActionButtons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: (isMusicAlbum && _albumTracks.isEmpty)
                                  ? null
                                  : () {
                                      if (isVideo) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (context) =>
                                                VideoPlayerScreen(
                                                  item: item,
                                                  localFilePath:
                                                      _localFile?.path,
                                                ),
                                          ),
                                        );
                                      } else if (isMusicAlbum) {
                                        if (_albumTracks.isNotEmpty) {
                                          final firstTrack =
                                              Map<String, dynamic>.from(
                                                _albumTracks.first,
                                              );
                                          if (firstTrack['AlbumId'] == null) {
                                            firstTrack['AlbumId'] =
                                                widget.itemId;
                                          }
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (context) =>
                                                  MusicPlayerScreen(
                                                    item: firstTrack,
                                                  ),
                                            ),
                                          );
                                        }
                                      } else if (isMusicTrack) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (context) =>
                                                MusicPlayerScreen(
                                                  item: item,
                                                  localFilePath:
                                                      _localFile?.path,
                                                ),
                                          ),
                                        );
                                      } else if (isAudiobook) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (context) =>
                                                AudiobookPlayerScreen(
                                                  item: item,
                                                  localFilePath:
                                                      _localFile?.path,
                                                ),
                                          ),
                                        );
                                      } else {
                                        _navigateToReader(
                                          context,
                                          auth,
                                          item,
                                          pageCount,
                                        );
                                      }
                                    },
                              icon: Icon(
                                isVideo || isMusic
                                    ? Icons.play_arrow
                                    : isAudiobook
                                    ? Icons.headphones
                                    : Icons.menu_book,
                              ),
                              label: Text(
                                isVideo
                                    ? hasPlaybackPosition
                                          ? 'Continue Watching'
                                          : 'Watch Now'
                                    : isMusicAlbum
                                    ? 'Play Album'
                                    : isMusicTrack
                                    ? 'Play Now'
                                    : isAudiobook
                                    ? hasPlaybackPosition
                                          ? 'Continue Listening'
                                          : 'Listen Now'
                                    : hasPlaybackPosition
                                    ? 'Continue Reading'
                                    : 'Read Now',
                              ),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: _isPlayed == true
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                            color: _isPlayed == true ? Colors.green : null,
                            tooltip: isVideo
                                ? 'Mark as Watched'
                                : isComic || isEpub
                                ? 'Mark as Read'
                                : 'Mark as Played',
                            onPressed: () => _togglePlayed(context, auth),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            icon: _isFavorite == true
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _isFavorite == true ? Colors.red : null,
                            tooltip: 'Favorite',
                            onPressed: () => _toggleFavorite(context, auth),
                          ),
                          if (!isMusicAlbum) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: _buildDownloadButton(context, auth, item),
                            ),
                          ],
                        ],
                      ),
                    ),

                  if (isMusicAlbum) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tracks',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_albumTracks.isNotEmpty)
                          Text(
                            '${_albumTracks.length} ${_albumTracks.length == 1 ? "track" : "tracks"}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingTracks)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_albumTracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('No tracks found in this album.'),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _albumTracks.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final track = _albumTracks[index];
                          final trackNumber =
                              track['IndexNumber'] ?? (index + 1);
                          final trackTitle =
                              track['Name'] as String? ?? 'Track ${index + 1}';
                          final trackArtists =
                              (track['Artists'] as List?)?.join(', ') ??
                              (track['AlbumArtist'] as String?) ??
                              '';
                          final trackDuration = _formatDurationFromTicks(
                            track['RunTimeTicks'] as num?,
                          );

                          void playThisTrack() {
                            final trackItem = Map<String, dynamic>.from(track);
                            if (trackItem['AlbumId'] == null) {
                              trackItem['AlbumId'] = widget.itemId;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    MusicPlayerScreen(item: trackItem),
                              ),
                            );
                          }

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: SizedBox(
                              width: 32,
                              child: Center(
                                child: Text(
                                  '$trackNumber',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                            title: Text(
                              trackTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: trackArtists.isNotEmpty
                                ? Text(
                                    trackArtists,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: Colors.grey),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  trackDuration,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.play_circle_outline),
                                  iconSize: 28,
                                  onPressed: playThisTrack,
                                ),
                              ],
                            ),
                            onTap: playThisTrack,
                          );
                        },
                      ),
                    const SizedBox(height: 24),
                  ],

                  if (hasOverview || !isMusicAlbum) ...[
                    Text(
                      'Summary',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasOverview ? overview : 'No summary available.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (item['Genres'] != null)
                    Wrap(
                      spacing: 8,
                      children: (item['Genres'] as List)
                          .map(
                            (genre) => Chip(
                              label: Text(genre.toString()),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetterHeader(
    String backgroundUrl,
    String coverUrl,
    String token,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: backgroundUrl,
          fit: BoxFit.cover,
          httpHeaders: {'X-Emby-Token': token},
          placeholder: (context, url) => Container(color: Colors.black),
          errorWidget: (context, url, error) => Container(color: Colors.black),
        ),
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withAlpha(77)),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.contain,
              httpHeaders: {'X-Emby-Token': token},
              placeholder: (context, url) =>
                  const Icon(Icons.book, size: 100, color: Colors.white70),
              errorWidget: (context, url, error) =>
                  const Icon(Icons.book, size: 100, color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    super.dispose();
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
