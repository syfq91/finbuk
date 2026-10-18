import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/item.dart';
import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';
import 'library_items_screen.dart';

/// Screen displaying sub-categories for Jellyfin Music libraries (Artists, Albums, Songs, Genres).
class MusicLibraryScreen extends StatelessWidget {
  final Item library;

  const MusicLibraryScreen({super.key, required this.library});

  void _navigateToCategory(
    BuildContext context, {
    required String title,
    String? includeItemTypes,
    String? genreId,
  }) {
    final libName = library.name ?? 'Music';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LibraryItemsScreen(
          libraryId: library.id,
          libraryName: '$libName - $title',
          includeItemTypes: includeItemTypes,
          genreIds: genreId,
        ),
      ),
    );
  }

  void _showGenresBottomSheet(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;

    if (serverUrl == null || userId == null || token == null) return;

    final jellyfinService = JellyfinService();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return FutureBuilder<List<dynamic>>(
            future: jellyfinService.getGenres(
              serverUrl,
              userId,
              token,
              parentId: library.id,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final genres = snapshot.data ?? [];
              if (genres.isEmpty) {
                return const Center(child: Text('No genres found.'));
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Select Genre',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: genres.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final genre = genres[index] as Map<String, dynamic>;
                        final genreName =
                            genre['Name']?.toString() ?? 'Unknown Genre';
                        final genreId = genre['Id']?.toString();

                        return ListTile(
                          leading: const Icon(Icons.music_note),
                          title: Text(genreName),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).pop();
                            _navigateToCategory(
                              context,
                              title: genreName,
                              includeItemTypes: 'Audio,MusicAlbum',
                              genreId: genreId,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = library.name ?? 'Music Library';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            title: const Text(
              'Artists',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Browse library by artist'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _navigateToCategory(
              context,
              title: 'Artists',
              includeItemTypes: 'MusicArtist',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.album,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            title: const Text(
              'Albums',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Browse albums'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _navigateToCategory(
              context,
              title: 'Albums',
              includeItemTypes: 'MusicAlbum',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.music_note,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            title: const Text(
              'Songs',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('All individual tracks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _navigateToCategory(
              context,
              title: 'Songs',
              includeItemTypes: 'Audio',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.category,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            title: const Text(
              'Genres',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Browse by musical genre'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showGenresBottomSheet(context),
          ),
        ],
      ),
    );
  }
}
