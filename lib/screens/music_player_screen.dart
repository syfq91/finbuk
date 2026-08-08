import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/music_player_provider.dart';

class MusicPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String? localFilePath;

  const MusicPlayerScreen({super.key, required this.item, this.localFilePath});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPlayer();
    });
  }

  void _initPlayer() {
    if (_initialized) return;
    _initialized = true;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final musicPlayer = Provider.of<MusicPlayerProvider>(
      context,
      listen: false,
    );

    if (auth.serverUrl == null || auth.token == null) {
      return;
    }

    musicPlayer.play(
      item: widget.item,
      serverUrl: auth.serverUrl!,
      token: auth.token!,
      localFilePath: widget.localFilePath,
    );
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
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Consumer<MusicPlayerProvider>(
      builder: (context, musicPlayer, _) {
        final item = musicPlayer.currentItem ?? widget.item;
        final imageUrl = auth.serverUrl != null
            ? '${auth.serverUrl}/Items/${item['Id']}/Images/Primary'
            : '';
        final token = auth.token;

        final runTimeTicks = item['RunTimeTicks'] as num?;
        final fallbackDuration = runTimeTicks != null && runTimeTicks > 0
            ? Duration(microseconds: (runTimeTicks / 10).round())
            : Duration.zero;
        final totalDuration = musicPlayer.duration > Duration.zero
            ? musicPlayer.duration
            : fallbackDuration;
        final remainingDuration = totalDuration > musicPlayer.position
            ? totalDuration - musicPlayer.position
            : Duration.zero;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Now Playing'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: 'Minimize',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 16.0,
            ),
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
                      httpHeaders: token != null
                          ? {'X-Emby-Token': token}
                          : const {},
                      errorWidget: (context, url, error) => Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.music_note, size: 100),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Text(
                  item['Name']?.toString() ?? 'Unknown Title',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  item['Artists'] != null &&
                          (item['Artists'] as List).isNotEmpty
                      ? (item['Artists'] as List).first.toString()
                      : 'Unknown Artist',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 32),
                Slider(
                  value: musicPlayer.position.inMilliseconds.toDouble().clamp(
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
                    musicPlayer.seek(Duration(milliseconds: v.round()));
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(musicPlayer.position),
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '-${_formatDuration(remainingDuration)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 48,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: musicPlayer.player.previous,
                    ),
                    IconButton(
                      iconSize: 80,
                      color: Theme.of(context).colorScheme.primary,
                      icon: Icon(
                        musicPlayer.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                      ),
                      onPressed: musicPlayer.togglePlayPause,
                    ),
                    IconButton(
                      iconSize: 48,
                      icon: const Icon(Icons.skip_next),
                      onPressed: musicPlayer.player.next,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
