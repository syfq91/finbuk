import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/music_player_provider.dart';
import '../screens/music_player_screen.dart';

/// Floating mini player displayed at the bottom of the screen during audio playback.
class FloatingMiniPlayer extends StatelessWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const FloatingMiniPlayer({super.key, this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicPlayerProvider>(
      builder: (context, musicPlayer, _) {
        final currentItem = musicPlayer.currentItem;

        if (currentItem == null || musicPlayer.isFullPlayerOpen) {
          return const SizedBox.shrink();
        }

        final auth = Provider.of<AuthProvider>(context, listen: false);
        final itemId = currentItem['Id'];
        final serverUrl = auth.serverUrl;
        final token = auth.token;
        final imageUrl = (serverUrl != null && itemId != null)
            ? '$serverUrl/Items/$itemId/Images/Primary'
            : '';

        final title = currentItem['Name']?.toString() ?? 'Unknown Title';
        final artistsList = currentItem['Artists'] as List<dynamic>?;
        final artist = (artistsList != null && artistsList.isNotEmpty)
            ? artistsList.first.toString()
            : 'Unknown Artist';

        final colorScheme = Theme.of(context).colorScheme;

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              color: colorScheme.surfaceContainerHighest,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  final route = MaterialPageRoute<void>(
                    builder: (context) => MusicPlayerScreen(item: currentItem),
                  );
                  if (navigatorKey?.currentState != null) {
                    navigatorKey!.currentState!.push(route);
                  } else {
                    Navigator.of(context).push(route);
                  }
                },
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: imageUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  httpHeaders: token != null
                                      ? {'X-Emby-Token': token}
                                      : const {},
                                  errorWidget: (context, url, error) => Container(
                                    color: colorScheme.surfaceContainerHigh,
                                    child: const Icon(Icons.music_note, size: 24),
                                  ),
                                )
                              : Container(
                                  color: colorScheme.surfaceContainerHigh,
                                  child: const Icon(Icons.music_note, size: 24),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Title & Artist
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      // Play / Pause button
                      IconButton(
                        iconSize: 32,
                        icon: Icon(
                          musicPlayer.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: colorScheme.primary,
                        ),
                        onPressed: musicPlayer.togglePlayPause,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
