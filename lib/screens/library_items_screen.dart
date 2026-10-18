import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../repositories/book_repository.dart';
import 'item_details_screen.dart';

class LibraryItemsScreen extends StatefulWidget {
  final String? libraryId;
  final String libraryName;
  final bool isFavoriteOnly;
  final String? includeItemTypes;
  final String? genreIds;

  const LibraryItemsScreen({
    super.key,
    this.libraryId,
    required this.libraryName,
    this.isFavoriteOnly = false,
    this.includeItemTypes,
    this.genreIds,
  });

  @override
  State<LibraryItemsScreen> createState() => _LibraryItemsScreenState();
}

class _LibraryItemsScreenState extends State<LibraryItemsScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _totalCount = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isGridView = true;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadViewPreference();
    _loadItems(reset: true);
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'library_view_grid_${widget.libraryId ?? "favorites"}';
    final saved = prefs.getBool(key);
    if (mounted && saved != null) {
      setState(() {
        _isGridView = saved;
      });
    }
  }

  Future<void> _saveViewPreference(bool isGrid) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'library_view_grid_${widget.libraryId ?? "favorites"}';
    await prefs.setBool(key, isGrid);
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
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final token = auth.token;

    if (serverUrl == null || userId == null || token == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final repository = BookRepository();
    int startIndex = reset ? 0 : _items.length;
    try {
      final result = await repository.getItems(
        serverUrl,
        userId,
        token,
        parentId: widget.isFavoriteOnly ? null : widget.libraryId,
        recursive: widget.isFavoriteOnly || widget.includeItemTypes != null
            ? true
            : false,
        limit: _pageSize,
        startIndex: startIndex,
        isFavorite: widget.isFavoriteOnly,
        includeItemTypes: widget.includeItemTypes,
        genreIds: widget.genreIds,
      );
      final newItems = (result['Items'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
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
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildGridItem(BuildContext context, Map<String, dynamic> item) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final serverUrl = auth.serverUrl;
    final token = auth.token;
    final itemType = item['Type'] as String?;
    final itemId = item['Id'] as String? ?? '';
    final isFolder =
        itemType == 'Folder' ||
        itemType == 'CollectionFolder' ||
        itemType == 'Series' ||
        itemType == 'Season' ||
        itemType == 'MusicAlbum' ||
        itemType == 'MusicArtist';
    final imageUrl =
        serverUrl != null ? '$serverUrl/Items/$itemId/Images/Primary' : '';
    return InkWell(
      onTap: () {
        if (isFolder) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => LibraryItemsScreen(
                libraryId: itemId,
                libraryName: item['Name'] as String? ?? 'Folder',
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => ItemDetailsScreen(
                itemId: itemId,
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
                    placeholder: (context, url) => const SizedBox.shrink(),
                    errorWidget: (context, url, error) => Center(
                      child: Icon(
                        isFolder ? Icons.folder : Icons.broken_image,
                        size: 48,
                        color: Colors.grey,
                      ),
                    ),
                    httpHeaders:
                        token != null ? {'X-Emby-Token': token} : const {},
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
                item['Name'] as String? ?? 'Unknown',
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
  }

  Widget _buildListItem(BuildContext context, Map<String, dynamic> item) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final serverUrl = auth.serverUrl;
    final token = auth.token;
    final itemType = item['Type'] as String?;
    final itemId = item['Id'] as String? ?? '';
    final isFolder =
        itemType == 'Folder' ||
        itemType == 'CollectionFolder' ||
        itemType == 'Series' ||
        itemType == 'Season' ||
        itemType == 'MusicAlbum' ||
        itemType == 'MusicArtist';
    final imageUrl =
        serverUrl != null ? '$serverUrl/Items/$itemId/Images/Primary' : '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 48,
            height: 48,
            child: isFolder
                ? Container(
                    color: Colors.grey.withValues(alpha: 0.2),
                    child: const Icon(Icons.folder, color: Colors.grey),
                  )
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox.shrink(),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.broken_image, color: Colors.grey),
                    httpHeaders:
                        token != null ? {'X-Emby-Token': token} : const {},
                  ),
          ),
        ),
        title: Text(
          item['Name'] as String? ?? 'Unknown',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          itemType ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Icon(
          isFolder ? Icons.chevron_right : Icons.play_circle_outline,
          color: Colors.grey,
        ),
        onTap: () {
          if (isFolder) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => LibraryItemsScreen(
                  libraryId: itemId,
                  libraryName: item['Name'] as String? ?? 'Folder',
                ),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => ItemDetailsScreen(
                  itemId: itemId,
                  initialItem: item,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Text('No items found in this library.'),
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
            sliver: _isGridView
                ? SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return _buildGridItem(context, _items[index]);
                    }, childCount: _items.length),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          childAspectRatio: 2 / 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return _buildListItem(context, _items[index]);
                    }, childCount: _items.length),
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
      appBar: AppBar(
        title: Text(widget.libraryName),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: _isGridView ? 'List view' : 'Grid view',
            onPressed: () {
              final newValue = !_isGridView;
              setState(() {
                _isGridView = newValue;
              });
              _saveViewPreference(newValue);
            },
          ),
        ],
      ),
      body: bodyContent,
    );
  }
}
