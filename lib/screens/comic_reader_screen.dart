import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:manga_page_view/manga_page_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';

class ComicReaderScreen extends StatefulWidget {
  final String itemId;
  final String title;
  final String? filePath;

  const ComicReaderScreen({
    super.key,
    required this.itemId,
    required this.title,
    this.filePath,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  List<String> _imagePaths = [];
  bool _isLoading = true;
  String? _error;

  // Reading settings
  MangaPageViewMode _mode = MangaPageViewMode.paged;
  MangaPageViewDirection _direction = MangaPageViewDirection.left;

  // Status bar state
  int _currentPage = 0;
  String _currentTime = '';
  Timer? _clockTimer;

  // UI state
  bool _isAppBarVisible = true;
  late final MangaPageViewController _mangaController;
  final JellyfinService _jellyfinService = JellyfinService();
  int? _totalTicks;
  String? _serverUrl;
  String? _token;
  String? _userId;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _serverUrl = auth.serverUrl;
    _token = auth.token;
    _userId = auth.userId;

    _mangaController = MangaPageViewController();
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
    _extractImages();
    _initJellyfinProgress();

    // Set immersive mode to hide status bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initJellyfinProgress() async {
    if (_serverUrl != null && _token != null && _userId != null) {
      await _jellyfinService.reportPlaybackStart(
        _serverUrl!,
        _userId!,
        _token!,
        widget.itemId,
      );

      // Fetch item details to get RunTimeTicks for accurate progress
      try {
        final details = await _jellyfinService.getItemDetails(
          _serverUrl!,
          _userId!,
          _token!,
          widget.itemId,
        );
        if (details['RunTimeTicks'] != null) {
          setState(() {
            _totalTicks = details['RunTimeTicks'];
          });
        }
      } catch (e) {
        debugPrint('Failed to fetch item details for ticks: $e');
      }
    }
  }

  void _updateClock() {
    final now = DateTime.now();
    final timeString =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (mounted) {
      setState(() {
        _currentTime = timeString;
      });
    }
  }

  Future<void> _extractImages() async {
    if (widget.filePath == null) {
      setState(() {
        _error = 'No file path provided';
        _isLoading = false;
      });
      return;
    }

    final file = File(widget.filePath!);
    if (!await file.exists()) {
      setState(() {
        _error = 'File not found: ${widget.filePath}';
        _isLoading = false;
      });
      return;
    }

    try {
      // Create a temporary directory for extracted images
      final tempDir = await Directory.systemTemp.createTemp(
        'comic_${widget.itemId}_',
      );

      final bytes = await file.readAsBytes();
      Archive archive;

      final ext = p.extension(widget.filePath!).toLowerCase();
      if (ext == '.cbz' || ext == '.zip') {
        final decoder = ZipDecoder();
        archive = decoder.decodeBytes(bytes);
      } else if (ext == '.cbr' || ext == '.rar') {
        throw Exception(
          'CBR/RAR format is not supported. Please convert to CBZ (ZIP) format.',
        );
      } else {
        throw Exception('Unsupported archive format: $ext');
      }

      final List<String> extractedPaths = [];

      for (final fileInArchive in archive.files) {
        if (fileInArchive.isFile) {
          final fileName = fileInArchive.name;
          // Check if file is an image (common extensions)
          final lowerName = fileName.toLowerCase();
          if (lowerName.endsWith('.jpg') ||
              lowerName.endsWith('.jpeg') ||
              lowerName.endsWith('.png') ||
              lowerName.endsWith('.gif') ||
              lowerName.endsWith('.webp') ||
              lowerName.endsWith('.bmp') ||
              lowerName.endsWith('.tiff')) {
            // Extract file
            final outputPath = p.join(tempDir.path, p.basename(fileName));
            final outputFile = File(outputPath);
            await outputFile.writeAsBytes(fileInArchive.content as List<int>);
            extractedPaths.add(outputPath);
          }
        }
      }

      // Sort naturally by filename
      extractedPaths.sort(_naturalCompare);

      if (extractedPaths.isEmpty) {
        throw Exception('No images found in the archive');
      }

      setState(() {
        _imagePaths = extractedPaths;
        _isLoading = false;
      });

      // Load and restore reading progress
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getInt('comic_progress_${widget.itemId}');
        if (saved != null && saved < _imagePaths.length) {
          // Update current page state
          setState(() {
            _currentPage = saved;
          });
          // Jump to saved page after the frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _mangaController.moveToPage(saved);
            }
          });
        }
      } catch (e) {
        debugPrint('Failed to load progress: $e');
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load comic: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProgress(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('comic_progress_${widget.itemId}', page);

      // Report to Jellyfin
      if (_serverUrl != null && _token != null && _userId != null) {
        int ticks = page; // Default if we don't know scale
        if (_totalTicks != null && _imagePaths.length > 1) {
          // Calculate ticks based on page percentage
          ticks = ((page / (_imagePaths.length - 1)) * _totalTicks!).toInt();
        }

        await _jellyfinService.reportProgress(
          _serverUrl!,
          _userId!,
          _token!,
          widget.itemId,
          ticks,
          false,
        );
      }
    } catch (e) {
      debugPrint('Failed to save progress: $e');
    }
  }

  int _naturalCompare(String a, String b) {
    final nameA = p.basenameWithoutExtension(a);
    final nameB = p.basenameWithoutExtension(b);

    // Split into alternating sequences of digits and non-digits
    final regex = RegExp(r'(\d+|\D+)');
    final partsA = regex.allMatches(nameA).map((m) => m.group(1)!).toList();
    final partsB = regex.allMatches(nameB).map((m) => m.group(1)!).toList();

    for (int i = 0; i < partsA.length || i < partsB.length; i++) {
      if (i >= partsA.length) return -1;
      if (i >= partsB.length) return 1;

      final partA = partsA[i];
      final partB = partsB[i];

      // Check if both are numeric
      final int? numA = int.tryParse(partA);
      final int? numB = int.tryParse(partB);

      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
      } else {
        // Compare non-numeric parts case-insensitively
        final cmp = partA.toLowerCase().compareTo(partB.toLowerCase());
        if (cmp != 0) return cmp;
      }
    }
    return 0;
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _mangaController.dispose();

    // Report stop to Jellyfin
    if (_serverUrl != null && _token != null && _userId != null) {
      int ticks = _currentPage;
      if (_totalTicks != null && _imagePaths.length > 1) {
        ticks = ((_currentPage / (_imagePaths.length - 1)) * _totalTicks!)
            .toInt();
      }
      _jellyfinService.reportPlaybackStopped(
        _serverUrl!,
        _userId!,
        _token!,
        widget.itemId,
        ticks,
      );
    }

    // Optionally clean up the temporary directory
    // if (_tempDirPath != null) {
    //   try { Directory(_tempDirPath!).delete(recursive: true); } catch (_) {}
    // }

    // Restore system UI mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBody(),
          if (_isAppBarVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: AppBar(
                  title: Text(widget.title),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: _showSettingsDialog,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading ${widget.title}...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _extractImages();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_imagePaths.isEmpty) {
      return const Center(child: Text('No pages to display'));
    }

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _handleTapUp,
            child: MangaPageView(
              key: ValueKey('${_direction.name}-${_mode.name}'),
              controller: _mangaController,
              mode: _mode,
              direction: _direction,
              pageCount: _imagePaths.length,
              onPageChange: (index) {
                if (mounted && index != _currentPage) {
                  setState(() {
                    _currentPage = index;
                    if (_isAppBarVisible) {
                      _isAppBarVisible = false;
                    }
                  });
                  _saveProgress(index);
                }
              },
              pageBuilder: (context, index) {
                final file = File(_imagePaths[index]);
                return Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.black,
                      child: Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.grey[400],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        Container(
          height: 40,
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Clock on the left
              Text(
                _currentTime,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
              // Page indicator on the right
              Text(
                '${_currentPage + 1} / ${_imagePaths.length}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reader Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reading direction
              const Text(
                'Reading Direction',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<MangaPageViewDirection>(
                  value: _direction,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: MangaPageViewDirection.right,
                      child: Text('Left to Right (Comics)'),
                    ),
                    DropdownMenuItem(
                      value: MangaPageViewDirection.left,
                      child: Text('Right to Left (Manga)'),
                    ),
                    DropdownMenuItem(
                      value: MangaPageViewDirection.down,
                      child: Text('Top to Bottom'),
                    ),
                    DropdownMenuItem(
                      value: MangaPageViewDirection.up,
                      child: Text('Bottom to Top'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      this.setState(() {
                        _direction = value;
                      });
                    }
                  },
                ),
              ),
              const Divider(height: 24),
              // View mode
              const Text(
                'View Mode',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<MangaPageViewMode>(
                  value: _mode,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: MangaPageViewMode.paged,
                      child: Text('Paged (One page at a time)'),
                    ),
                    DropdownMenuItem(
                      value: MangaPageViewMode.continuous,
                      child: Text('Continuous (Long strip)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      this.setState(() {
                        _mode = value;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTapUp(TapUpDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.localPosition.dx;
    final threshold = screenWidth / 3;

    if (dx >= threshold && dx <= threshold * 2) {
      // Middle tap: toggle AppBar visibility
      setState(() {
        _isAppBarVisible = !_isAppBarVisible;
      });
    }
    // Left and right taps do nothing (page navigation removed)
  }
}
