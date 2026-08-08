import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

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
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final serverUrl = auth.serverUrl;
    final token = auth.token;

    final runTimeTicks = widget.item['RunTimeTicks'] as num?;
    final fallbackDuration = runTimeTicks != null && runTimeTicks > 0
        ? Duration(microseconds: (runTimeTicks / 10).round())
        : Duration.zero;

    player.stream.position.listen((p) {
      if (mounted) setState(() => position = p);
    });
    player.stream.duration.listen((d) {
      if (mounted && d > Duration.zero) setState(() => duration = d);
    });
    player.stream.playing.listen((p) {
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
      final streamUrl = '$serverUrl/Videos/${widget.item['Id']}/stream';
      playable = Media(
        streamUrl,
        httpHeaders: token != null ? {'X-Emby-Token': token} : const {},
      );
    }

    await player.open(playable);
    if (startPosition.inSeconds > 0) {
      await player.seek(startPosition);
    }

    // TODO: Listen to player.stream.position and update progress to Jellyfin using JellyfinService
  }

  @override
  void dispose() {
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
