import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' hide Locator;
import 'package:flureadium/flureadium.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';
import '../widgets/epub/epub_toc_sheet.dart';
import '../widgets/epub/epub_settings_sheet.dart';

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

class EpubReaderScreen extends StatefulWidget {
  final String itemId;
  final String title;
  final String? filePath;

  const EpubReaderScreen({
    super.key,
    required this.itemId,
    required this.title,
    this.filePath,
  });

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final _flureadium = Flureadium();
  final _jellyfinService = JellyfinService();

  Publication? _publication;
  Locator? _initialLocator;
  bool _isLoading = true;
  String? _error;

  // UI overlay visibility
  bool _showAppBar = false;

  // Progress tracking
  double _currentProgress = 0.0;

  // EPUB preferences
  EPUBPreferences _prefs = EPUBPreferences(
    fontFamily: 'Georgia',
    fontSize: 100,
    fontWeight: 400.0,
    verticalScroll: false,
    backgroundColor: const Color(0xFFFFFFFF),
    textColor: const Color(0xFF000000),
  );
  bool _readerReady = false;
  EPUBPreferences? _pendingPrefs;

  // Jellyfin state
  String? _serverUrl;
  String? _token;
  String? _userId;
  int? _totalTicks;

  // Stream subscriptions — set up in onReady per the docs
  StreamSubscription<Locator>? _locatorSub;
  StreamSubscription<ReadiumError>? _errorSub;

  static const _prefsKey = 'epub_global_prefs';

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

    _loadPrefs().then((_) => _openPublication());
  }

  @override
  void dispose() {
    _locatorSub?.cancel();
    _errorSub?.cancel();

    // Report playback stopped to Jellyfin
    if (_serverUrl != null && _token != null && _userId != null) {
      final ticks = _totalTicks != null
          ? (_currentProgress * _totalTicks!).toInt()
          : 0;
      _jellyfinService.reportPlaybackStopped(
        _serverUrl!,
        _userId!,
        _token!,
        widget.itemId,
        ticks,
      );
    }

    _flureadium.closePublication();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Preferences persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefsKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          _prefs = EPUBPreferences(
            fontFamily: map['fontFamily'] as String? ?? 'Georgia',
            fontSize: (map['fontSize'] as num?)?.toInt() ?? 100,
            fontWeight: (map['fontWeight'] as num?)?.toDouble() ?? 400.0,
            verticalScroll: map['verticalScroll'] as bool? ?? false,
            backgroundColor: Color(
              map['backgroundColor'] as int? ?? 0xFFFFFFFF,
            ),
            textColor: Color(map['textColor'] as int? ?? 0xFF000000),
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _savePrefs(EPUBPreferences p) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _prefsKey,
        jsonEncode({
          'fontFamily': p.fontFamily,
          'fontSize': p.fontSize,
          'fontWeight': p.fontWeight,
          'verticalScroll': p.verticalScroll,
          'backgroundColor': p.backgroundColor?.toARGB32(),
          'textColor': p.textColor?.toARGB32(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _applyPrefs(EPUBPreferences p) async {
    setState(() => _prefs = p);
    _pendingPrefs = p;
    if (_readerReady) {
      await _flureadium.setEPUBPreferences(p);
      _pendingPrefs = null;
    }
    await _savePrefs(p);
  }

  // ---------------------------------------------------------------------------
  // Publication lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _openPublication() async {
    if (widget.filePath == null) {
      setState(() {
        _error = 'No file path provided';
        _isLoading = false;
      });
      return;
    }

    try {
      // Load saved locator before opening the publication
      Locator? savedLocator;
      try {
        final sp = await SharedPreferences.getInstance();
        final raw = sp.getString('epub_locator_${widget.itemId}');
        if (raw != null) savedLocator = Locator.fromJsonString(raw);
      } catch (_) {}

      // Set default preferences before opening
      _flureadium.setDefaultPreferences(_prefs);

      // Open the publication — pass the raw filesystem path
      final pub = await _flureadium.openPublication(widget.filePath!);

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
          if (savedLocator != null) {
            _currentProgress = savedLocator.locations?.totalProgression ?? 0.0;
          }
          _isLoading = false;
        });
      }
    } on ReadiumException catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to open EPUB: ${e.message}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load EPUB: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // onReady — subscribe to EventChannels here per flureadium docs
  // ---------------------------------------------------------------------------

  void _onReaderReady() {
    _readerReady = true;
    _locatorSub?.cancel();
    _errorSub?.cancel();

    if (_pendingPrefs != null) {
      _flureadium.setEPUBPreferences(_pendingPrefs!);
      _pendingPrefs = null;
    }

    _locatorSub = _flureadium.onTextLocatorChanged.listen((locator) {
      if (!mounted) return;

      setState(() {
        _currentProgress = locator.locations?.totalProgression ?? 0.0;
      });

      _saveProgress(locator);
    });

    _errorSub = _flureadium.onErrorEvent.listen((error) {
      debugPrint('EPUB Reader Error: $error');
    });
  }

  Future<void> _goPreviousPage() async {
    try {
      await _flureadium.goLeft();
    } catch (e) {
      debugPrint('Failed to navigate to previous EPUB page: $e');
    }
  }

  Future<void> _goNextPage() async {
    try {
      await _flureadium.goRight();
    } catch (e) {
      debugPrint('Failed to navigate to next EPUB page: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Progress persistence & Jellyfin reporting
  // ---------------------------------------------------------------------------

  Future<void> _saveProgress(Locator locator) async {
    _currentProgress = locator.locations?.totalProgression ?? _currentProgress;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('epub_locator_${widget.itemId}', locator.json);

      if (_serverUrl != null && _token != null && _userId != null) {
        final prog = locator.locations?.totalProgression ?? 0.0;
        final ticks = _totalTicks != null ? (prog * _totalTicks!).toInt() : 0;
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
  // TOC sheet
  // ---------------------------------------------------------------------------

  void _showToc() {
    if (_publication == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EpubTocSheet(
        toc: _publication!.tableOfContents,
        onTap: (link) {
          Navigator.pop(context);
          _flureadium.goByLink(link, _publication!);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Settings sheet
  // ---------------------------------------------------------------------------

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EpubSettingsSheet(prefs: _prefs, onChanged: _applyPrefs),
    );
  }

  // ---------------------------------------------------------------------------
  // External links
  // ---------------------------------------------------------------------------

  Future<void> _onExternalLink(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open External Link?'),
        content: Text(url, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
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
                'Loading ${widget.title}…',
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
                const Icon(
                  Icons.menu_book_rounded,
                  size: 64,
                  color: Colors.red,
                ),
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
          child: Text('No content', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    // Main reader layout — follows the same design as ComicReaderScreen
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Reader widget — placed directly, no wrapping GestureDetectors
          ReadiumReaderWidget(
            publication: _publication!,
            initialLocator: _initialLocator,
            onReady: _onReaderReady,
            onLocatorChanged: (locator) {
              if (mounted) {
                setState(() {
                  _currentProgress = locator.locations?.totalProgression ?? 0.0;
                });
              }
              _saveProgress(locator);
            },
            onExternalLinkActivated: _onExternalLink,
          ),

          // Tap zones for overlay toggle and page navigation
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

          // Top AppBar — toggled by tapping
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
                        icon: const Icon(Icons.list_rounded),
                        tooltip: 'Table of Contents',
                        onPressed: _showToc,
                      ),
                      IconButton(
                        icon: const Icon(Icons.text_fields_rounded),
                        tooltip: 'Reading Settings',
                        onPressed: _showSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom bar — always visible, minimalist design
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
                        '${(_currentProgress * 100).toStringAsFixed(0)}%',
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
// Clock Widget
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
