import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' hide Locator;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  final _readium = FlutterReadium();
  final _jellyfinService = JellyfinService();

  Publication? _publication;
  Locator? _initialLocator;
  bool _isLoading = true;
  String? _error;

  // Overlay — appbar toggles on tap; bottom bar is always visible
  bool _showAppBar = false;

  // Progress tracking
  double _currentProgress = 0.0;
  int _currentPosition = 0;
  int _totalPages = 0;

  // Jellyfin state
  String? _serverUrl;
  String? _token;
  String? _userId;
  int? _totalTicks;

  // Stream subscriptions
  StreamSubscription<Locator>? _locatorSub;
  StreamSubscription<ReadiumError>? _errorSub;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    final auth = Provider.of<AuthProvider>(context, listen: false);
    _serverUrl = auth.serverUrl;
    _token = auth.token;
    _userId = auth.userId;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _openPublication();
  }

  @override
  void dispose() {
    _locatorSub?.cancel();
    _errorSub?.cancel();

    // Report playback stopped to Jellyfin
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

    _readium.closePublication();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Publication lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _openPublication() async {
    if (widget.filePath == null) {
      if (mounted) {
        setState(() {
          _error = 'No file path provided';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // Load saved locator before opening the publication
      Locator? savedLocator;
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedJson = prefs.getString('comic_locator_${widget.itemId}');
        if (savedJson != null) {
          savedLocator = Locator.fromJsonString(savedJson);
        }
      } catch (e) {
        debugPrint('Failed to load saved locator: $e');
      }

      // Open the publication — pass the raw filesystem path
      final pub = await _readium.openPublication(widget.filePath!);

      debugPrint('Publication opened: ${pub.metadata.title}');
      debugPrint('Reading order: ${pub.readingOrder.length} items');

      _setupSubscriptions();

      // Report playback start to Jellyfin
      if (_serverUrl != null && _token != null && _userId != null) {
        await _jellyfinService.reportPlaybackStart(
          _serverUrl!,
          _userId!,
          _token!,
          widget.itemId,
        );
        try {
          final details = await _jellyfinService.getItemDetails(
            _serverUrl!,
            _userId!,
            _token!,
            widget.itemId,
          );
          if (details['RunTimeTicks'] != null) {
            _totalTicks = details['RunTimeTicks'] as int;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _publication = pub;
          _initialLocator = savedLocator;
          _totalPages = pub.readingOrder.length;
          _isLoading = false;
          if (savedLocator != null) {
            _currentProgress = savedLocator.locations?.totalProgression ?? 0.0;
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

  // ---------------------------------------------------------------------------
  // Stream subscriptions
  // ---------------------------------------------------------------------------

  void _setupSubscriptions() {
    _locatorSub?.cancel();
    _errorSub?.cancel();

    _locatorSub = _readium.onTextLocatorChanged.listen((locator) {
      if (!mounted) return;

      setState(() {
        _currentProgress = locator.locations?.totalProgression ?? 0.0;
        _currentPosition = locator.locations?.position ?? 0;
      });

      _saveProgress(locator);
    });

    _errorSub = _readium.onErrorEvent.listen((error) {
      debugPrint('Readium error: $error');
    });
  }

  Future<void> _goPreviousPage() async {
    try {
      await _readium.goBackward();
    } catch (e) {
      debugPrint('Failed to navigate to previous page: $e');
    }
  }

  Future<void> _goNextPage() async {
    try {
      await _readium.goForward();
    } catch (e) {
      debugPrint('Failed to navigate to next page: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Progress persistence & Jellyfin reporting
  // ---------------------------------------------------------------------------

  Future<void> _saveProgress(Locator locator) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('comic_locator_${widget.itemId}', locator.json);

      if (_serverUrl != null && _token != null && _userId != null) {
        final progress = locator.locations?.totalProgression ?? 0.0;
        int ticks = _totalTicks != null
            ? (progress * _totalTicks!).toInt()
            : (locator.locations?.position ?? 0);

        await _jellyfinService.reportProgress(
          _serverUrl!,
          _userId!,
          _token!,
          widget.itemId,
          ticks,
          false,
        );
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading ${widget.title}...',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
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
          ),
        ),
      );
    }

    if (_publication == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No pages to display',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    // Main reader layout — follows the official flutter_readium documentation
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Reader widget — placed directly, no wrapping GestureDetectors
          ReadiumReaderWidget(
            publication: _publication!,
            initialLocator: _initialLocator,
          ),

          // Tap zones for page navigation and overlay toggle
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _goPreviousPage,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _showAppBar = !_showAppBar),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _goNextPage,
                  ),
                ),
              ],
            ),
          ),

          // Top AppBar — toggled by tapping the reader
          if (_showAppBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    title: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Settings',
                        onPressed: () {
                          // TODO: implement settings
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom bar — always visible, shows clock (left) and page (right)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _ClockWidget(),
                      Text(
                        _totalPages > 0
                            ? '${_currentPosition + 1} / $_totalPages'
                            : '${_currentPosition + 1}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clock Widget — always-visible persistent clock
// ---------------------------------------------------------------------------

class _ClockWidget extends StatefulWidget {
  const _ClockWidget();

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  late Timer _timer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    final newTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (_currentTime != newTime) {
      setState(() {
        _currentTime = newTime;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _currentTime,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
