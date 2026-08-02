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

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final serverUrl = auth.serverUrl;
    final token = auth.token;

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

  @override
  Widget build(BuildContext context) {
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
      body: Center(child: Video(controller: controller)),
    );
  }
}
