import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/homepage_provider.dart';
import '../repositories/book_repository.dart';
import '../models/item.dart';
import 'library_items_screen.dart';
import 'item_details_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final homepageProvider = Provider.of<HomepageProvider>(context);
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

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildErrorState(context, auth);
        }

        final libraries = snapshot.data!;
        final availableIds = ['resume', ...libraries.map((l) => l.id)];

        WidgetsBinding.instance.addPostFrameCallback((_) {
          homepageProvider.syncAvailableSections(availableIds);
        });

        // Determine ordered & visible section IDs
        final orderedIds =
            (homepageProvider.sectionOrder.isNotEmpty
                    ? homepageProvider.sectionOrder
                    : availableIds)
                .where((id) {
                  return availableIds.contains(id) &&
                      homepageProvider.isSectionVisible(id);
                })
                .toList();

        if (orderedIds.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.visibility_off_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No homepage sections visible',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('Customize visible libraries in Settings.'),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: orderedIds.map<Widget>((sectionId) {
            if (sectionId == 'resume') {
              return _ResumeSection(auth: auth, repository: repository);
            } else {
              final matching = libraries
                  .where((l) => l.id == sectionId)
                  .toList();
              if (matching.isEmpty) return const SizedBox.shrink();
              return _LibrarySection(
                library: matching.first,
                auth: auth,
                repository: repository,
              );
            }
          }).toList(),
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, AuthProvider auth) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.library_books, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Welcome, ${auth.username ?? 'User'}!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text('No libraries found on this server.'),
        ],
      ),
    );
  }
}

class _ResumeSection extends StatelessWidget {
  final AuthProvider auth;
  final BookRepository repository;

  const _ResumeSection({required this.auth, required this.repository});

  @override
  Widget build(BuildContext context) {
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;

    if (serverUrl == null || userId == null || token == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<Item>>(
      future: repository.getResumeItems(serverUrl, userId, token),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            (!snapshot.hasData || snapshot.data!.isEmpty)) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final items = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Continue',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 220,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemCount: math.min(items.length, 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final imageUrl = '$serverUrl/Items/${item.id}/Images/Primary';
                  final playedPercentage = item.userData?['PlayedPercentage'];

                  return Container(
                    width: 140,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => ItemDetailsScreen(
                              itemId: item.id,
                              initialItem: item.rawJson,
                            ),
                          ),
                        );
                      },
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const SizedBox.shrink(),
                                errorWidget: (context, url, error) =>
                                    const Center(
                                      child: Icon(Icons.broken_image),
                                    ),
                                httpHeaders: {'X-Emby-Token': token},
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name ?? 'Unknown',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (playedPercentage is num)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: LinearProgressIndicator(
                                        value: playedPercentage / 100.0,
                                        minHeight: 2,
                                        backgroundColor: Colors.grey.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _LibrarySection extends StatelessWidget {
  final Item library;
  final AuthProvider auth;
  final BookRepository repository;

  const _LibrarySection({
    required this.library,
    required this.auth,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;

    if (serverUrl == null || userId == null || token == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<Item>>(
      future: repository.getLatestMedia(
        serverUrl,
        userId,
        token,
        parentId: library.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            (!snapshot.hasData || snapshot.data!.isEmpty)) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final items = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Newly Added in ${library.name}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 280,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemCount: math.min(items.length, 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final imageUrl = '$serverUrl/Items/${item.id}/Images/Primary';

                  return Container(
                    width: 160,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => ItemDetailsScreen(
                              itemId: item.id,
                              initialItem: item.rawJson,
                            ),
                          ),
                        );
                      },
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const SizedBox.shrink(),
                                errorWidget: (context, url, error) =>
                                    const Center(
                                      child: Icon(Icons.broken_image),
                                    ),
                                httpHeaders: {'X-Emby-Token': token},
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                item.name ?? 'Unknown',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
