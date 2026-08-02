import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';

class MusicPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String? localFilePath;

  const MusicPlayerScreen({
    super.key,
    required this.item,
    this.localFilePath,
  });

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  late final Player player = Player();
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

    player.stream.position.listen((p) {
      if (mounted) setState(() => position = p);
    });
    player.stream.duration.listen((d) {
      if (mounted) setState(() => duration = d);
    });
    player.stream.playing.listen((p) {
      if (mounted) setState(() => isPlaying = p);
    });

    Playable playable;
    if (widget.localFilePath != null) {
      playable = Media(widget.localFilePath!);
    } else {
      final streamUrl = '$serverUrl/Items/${widget.item['Id']}/Download';
      playable = Media(
        streamUrl,
        httpHeaders: token != null ? {'X-Emby-Token': token} : const {},
      );
    }

    await player.open(playable);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return '${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final imageUrl = '${auth.serverUrl}/Items/${widget.item['Id']}/Images/Primary';
    final token = auth.token;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  httpHeaders: token != null ? {'X-Emby-Token': token} : const {},
                  errorWidget: (context, url, error) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.music_note, size: 100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              widget.item['Name']?.toString() ?? 'Unknown Title',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.item['Artists'] != null && (widget.item['Artists'] as List).isNotEmpty
                  ? (widget.item['Artists'] as List).first.toString()
                  : 'Unknown Artist',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            Slider(
              value: position.inMilliseconds.toDouble().clamp(
                    0.0,
                    duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                  ),
              min: 0.0,
              max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
              onChanged: (v) {
                player.seek(Duration(milliseconds: v.round()));
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position), style: const TextStyle(fontSize: 12)),
                Text(_formatDuration(duration), style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => player.previous(),
                ),
                IconButton(
                  iconSize: 80,
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  onPressed: () => player.playOrPause(),
                ),
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => player.next(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
