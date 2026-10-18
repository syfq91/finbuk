import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';

class AudiobookPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String? localFilePath;

  const AudiobookPlayerScreen({
    super.key,
    required this.item,
    this.localFilePath,
  });

  @override
  State<AudiobookPlayerScreen> createState() => _AudiobookPlayerScreenState();
}

class _AudiobookPlayerScreenState extends State<AudiobookPlayerScreen> {
  late final Player player = Player();
  final JellyfinService _jellyfinService = JellyfinService();

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<double>? _rateSubscription;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  double playbackRate = 1.0;
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
    _rateSubscription = player.stream.rate.listen((r) {
      if (mounted) setState(() => playbackRate = r);
    });

    if (fallbackDuration > Duration.zero && mounted) {
      setState(() => duration = fallbackDuration);
    }

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
      final streamUrl = '$_serverUrl/Items/$_itemId/Download';
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
    _rateSubscription?.cancel();
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

  void _skip(Duration offset) {
    final newPosition = position + offset;
    if (newPosition < Duration.zero) {
      player.seek(Duration.zero);
    } else if (newPosition > duration) {
      player.seek(duration);
    } else {
      player.seek(newPosition);
    }
  }

  void _changeSpeed() {
    final speeds = [1.0, 1.25, 1.5, 1.75, 2.0, 0.75];
    int currentIndex = speeds.indexOf(playbackRate);
    if (currentIndex == -1) currentIndex = 0;
    final nextSpeed = speeds[(currentIndex + 1) % speeds.length];
    player.setRate(nextSpeed);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final imageUrl =
        '${auth.serverUrl}/Items/${widget.item['Id']}/Images/Primary';
    final token = auth.token;

    final runTimeTicks = widget.item['RunTimeTicks'] as num?;
    final fallbackDuration = runTimeTicks != null && runTimeTicks > 0
        ? Duration(microseconds: (runTimeTicks / 10).round())
        : Duration.zero;
    final totalDuration =
        duration > Duration.zero ? duration : fallbackDuration;
    final remainingDuration = totalDuration > position
        ? totalDuration - position
        : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audiobook Player'),
        actions: [
          TextButton(
            onPressed: _changeSpeed,
            child: Text(
              '${playbackRate}x',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    httpHeaders: token != null
                        ? {'X-Emby-Token': token}
                        : const {},
                    errorWidget: (context, url, error) => Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.book, size: 100),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              widget.item['Name']?.toString() ?? 'Unknown Title',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.item['Authors'] != null &&
                      (widget.item['Authors'] as List).isNotEmpty
                  ? (widget.item['Authors'] as List).first.toString()
                  : 'Unknown Author',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Slider(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
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
                  iconSize: 40,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _skip(const Duration(seconds: -10)),
                ),
                IconButton(
                  iconSize: 80,
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: () => player.playOrPause(),
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.forward_30),
                  onPressed: () => _skip(const Duration(seconds: 30)),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
