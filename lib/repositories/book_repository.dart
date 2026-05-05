import '../services/jellyfin_service.dart';
import '../services/database_service.dart';
import '../models/item.dart';
import 'package:flutter/foundation.dart';

class BookRepository {
  final JellyfinService _apiService = JellyfinService();
  final DatabaseService _dbService = DatabaseService();

  Future<List<Item>> getUserViews(
    String url,
    String userId,
    String token, {
    bool forceRefresh = false,
  }) async {
    final cached = await _dbService.getItemsByCategory('user_views');

    if (cached.isNotEmpty && !forceRefresh) {
      // Return cached but update in background
      _apiService
          .getUserViews(url, userId, token)
          .then((rawItems) async {
            final items = rawItems.map((j) => Item.fromJson(j)).toList();
            await _dbService.clearCategory('user_views');
            await _dbService.saveItems(items, 'user_views');
          })
          .catchError(
            (e) => debugPrint(
              'Background cache refresh failed for user_views: $e',
            ),
          );

      return cached;
    }

    try {
      final rawItems = await _apiService.getUserViews(url, userId, token);
      final items = rawItems.map((json) => Item.fromJson(json)).toList();
      await _dbService.clearCategory('user_views');
      await _dbService.saveItems(items, 'user_views');
      return items;
    } catch (e) {
      if (cached.isNotEmpty) return cached;
      return [];
    }
  }

  Future<List<Item>> getResumeItems(
    String url,
    String userId,
    String token, {
    bool forceRefresh = false,
  }) async {
    final cached = await _dbService.getItemsByCategory('resume');

    if (cached.isNotEmpty && !forceRefresh) {
      _apiService
          .getResumeItems(url, userId, token)
          .then((rawItems) async {
            final items = rawItems.map((j) => Item.fromJson(j)).toList();
            await _dbService.clearCategory('resume');
            await _dbService.saveItems(items, 'resume');
          })
          .catchError(
            (e) => debugPrint('Background cache refresh failed for resume: $e'),
          );
      return cached;
    }

    try {
      final rawItems = await _apiService.getResumeItems(url, userId, token);
      final items = rawItems.map((json) => Item.fromJson(json)).toList();
      await _dbService.clearCategory('resume');
      await _dbService.saveItems(items, 'resume');
      return items;
    } catch (e) {
      if (cached.isNotEmpty) return cached;
      return [];
    }
  }

  Future<List<Item>> getLatestMedia(
    String url,
    String userId,
    String token, {
    String? parentId,
    bool forceRefresh = false,
  }) async {
    final category = 'latest_${parentId ?? "all"}';
    final cached = await _dbService.getItemsByCategory(
      category,
      parentId: parentId,
    );

    if (cached.isNotEmpty && !forceRefresh) {
      _apiService
          .getLatestMedia(url, userId, token, parentId: parentId)
          .then((rawItems) async {
            final items = rawItems.map((j) => Item.fromJson(j)).toList();
            await _dbService.clearCategory(category, parentId: parentId);
            await _dbService.saveItems(items, category);
          })
          .catchError(
            (e) => debugPrint(
              'Background cache refresh failed for $category (parentId: $parentId): $e',
            ),
          );
      return cached;
    }

    try {
      final rawItems = await _apiService.getLatestMedia(
        url,
        userId,
        token,
        parentId: parentId,
      );
      final items = rawItems.map((json) => Item.fromJson(json)).toList();
      await _dbService.clearCategory(category, parentId: parentId);
      await _dbService.saveItems(items, category);
      return items;
    } catch (e) {
      if (cached.isNotEmpty) return cached;
      return [];
    }
  }

  Future<Map<String, dynamic>> getItems(
    String url,
    String userId,
    String token, {
    String? parentId,
    bool recursive = false,
    int? limit,
    int? startIndex,
    bool isFavorite = false,
    bool forceRefresh = false,
  }) async {
    // For paginated items, caching is more complex.
    // For now, let's cache the first page or small sets.
    final category = 'items_${parentId ?? "root"}_${recursive}_$isFavorite';

    // Only cache if we are getting the first page or it's not paginated
    final isFirstPage = (startIndex == null || startIndex == 0);

    if (isFirstPage) {
      final cached = await _dbService.getItemsByCategory(
        category,
        parentId: parentId,
      );
      if (cached.isNotEmpty && !forceRefresh) {
        _apiService
            .getItems(
              url,
              userId,
              token,
              parentId: parentId,
              recursive: recursive,
              limit: limit,
              startIndex: startIndex,
              isFavorite: isFavorite,
            )
            .then((response) async {
              final items = (response['Items'] as List)
                  .map((j) => Item.fromJson(j))
                  .toList();
              await _dbService.clearCategory(category, parentId: parentId);
              await _dbService.saveItems(items, category);
            })
            .catchError(
              (e) => debugPrint(
                'Background cache refresh failed for $category (parentId: $parentId, recursive: $recursive, isFavorite: $isFavorite): $e',
              ),
            );

        return {
          'Items': cached.map((item) => item.toJson()).toList(),
          'TotalRecordCount': cached.length, // Approximation
        };
      }
    }

    final response = await _apiService.getItems(
      url,
      userId,
      token,
      parentId: parentId,
      recursive: recursive,
      limit: limit,
      startIndex: startIndex,
      isFavorite: isFavorite,
    );

    if (isFirstPage) {
      final items = (response['Items'] as List)
          .map((json) => Item.fromJson(json))
          .toList();
      await _dbService.clearCategory(category, parentId: parentId);
      await _dbService.saveItems(items, category);
    }

    return response;
  }

  Future<Map<String, dynamic>> getItemDetails(
    String url,
    String userId,
    String token,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    final cached = await _dbService.getItemById(itemId);

    if (cached != null && !forceRefresh) {
      // Return cached but update in background
      _apiService
          .getItemDetails(url, userId, token, itemId)
          .then((rawItem) async {
            final item = Item.fromJson(rawItem);
            await _dbService.saveItems([item], 'details');
          })
          .catchError(
            (e) => debugPrint(
              'Background cache refresh failed for item details (itemId: $itemId): $e',
            ),
          );

      return cached.toJson();
    }

    try {
      final rawItem = await _apiService.getItemDetails(
        url,
        userId,
        token,
        itemId,
      );
      final item = Item.fromJson(rawItem);
      await _dbService.saveItems([item], 'details');
      return rawItem;
    } catch (e) {
      if (cached != null) return cached.toJson();
      rethrow;
    }
  }
}
