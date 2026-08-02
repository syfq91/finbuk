import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../repositories/book_repository.dart';
import '../models/item.dart';
import 'library_items_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;

    if (serverUrl == null || userId == null || token == null) {
      return const Center(child: Text('Not authenticated'));
    }

    final repository = BookRepository();

    return FutureBuilder<List<Item>>(
      future: repository.getUserViews(serverUrl, userId, token),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            (!snapshot.hasData || snapshot.data!.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Could not fetch libraries',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        final libraries = snapshot.data!;
        return ListView.separated(
          itemCount: libraries.length + 1,
          padding: const EdgeInsets.symmetric(vertical: 8),
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.transparent,
                  child: Icon(Icons.favorite, color: Colors.red),
                ),
                title: const Text(
                  'Favorites',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const LibraryItemsScreen(
                        libraryName: 'Favorites',
                        isFavoriteOnly: true,
                      ),
                    ),
                  );
                },
              );
            }

            final library = libraries[index - 1];
            final collectionType = library.collectionType ?? '';
            IconData libraryIcon;
            Color iconColor;
            switch (collectionType) {
              case 'books':
                libraryIcon = Icons.library_books;
                iconColor = Colors.deepPurple;
              case 'movies':
                libraryIcon = Icons.movie;
                iconColor = Colors.blue;
              case 'tvshows':
                libraryIcon = Icons.tv;
                iconColor = Colors.teal;
              case 'music':
                libraryIcon = Icons.library_music;
                iconColor = Colors.pink;
              case 'homevideos':
                libraryIcon = Icons.video_library;
                iconColor = Colors.orange;
              default:
                libraryIcon = Icons.folder;
                iconColor = Colors.grey;
            }
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.transparent,
                child: Icon(libraryIcon, color: iconColor),
              ),
              title: Text(
                library.name ?? 'Unknown Library',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => LibraryItemsScreen(
                      libraryId: library.id,
                      libraryName: library.name ?? 'Library',
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
