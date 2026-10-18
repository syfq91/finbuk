import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/homepage_provider.dart';
import '../repositories/book_repository.dart';
import '../models/item.dart';

/// Screen allowing users to reorder and toggle visibility of homepage sections.
class HomepageSettingsScreen extends StatefulWidget {
  const HomepageSettingsScreen({super.key});

  @override
  State<HomepageSettingsScreen> createState() => _HomepageSettingsScreenState();
}

class _HomepageSettingsScreenState extends State<HomepageSettingsScreen> {
  final BookRepository _repository = BookRepository();
  List<Item> _libraries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLibraries();
  }

  Future<void> _loadLibraries() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;

    if (serverUrl == null || userId == null || token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final views = await _repository.getUserViews(serverUrl, userId, token);
      if (mounted) {
        setState(() {
          _libraries = views;
          _isLoading = false;
        });

        final availableIds = ['resume', ...views.map((l) => l.id)];
        Provider.of<HomepageProvider>(
          context,
          listen: false,
        ).syncAvailableSections(availableIds);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getSectionIcon(String id) {
    if (id == 'resume') {
      return Icons.play_circle_outline;
    }
    final matching = _libraries.where((l) => l.id == id).toList();
    if (matching.isNotEmpty) {
      final collectionType = matching.first.collectionType ?? '';
      switch (collectionType) {
        case 'books':
          return Icons.library_books;
        case 'movies':
          return Icons.movie;
        case 'tvshows':
          return Icons.tv;
        case 'music':
          return Icons.library_music;
        case 'homevideos':
          return Icons.video_library;
        default:
          return Icons.folder;
      }
    }
    return Icons.view_headline;
  }

  String _getSectionTitle(String id) {
    if (id == 'resume') {
      return 'Continue Reading / Watching';
    }
    final matching = _libraries.where((l) => l.id == id).toList();
    if (matching.isNotEmpty) {
      return matching.first.name ?? 'Unknown Library';
    }
    return 'Library Section';
  }

  @override
  Widget build(BuildContext context) {
    final homepageProvider = Provider.of<HomepageProvider>(context);

    final availableIds = ['resume', ..._libraries.map((l) => l.id)];
    final orderedIds =
        (homepageProvider.sectionOrder.isNotEmpty
                ? homepageProvider.sectionOrder
                : availableIds)
            .where((id) => availableIds.contains(id))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Customize Homepage')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : orderedIds.isEmpty
          ? const Center(
              child: Text('No library sections available to customize.'),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Drag to reorder homepage rows. Toggle the switch to hide or show sections.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: orderedIds.length,
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) {
                      homepageProvider.reorderSections(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final sectionId = orderedIds[index];
                      final isVisible = homepageProvider.isSectionVisible(
                        sectionId,
                      );

                      return ListTile(
                        key: ValueKey(sectionId),
                        leading: Icon(
                          _getSectionIcon(sectionId),
                          color: isVisible
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(
                          _getSectionTitle(sectionId),
                          style: TextStyle(
                            color: isVisible ? null : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isVisible,
                              onChanged: (_) {
                                homepageProvider.toggleSectionVisibility(
                                  sectionId,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(
                                Icons.drag_handle,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
