import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../repositories/book_repository.dart';
import 'book_details_screen.dart';

class LibraryItemsScreen extends StatefulWidget {
  final String libraryId;
  final String libraryName;

  const LibraryItemsScreen({
    super.key,
    required this.libraryId,
    required this.libraryName,
  });

  @override
  State<LibraryItemsScreen> createState() => _LibraryItemsScreenState();
}

class _LibraryItemsScreenState extends State<LibraryItemsScreen> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _items = [];
  int _totalCount = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadItems(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        _hasMore &&
        !_isLoading) {
      _loadItems();
    }
  }

  Future<void> _loadItems({bool reset = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repository = BookRepository();
    int startIndex = reset ? 0 : _items.length;
    try {
      final result = await repository.getItems(
        auth.serverUrl!,
        auth.userId!,
        auth.token!,
        parentId: widget.libraryId,
        limit: _pageSize,
        startIndex: startIndex,
      );
      final newItems = result['Items'] as List<dynamic>;
      final totalCount = result['TotalRecordCount'] as int? ?? 0;
      if (reset) {
        _items = newItems;
      } else {
        _items.addAll(newItems);
      }
      _totalCount = totalCount;
      _hasMore = _items.length < _totalCount;
    } catch (e) {
      debugPrint('Error loading items: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    Widget bodyContent;

    if (_items.isEmpty) {
      if (_isLoading) {
        bodyContent = const Center(child: CircularProgressIndicator());
      } else {
        bodyContent = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.library_books, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No books found in this library.'),
            ],
          ),
        );
      }
    } else {
      bodyContent = CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = _items[index];
                final isFolder =
                    item['Type'] == 'Folder' ||
                    item['Type'] == 'CollectionFolder';
                final imageUrl =
                    '${auth.serverUrl}/Items/${item['Id']}/Images/Primary';
                return InkWell(
                  onTap: () {
                    if (isFolder) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => LibraryItemsScreen(
                            libraryId: item['Id'],
                            libraryName: item['Name'] ?? 'Folder',
                          ),
                        ),
                      );
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => BookDetailsScreen(
                            itemId: item['Id'],
                            initialItem: item,
                          ),
                        ),
                      );
                    }
                  },
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const SizedBox.shrink(),
                                errorWidget: (context, url, error) => Center(
                                  child: Icon(
                                    isFolder
                                        ? Icons.folder
                                        : Icons.broken_image,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                ),
                                httpHeaders: {'X-Emby-Token': auth.token!},
                              ),
                              if (isFolder)
                                Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: Icon(
                                      Icons.folder,
                                      color: Colors.white70,
                                      size: 32,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            item['Name'] ?? 'Unknown',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }, childCount: _items.length),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
            ),
          ),
          if (_isLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (!_hasMore && _items.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(child: Text('No more items')),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.libraryName)),
      body: bodyContent,
    );
  }
}
