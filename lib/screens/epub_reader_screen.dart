import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flureadium/flureadium.dart' as fr;
import 'package:provider/provider.dart';
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
  final flureadium = fr.Flureadium();
  fr.Publication? _publication;
  final JellyfinService _jellyfinService = JellyfinService();
  int? _totalTicks;
  String? _serverUrl;
  String? _token;
  String? _userId;
  double _currentProgress = 0.0;
  bool _isAppBarVisible = false;
  bool _isLoading = true;
  bool _isSettingsLoaded = false;
  double _fontSize = 16.0;
  String _fontFamily = 'sans-serif';
  String? _initialLocator;
  String _currentTime = '';
  Timer? _clockTimer;
  List<fr.Link> _chapters = [];

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _serverUrl = auth.serverUrl;
    _token = auth.token;
    _userId = auth.userId;

    // Set edge to edge mode so status bar is visible
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _initJellyfinProgress();
    _loadSettings();
    _openPublication();

    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
  }

  Future<void> _openPublication() async {
    try {
      final publication = await flureadium.openPublication(widget.filePath);
      if (mounted) {
        setState(() {
          _publication = publication;
          _chapters = publication.tableOfContents;
          _isLoading = false;
        });

        if (_initialLocator != null) {
          final locator = fr.Locator.fromJson(jsonDecode(_initialLocator!));
          if (locator != null) {
            flureadium.goToLocator(locator);
          }
        }
      }
    } catch (e) {
      debugPrint('Error opening publication: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble('epub_font_size') ?? 16.0;
      _fontFamily = prefs.getString('epub_font_family') ?? 'sans-serif';
      _initialLocator = prefs.getString('epub_locator_${widget.itemId}');
      _isSettingsLoaded = true;
    });

    // Apply settings if reader is ready
    _applySettings();
  }

  void _applySettings() {
    // flureadium expects fontSize as a percentage (100 = 100%)
    // Mapping 16.0 (default slider) to 100%
    final fontSizePercent = (_fontSize * 6.25).toInt();
    
    flureadium.setEPUBPreferences(
      fr.EPUBPreferences(
        fontSize: fontSizePercent,
        fontFamily: _fontFamily,
        fontWeight: null,
        verticalScroll: false,
        backgroundColor: null,
        textColor: null,
      ),
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub_font_size', _fontSize);
    await prefs.setString('epub_font_family', _fontFamily);
  }

  Future<void> _saveLocator(fr.Locator locator) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'epub_locator_${widget.itemId}',
      jsonEncode(locator.toJson()),
    );
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

    flureadium.closePublication();

    // Restore system UI mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleAppBar() {
    setState(() {
      _isAppBarVisible = !_isAppBarVisible;
    });
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
                            final List<fr.Link> flatChapters = [];

                            // flureadium Link objects usually have nested 'children'
                            void flattenRecursive(List<fr.Link> links, int level) {
                              for (var link in links) {
                                final prefix = List.filled(level, '  ').join();
                                final title = link.title != null && link.title!.isNotEmpty
                                    ? link.title!
                                    : 'Chapter ${flatChapters.length + 1}';
                                
                                // Add to flat list with proper title indentation
                                flatChapters.add(fr.Link(
                                  href: link.href,
                                  title: prefix + title,
                                  children: [], // Flattened
                                ));

                                if (link.children.isNotEmpty) {
                                  flattenRecursive(link.children, level + 1);
                                }
                              }
                            }

                            flattenRecursive(_chapters, 0);

                            return ListView.builder(
                              itemCount: flatChapters.length,
                              itemBuilder: (context, index) {
                                final chapter = flatChapters[index];
                                return ListTile(
                                  title: Text(chapter.title ?? 'Chapter ${index + 1}'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (_isAppBarVisible) _toggleAppBar();

                                    if (_publication != null) {
                                      flureadium.goByLink(chapter, _publication!);
                                    }
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
                              _applySettings();
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
                        _applySettings();
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
                child: _publication == null
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        children: [
                          fr.ReadiumReaderWidget(
                            publication: _publication!,
                            initialLocator: _initialLocator != null 
                              ? fr.Locator.fromJson(jsonDecode(_initialLocator!)) 
                              : null,
                            onReady: () {
                              _applySettings();
                            },
                            onLocatorChanged: (locator) {
                              if (mounted) {
                                setState(() {
                                  _currentProgress = locator.locations?.totalProgression ?? 0.0;
                                });
                              }
                              _reportProgress(_currentProgress);
                              _saveLocator(locator);
                            },
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              onTapUp: (details) {
                                final width = MediaQuery.of(context).size.width;
                                final x = details.globalPosition.dx / width;
                                if (x < 0.33) {
                                  flureadium.goLeft();
                                  if (_isAppBarVisible) _toggleAppBar();
                                } else if (x > 0.66) {
                                  flureadium.goRight();
                                  if (_isAppBarVisible) _toggleAppBar();
                                } else {
                                  _toggleAppBar();
                                }
                              },
                              behavior: HitTestBehavior.translucent,
                            ),
                          ),
                        ],
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
                      '${(_currentProgress * 100).toStringAsFixed(1)}%',
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
