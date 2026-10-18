import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String? localFilePath;

  const VideoPlayerScreen({super.key, required this.item, this.localFilePath});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  final JellyfinService _jellyfinService = JellyfinService();

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  DateTime _lastProgressReport = DateTime.fromMillisecondsSinceEpoch(0);

  String? _serverUrl;
  String? _userId;
  String? _token;
  late final String _itemId;

  @override
  void initState() {
    super.initState();
    _itemId = widget.item['Id']?.toString() ?? '';
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _serverUrl = auth.serverUrl;
    _userId = auth.currentUser?.id;
    _token = auth.token;

    final runTimeTicks = widget.item['RunTimeTicks'] as num?;
    final fallbackDuration = runTimeTicks != null && runTimeTicks > 0
        ? Duration(microseconds: (runTimeTicks / 10).round())
        : Duration.zero;

    _positionSubscription = player.stream.position.listen((p) {
      if (mounted) setState(() => position = p);
      _onPositionChanged(p);
    });
    _durationSubscription = player.stream.duration.listen((d) {
      if (mounted && d > Duration.zero) setState(() => duration = d);
    });
    _playingSubscription = player.stream.playing.listen((p) {
      if (mounted) setState(() => isPlaying = p);
    });

    if (fallbackDuration > Duration.zero && mounted) {
      setState(() => duration = fallbackDuration);
    }

    // Resume position if available (Jellyfin ticks are 10,000,000 per second)
    final userData = widget.item['UserData'] as Map<String, dynamic>?;
    final playbackPositionTicks =
        userData?['PlaybackPositionTicks'] as num? ?? 0;
    final startPosition = Duration(
      microseconds: (playbackPositionTicks / 10).round(),
    );

    Playable playable;
    if (widget.localFilePath != null) {
      playable = Media(widget.localFilePath!);
    } else {
      // Use Jellyfin stream URL (can also use /Items/${widget.item['Id']}/Download)
      final streamUrl = '$_serverUrl/Videos/$_itemId/stream';
      playable = Media(
        streamUrl,
        httpHeaders: _token != null ? {'X-Emby-Token': _token!} : const {},
      );
    }

    await player.open(playable);
    if (startPosition.inSeconds > 0) {
      await player.seek(startPosition);
    }

    if (_serverUrl != null &&
        _userId != null &&
        _token != null &&
        _itemId.isNotEmpty) {
      unawaited(
        _jellyfinService.reportPlaybackStart(
          _serverUrl!,
          _userId!,
          _token!,
          _itemId,
        ),
      );
    }
  }

  void _onPositionChanged(Duration p) {
    final now = DateTime.now();
    if (now.difference(_lastProgressReport).inSeconds >= 10) {
      _lastProgressReport = now;
      if (_serverUrl != null &&
          _userId != null &&
          _token != null &&
          _itemId.isNotEmpty) {
        final positionTicks = p.inMicroseconds * 10;
        unawaited(
          _jellyfinService.reportProgress(
            _serverUrl!,
            _userId!,
            _token!,
            _itemId,
            positionTicks,
            !isPlaying,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_serverUrl != null &&
        _userId != null &&
        _token != null &&
        _itemId.isNotEmpty) {
      final positionTicks = position.inMicroseconds * 10;
      unawaited(
        _jellyfinService.reportPlaybackStopped(
          _serverUrl!,
          _userId!,
          _token!,
          _itemId,
          positionTicks,
        ),
      );
    }
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String minutes = twoDigits(d.inMinutes.remainder(60));
    String seconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final runTimeTicks = widget.item['RunTimeTicks'] as num?;
    final fallbackDuration = runTimeTicks != null && runTimeTicks > 0
        ? Duration(microseconds: (runTimeTicks / 10).round())
        : Duration.zero;
    final totalDuration =
        fallbackDuration > Duration.zero ? fallbackDuration : duration;
    final remainingDuration = totalDuration > position
        ? totalDuration - position
        : Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.item['Name']?.toString() ?? 'Video Player',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Center(child: Video(controller: controller)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        thumbColor: Colors.white,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white30,
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: position.inMilliseconds.toDouble().clamp(
                          0.0,
                          totalDuration.inMilliseconds.toDouble() > 0
                              ? totalDuration.inMilliseconds.toDouble()
                              : 1.0,
                        ),
                        min: 0.0,
                        max: totalDuration.inMilliseconds.toDouble() > 0
                            ? totalDuration.inMilliseconds.toDouble()
                            : 1.0,
                        onChanged: (v) {
                          player.seek(Duration(milliseconds: v.round()));
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '-${_formatDuration(remainingDuration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
