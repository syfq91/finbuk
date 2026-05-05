import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' hide Locator;
import 'package:flureadium/flureadium.dart';
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
  final Flureadium _flureadium = Flureadium();
  Publication? _publication;
  Locator? _initialLocator;
  bool _isLoading = true;
  String? _error;

  // Status bar state
  double _currentProgress = 0.0;
  int _currentPosition = 0;
  int _totalPages = 0;
  String _currentTime = '';
  Timer? _clockTimer;

  // UI state
  bool _isAppBarVisible = true;
  final JellyfinService _jellyfinService = JellyfinService();
  int? _totalTicks;
  String? _serverUrl;
  String? _token;
  String? _userId;

  // Stream subscriptions
  StreamSubscription<Locator>? _locatorSubscription;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _serverUrl = auth.serverUrl;
    _token = auth.token;
    _userId = auth.userId;

    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
    _openPublication();
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

  Future<void> _openPublication() async {
    if (widget.filePath == null) {
      setState(() {
        _error = 'No file path provided';
        _isLoading = false;
      });
      return;
    }

    try {
      // Convert filesystem path to file:// URI for Flureadium
      String pubUrl = widget.filePath!;
      if (!pubUrl.startsWith('file://')) {
        pubUrl = 'file://$pubUrl';
      }

      final pub = await _flureadium.openPublication(pubUrl);

      // Determine total pages from reading order
      final pageCount = pub.readingOrder.length;

      // Try to restore saved position
      Locator? savedLocator;
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedJson = prefs.getString(
          'comic_locator_${widget.itemId}',
        );
        if (savedJson != null) {
          savedLocator = Locator.fromJsonString(savedJson);
        }
      } catch (e) {
        debugPrint('Failed to load saved locator: $e');
      }

      if (mounted) {
        setState(() {
          _publication = pub;
          _initialLocator = savedLocator;
          _totalPages = pageCount;
          _isLoading = false;
          // Restore position from saved locator
          if (savedLocator != null) {
            _currentProgress =
                savedLocator.locations?.totalProgression ?? 0.0;
            _currentPosition = savedLocator.locations?.position ?? 0;
          }
        });
      }
    } on ReadiumException catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to open comic: ${e.message}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load comic: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onReaderReady() {
    // Subscribe to locator changes after the reader is ready
    _locatorSubscription?.cancel();
    _locatorSubscription = _flureadium.onTextLocatorChanged.listen(
      (locator) {
        if (!mounted) return;

        final progress = locator.locations?.totalProgression ?? 0.0;
        final position = locator.locations?.position ?? 0;

        setState(() {
          _currentProgress = progress;
          _currentPosition = position;
          if (_isAppBarVisible) {
            _isAppBarVisible = false;
          }
        });

        _saveProgress(locator);
      },
    );
  }

  Future<void> _saveProgress(Locator locator) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'comic_locator_${widget.itemId}',
        locator.json,
      );

      // Report to Jellyfin
      if (_serverUrl != null && _token != null && _userId != null) {
        final progress = locator.locations?.totalProgression ?? 0.0;
        int ticks;
        if (_totalTicks != null) {
          ticks = (progress * _totalTicks!).toInt();
        } else {
          // Fallback: use position as ticks
          ticks = locator.locations?.position ?? 0;
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

  @override
  void dispose() {
    _clockTimer?.cancel();
    _locatorSubscription?.cancel();

    // Report stop to Jellyfin
    if (_serverUrl != null && _token != null && _userId != null) {
      int ticks;
      if (_totalTicks != null) {
        ticks = (_currentProgress * _totalTicks!).toInt();
      } else {
        ticks = _currentPosition;
      }
      _jellyfinService.reportPlaybackStopped(
        _serverUrl!,
        _userId!,
        _token!,
        widget.itemId,
        ticks,
      );
    }

    // Close the publication
    _flureadium.closePublication();

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
                _openPublication();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_publication == null) {
      return const Center(child: Text('No pages to display'));
    }

    // Compute displayed page number from progress
    final displayPage = _totalPages > 0
        ? (_currentProgress * _totalPages).ceil().clamp(1, _totalPages)
        : _currentPosition + 1;

    return Column(
      children: [
        Expanded(
          child: ReadiumReaderWidget(
            publication: _publication!,
            initialLocator: _initialLocator,
            loadingWidget: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Loading ${widget.title}...'),
                ],
              ),
            ),
            onTap: () {
              setState(() {
                _isAppBarVisible = !_isAppBarVisible;
              });
            },
            onLocatorChanged: (locator) {
              if (!mounted) return;

              final progress = locator.locations?.totalProgression ?? 0.0;
              final position = locator.locations?.position ?? 0;

              setState(() {
                _currentProgress = progress;
                _currentPosition = position;
              });

              _saveProgress(locator);
            },
            onReady: _onReaderReady,
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
                _totalPages > 0
                    ? '$displayPage / $_totalPages'
                    : 'Page ${_currentPosition + 1}',
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
}
