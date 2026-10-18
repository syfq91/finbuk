import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Provider for managing global music playback state using media_kit.
class MusicPlayerProvider extends ChangeNotifier {
  late final Player _player;
  Map<String, dynamic>? _currentItem;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isFullPlayerOpen = false;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;

  MusicPlayerProvider() {
    _player = Player();
    _initSubscriptions();
  }

  void _initSubscriptions() {
    _positionSubscription = _player.stream.position.listen((p) {
      _position = p;
      notifyListeners();
    });

    _durationSubscription = _player.stream.duration.listen((d) {
      if (d > Duration.zero) {
        _duration = d;
        notifyListeners();
      }
    });

    _playingSubscription = _player.stream.playing.listen((p) {
      _isPlaying = p;
      notifyListeners();
    });
  }

  Player get player => _player;
  Map<String, dynamic>? get currentItem => _currentItem;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isFullPlayerOpen => _isFullPlayerOpen;

  void setFullPlayerOpen(bool open) {
    if (_isFullPlayerOpen != open) {
      _isFullPlayerOpen = open;
      notifyListeners();
    }
  }

  static String _normalizeUrl(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Start playing an audio track, either from a local file or streaming from Jellyfin.
  Future<void> play({
    required Map<String, dynamic> item,
    required String serverUrl,
    required String token,
    String? localFilePath,
  }) async {
    _currentItem = item;

    // Use metadata RunTimeTicks as fallback duration
    final runTimeTicks = item['RunTimeTicks'] as num?;
    if (runTimeTicks != null && runTimeTicks > 0) {
      _duration = Duration(microseconds: (runTimeTicks / 10).round());
    } else {
      _duration = Duration.zero;
    }
    _position = Duration.zero;
    notifyListeners();

    final Playable playable;
    if (localFilePath != null && localFilePath.isNotEmpty) {
      playable = Media(localFilePath);
    } else {
      final baseUrl = _normalizeUrl(serverUrl);
      final itemId = item['Id'];
      final streamUrl = '$baseUrl/Audio/$itemId/stream';
      playable = Media(
        streamUrl,
        httpHeaders: {'X-Emby-Token': token},
      );
    }

    await _player.open(playable);

    // Resume position if available
    final userData = item['UserData'] as Map<String, dynamic>?;
    final playbackPositionTicks = userData?['PlaybackPositionTicks'] as num? ?? 0;
    if (playbackPositionTicks > 0) {
      final startPosition = Duration(
        microseconds: (playbackPositionTicks / 10).round(),
      );
      if (startPosition.inSeconds > 0) {
        await _player.seek(startPosition);
      }
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> togglePlayPause() async {
    await _player.playOrPause();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
