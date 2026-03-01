import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';

class EpubReaderScreen extends StatefulWidget {
  final String title;
  final String filePath;
  final String itemId;

  const EpubReaderScreen({
    super.key,
    required this.title,
    required this.filePath,
    required this.itemId,
  });

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  late final EpubController _controller;
  final JellyfinService _jellyfinService = JellyfinService();
  int? _totalTicks;
  String? _serverUrl;
  String? _token;
  String? _userId;
  double _currentProgress = 0.0;
  int? _chapterCurrentPage;
  int? _chapterTotalPages;
  bool _isAppBarVisible = false;
  bool _isLoading = true;
  bool _isSettingsLoaded = false;
  double _fontSize = 16.0;
  String _fontFamily = 'sans-serif';
  String? _initialCfi;
  String _currentTime = '';
  Timer? _clockTimer;
  List<EpubChapter> _chapters = [];

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _serverUrl = auth.serverUrl;
    _token = auth.token;
    _userId = auth.userId;

    _controller = EpubController();

    // Set immersive sticky mode for better reading experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initJellyfinProgress();
    _loadSettings();

    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble('epub_font_size') ?? 16.0;
      _fontFamily = prefs.getString('epub_font_family') ?? 'sans-serif';
      _initialCfi = prefs.getString('epub_cfi_${widget.itemId}');
      _isSettingsLoaded = true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub_font_size', _fontSize);
    await prefs.setString('epub_font_family', _fontFamily);
  }

  Future<void> _saveCfi(String cfi) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('epub_cfi_${widget.itemId}', cfi);
  }

  Future<void> _initJellyfinProgress() async {
    if (_serverUrl != null && _token != null && _userId != null) {
      await _jellyfinService.reportPlaybackStart(
        _serverUrl!,
        _userId!,
        _token!,
        widget.itemId,
      );

      // Fetch item details to get RunTimeTicks
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

  void _reportProgress(double progress) {
    _currentProgress = progress;
    if (_serverUrl != null && _token != null && _userId != null) {
      int ticks = 0;
      if (_totalTicks != null) {
        ticks = (progress * _totalTicks!).toInt();
      } else {
        // Fallback or use ticks as percentage if possible?
        // Best to at least send something.
        ticks = (progress * 1000000).toInt(); // Arbitrary scale
      }

      _jellyfinService.reportProgress(
        _serverUrl!,
        _userId!,
        _token!,
        widget.itemId,
        ticks,
        false,
      );
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();

    // Report stop to Jellyfin
    if (_serverUrl != null && _token != null && _userId != null) {
      int ticks = 0;
      if (_totalTicks != null) {
        ticks = (_currentProgress * _totalTicks!).toInt();
      } else {
        ticks = (_currentProgress * 1000000).toInt();
      }

      _jellyfinService.reportPlaybackStopped(
        _serverUrl!,
        _userId!,
        _token!,
        widget.itemId,
        ticks,
      );
    }

    // Restore system UI mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleAppBar() {
    setState(() {
      _isAppBarVisible = !_isAppBarVisible;
      if (_isAppBarVisible) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  void _handleTapUp(double x, double y) {
    if (x < 0.33) {
      // Left tap: previous page
      _controller.prev();
      if (_isAppBarVisible) _toggleAppBar();
    } else if (x > 0.66) {
      // Right tap: next page
      _controller.next();
      if (_isAppBarVisible) _toggleAppBar();
    } else {
      // Middle tap: toggle AppBar
      _toggleAppBar();
    }
  }

  void _showChaptersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (BuildContext context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Chapters',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _chapters.isEmpty
                      ? const Center(child: Text('No chapters available'))
                      : Builder(
                          builder: (context) {
                            final List<EpubChapter> flatChapters = [];
                            void flatten(
                              List<EpubChapter> chapters,
                              int level,
                            ) {
                              for (var c in chapters) {
                                final prefix = List.filled(level, '  ').join();
                                final title = c.title.isNotEmpty
                                    ? c.title
                                    : 'Chapter ${flatChapters.length + 1}';
                                flatChapters.add(
                                  EpubChapter(
                                    title: prefix + title,
                                    href: c.href,
                                    id: c.id,
                                    subitems: [],
                                  ),
                                );
                                if (c.subitems.isNotEmpty) {
                                  flatten(c.subitems, level + 1);
                                }
                              }
                            }

                            flatten(_chapters, 0);

                            return ListView.builder(
                              itemCount: flatChapters.length,
                              itemBuilder: (context, index) {
                                final chapter = flatChapters[index];
                                return ListTile(
                                  title: Text(chapter.title),
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (_isAppBarVisible) _toggleAppBar();

                                    // delay slightly to allow BottomSheet animation & UI resizing
                                    // (e.g. immersive mode changes) to settle without aborting rendering
                                    Future.delayed(
                                      const Duration(milliseconds: 300),
                                      () {
                                        if (!mounted) return;
                                        _controller.clearSelection();
                                        _controller.display(cfi: chapter.href);
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Font Size',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        const Text('A', style: TextStyle(fontSize: 14)),
                        Expanded(
                          child: Slider(
                            value: _fontSize,
                            min: 10.0,
                            max: 32.0,
                            divisions: 22,
                            onChanged: (value) {
                              setModalState(() {
                                _fontSize = value;
                              });
                              setState(() {});
                              _controller.setFontSize(fontSize: _fontSize);
                              _saveSettings();
                            },
                          ),
                        ),
                        const Text('A', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Font Style',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'serif', label: Text('Serif')),
                        ButtonSegment(value: 'sans-serif', label: Text('Sans')),
                        ButtonSegment(value: 'monospace', label: Text('Mono')),
                      ],
                      selected: {_fontFamily},
                      onSelectionChanged: (Set<String> newSelection) {
                        setModalState(() {
                          _fontFamily = newSelection.first;
                        });
                        setState(() {});
                        _controller.updateTheme(
                          theme: EpubTheme.custom(
                            customCss: {
                              '*': {
                                'font-family':
                                    '${_getFontFamilyCss()} !important',
                              },
                            },
                          ),
                        );
                        _saveSettings();
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getFontFamilyCss() {
    switch (_fontFamily) {
      case 'serif':
        return '"Noto Serif", serif';
      case 'monospace':
        return '"Noto Sans Mono", monospace';
      case 'sans-serif':
      default:
        return '"Noto Sans", sans-serif';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSettingsLoaded) {
      return Scaffold(
        body: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: EpubViewer(
                  epubSource: EpubSource.fromFile(File(widget.filePath)),
                  epubController: _controller,
                  initialCfi: _initialCfi,
                  displaySettings: EpubDisplaySettings(
                    fontSize: _fontSize.toInt(),
                    theme: EpubTheme.custom(
                      customCss: {
                        '*': {
                          'font-family': '${_getFontFamilyCss()} !important',
                        },
                      },
                    ),
                  ),
                  onRelocated: (location) async {
                    _reportProgress(location.progress);
                    _saveCfi(location.startCfi);

                    // Fetch chapter progress directly from epub.js
                    try {
                      final controller = _controller.webViewController;
                      if (controller != null) {
                        final result = await controller.evaluateJavascript(
                          source:
                              'rendition.currentLocation() ? rendition.currentLocation().start.displayed : null',
                        );
                        if (mounted && result != null && result is Map) {
                          final page = result['page'] as int?;
                          final total = result['total'] as int?;
                          if (page != null && total != null) {
                            setState(() {
                              _chapterCurrentPage = page;
                              _chapterTotalPages = total;
                            });
                          }
                        }
                      }
                    } catch (e) {
                      debugPrint('Error fetching chapter progress: $e');
                    }
                  },
                  onChaptersLoaded: (chapters) {
                    if (mounted) {
                      setState(() {
                        _chapters = chapters;
                      });
                    }
                  },
                  onEpubLoaded: () {
                    setState(() {
                      _isLoading = false;
                    });
                  },
                  onTouchUp: _handleTapUp,
                ),
              ),
              Container(
                height: 40,
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _currentTime,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                    Text(
                      _chapterCurrentPage != null && _chapterTotalPages != null
                          ? '$_chapterCurrentPage / $_chapterTotalPages'
                          : '${(_currentProgress * 100).toStringAsFixed(1)}%',
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
          ),
          if (_isLoading)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('Loading ${widget.title}...'),
                  ],
                ),
              ),
            ),
          if (_isAppBarVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppBar(
                title: Text(widget.title),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.9),
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.format_list_bulleted),
                    onPressed: _showChaptersBottomSheet,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: _showSettingsBottomSheet,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
