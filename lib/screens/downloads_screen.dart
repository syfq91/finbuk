import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../services/file_service.dart';
import '../models/item.dart';
import 'book_details_screen.dart';
import 'comic_reader_screen.dart';
import 'epub_reader_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final FileService _fileService = FileService();
  List<Item>? _downloadedItems;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    if (mounted) setState(() => _isLoading = true);
    final items = await _fileService.getDownloadedItems();
    if (mounted) {
      setState(() {
        _downloadedItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(Item item) async {
    final ext = _fileService.getExtension(item.rawJson);
    await _fileService.deleteDownloadedItem(item.id, ext);
    _loadDownloads();
  }

  Future<void> _navigateToReader(Item item) async {
    final ext = _fileService.getExtension(item.rawJson).toLowerCase();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (ext == '.pdf') {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('PDF reading is not supported')),
        );
      }
      return;
    }
    String? filePath;

    // Use FileService to find the file regardless of how it was named on disk
    final file = await _fileService.findDownloadedFileByItemId(item.id);
    if (file != null) {
      filePath = file.path;
    }

    if (ext == '.cbz' || ext == '.cbr') {
      if (mounted) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => ComicReaderScreen(
              itemId: item.id,
              title: item.name ?? 'Comic Reader',
              filePath: filePath,
            ),
          ),
        );
      }
    } else if (ext == '.epub') {
      if (mounted) {
        navigator.push(
          MaterialPageRoute(
            builder: (context) => EpubReaderScreen(
              itemId: item.id,
              title: item.name ?? 'EPUB Reader',
              filePath: filePath,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unsupported format for reading')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_downloadedItems == null || _downloadedItems!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No downloaded books yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDownloads,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _downloadedItems!.length,
        itemBuilder: (context, index) {
          final item = _downloadedItems![index];
          final auth = Provider.of<AuthProvider>(context, listen: false);
          final imageUrl = '${auth.serverUrl}/Items/${item.id}/Images/Primary';
          final token = auth.token;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () => _navigateToReader(item),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cover Image
                    SizedBox(
                      width: 80,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        httpHeaders: token != null
                            ? {'X-Emby-Token': token}
                            : const {},
                        placeholder: (context, url) => Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.book, color: Colors.grey),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.book, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Details
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.name ?? 'Unknown',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.rawJson['ProductionYear'] != null)
                              Text(
                                '${item.rawJson['ProductionYear']}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Actions
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => BookDetailsScreen(
                                  itemId: item.id,
                                  initialItem: item.rawJson,
                                ),
                              ),
                            );
                          },
                          tooltip: 'Details',
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _confirmDelete(item),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(Item item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Download'),
        content: Text(
          'Are you sure you want to remove "${item.name}" from your device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteItem(item);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
