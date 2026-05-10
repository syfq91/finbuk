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

class _EpubReaderScreenState extends State<EpubReaderScreen>
    with SingleTickerProviderStateMixin {
  final Flureadium _flureadium = Flureadium();
  final JellyfinService _jellyfinService = JellyfinService();

  Publication? _publication;
  Locator? _initialLocator;
  EPUBPreferences _prefs = EPUBPreferences(
    fontFamily: 'Georgia',
    fontSize: 100,
    fontWeight: 400.0,
    verticalScroll: false,
    backgroundColor: const Color(0xFFFFFFFF),
    textColor: const Color(0xFF000000),
  );

  bool _isLoading = true;
  String? _error;

  // UI overlay visibility
  bool _showOverlay = true;
  late final AnimationController _overlayAnim;
  late final Animation<double> _overlayFade;

  // Progress (kept for tick calculation on dispose, but stream feeds UI)
  double _lastProgress = 0.0;

  // Jellyfin
  String? _serverUrl;
  String? _token;
  String? _userId;
  int? _totalTicks;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _overlayAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _overlayFade = CurvedAnimation(
      parent: _overlayAnim,
      curve: Curves.easeInOut,
    );

    final auth = Provider.of<AuthProvider>(context, listen: false);
    _serverUrl = auth.serverUrl;
    _token = auth.token;
    _userId = auth.userId;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _loadPrefs().then((_) => _openPublication());
  }

  @override
  void dispose() {
    _overlayAnim.dispose();

    if (_serverUrl != null && _token != null && _userId != null) {
      final ticks = _totalTicks != null
          ? (_lastProgress * _totalTicks!).toInt()
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
  // Helpers
  // ---------------------------------------------------------------------------

  static const _prefsKey = 'epub_global_prefs';

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
    await _flureadium.setEPUBPreferences(p);
    await _savePrefs(p);
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
      String url = widget.filePath!;
      if (!url.startsWith('file://')) url = 'file://$url';

      _flureadium.setDefaultPreferences(_prefs);
      final pub = await _flureadium.openPublication(url);

      Locator? saved;
      try {
        final sp = await SharedPreferences.getInstance();
        final raw = sp.getString('epub_locator_${widget.itemId}');
        if (raw != null) saved = Locator.fromJsonString(raw);
      } catch (_) {}

      // Jellyfin reporting
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
          _initialLocator = saved;
          if (saved != null) {
            _lastProgress = saved.locations?.totalProgression ?? 0.0;
          }
          _isLoading = false;
        });
      }
    } on ReadiumException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProgress(Locator locator) async {
    _lastProgress = locator.locations?.totalProgression ?? _lastProgress;
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

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
    if (_showOverlay) {
      _overlayAnim.forward();
    } else {
      _overlayAnim.reverse();
    }
  }

  // ---------------------------------------------------------------------------
  // TOC sheet
  // ---------------------------------------------------------------------------

  void _showToc() {
    if (_publication == null) return;
    showModalBottomSheet(
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
    showModalBottomSheet(
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildBody(),
          if (!_isLoading && _error == null && _publication != null)
            ..._buildOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
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
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_rounded, size: 64, color: Colors.red),
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
      );
    }

    if (_publication == null) {
      return const Center(
        child: Text('No content', style: TextStyle(color: Colors.white70)),
      );
    }

    return Stack(
      children: [
        // Core reader with Swipe Gestures
        GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! < 0) {
                _flureadium.goRight();
              } else if (details.primaryVelocity! > 0) {
                _flureadium.goLeft();
              }
            }
          },
          child: ReadiumReaderWidget(
            publication: _publication!,
            initialLocator: _initialLocator,
            onTap: _toggleOverlay,
            onLocatorChanged: _saveProgress,
            onExternalLinkActivated: _onExternalLink,
          ),
        ),

        // Left tap zone → previous page
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.25,
          child: GestureDetector(
            onTap: () => _flureadium.goLeft(),
            child: Container(color: Colors.transparent),
          ),
        ),

        // Right tap zone → next page
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * 0.25,
          child: GestureDetector(
            onTap: () => _flureadium.goRight(),
            child: Container(color: Colors.transparent),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildOverlay() {
    return [
      // Top bar
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: FadeTransition(
          opacity: _overlayFade,
          child: IgnorePointer(
            ignoring: !_showOverlay,
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
        ),
      ),

      // Bottom bar
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: FadeTransition(
          opacity: _overlayFade,
          child: IgnorePointer(
            ignoring: !_showOverlay,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Chapter + clock row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: StreamBuilder<Locator>(
                            stream: _flureadium.onTextLocatorChanged,
                            builder: (context, snapshot) {
                              final chapterTitle =
                                  snapshot.data?.title ?? widget.title;
                              return Text(
                                chapterTitle,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ),
                        const _ClockWidget(),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Progress bar + percentage
                    StreamBuilder<Locator>(
                      stream: _flureadium.onTextLocatorChanged,
                      builder: (context, snapshot) {
                        // Use initial locator progress if stream hasn't emitted yet
                        final currentProgress = snapshot.hasData
                            ? (snapshot.data!.locations?.totalProgression ??
                                  0.0)
                            : _lastProgress;

                        return Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: currentProgress,
                                  minHeight: 3,
                                  backgroundColor: Colors.white24,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${(currentProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),

                    // Navigation row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _navBtn(
                          Icons.skip_previous_rounded,
                          'Prev chapter',
                          () => _flureadium.skipToPrevious(),
                        ),
                        _navBtn(
                          Icons.chevron_left_rounded,
                          'Previous page',
                          () => _flureadium.goLeft(),
                        ),
                        _navBtn(
                          Icons.chevron_right_rounded,
                          'Next page',
                          () => _flureadium.goRight(),
                        ),
                        _navBtn(
                          Icons.skip_next_rounded,
                          'Next chapter',
                          () => _flureadium.skipToNext(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _navBtn(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: onPressed,
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
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }
}
