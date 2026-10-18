import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/jellyfin_service.dart';
import '../services/database_service.dart';
import '../models/item.dart';

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
      _refreshInBackground(() async {
        final rawItems = await _apiService.getUserViews(url, userId, token);
        final items = rawItems
            .map((j) => Item.fromJson(j as Map<String, dynamic>))
            .toList();
        await _dbService.clearCategory('user_views');
        await _dbService.saveItems(items, 'user_views');
      }, 'user_views');

      return cached;
    }

    try {
      final rawItems = await _apiService.getUserViews(url, userId, token);
      final items = rawItems
          .map((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();
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
      _refreshInBackground(() async {
        final rawItems = await _apiService.getResumeItems(url, userId, token);
        final items = rawItems
            .map((j) => Item.fromJson(j as Map<String, dynamic>))
            .toList();
        await _dbService.clearCategory('resume');
        await _dbService.saveItems(items, 'resume');
      }, 'resume');

      return cached;
    }

    try {
      final rawItems = await _apiService.getResumeItems(url, userId, token);
      final items = rawItems
          .map((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();
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
      _refreshInBackground(() async {
        final rawItems = await _apiService.getLatestMedia(
          url,
          userId,
          token,
          parentId: parentId,
        );
        final items = rawItems
            .map((j) => Item.fromJson(j as Map<String, dynamic>))
            .toList();
        await _dbService.clearCategory(category, parentId: parentId);
        await _dbService.saveItems(items, category);
      }, '$category (parentId: $parentId)');

      return cached;
    }

    try {
      final rawItems = await _apiService.getLatestMedia(
        url,
        userId,
        token,
        parentId: parentId,
      );
      final items = rawItems
          .map((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();
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
    String? includeItemTypes,
    String? genreIds,
  }) async {
    // For paginated items, caching is more complex.
    // For now, let's cache the first page or small sets.
    final category =
        'items_${parentId ?? "root"}_${recursive}_${isFavorite}_${includeItemTypes ?? "all"}';

    // Only cache if we are getting the first page or it's not paginated
    final isFirstPage = (startIndex == null || startIndex == 0);

    if (isFirstPage) {
      final cached = await _dbService.getItemsByCategory(
        category,
        parentId: parentId,
      );
      if (cached.isNotEmpty && !forceRefresh) {
        _refreshInBackground(
          () async {
            final response = await _apiService.getItems(
              url,
              userId,
              token,
              parentId: parentId,
              recursive: recursive,
              limit: limit,
              startIndex: startIndex,
              isFavorite: isFavorite,
              includeItemTypes: includeItemTypes,
              genreIds: genreIds,
            );
            final items = (response['Items'] as List)
                .map((j) => Item.fromJson(j as Map<String, dynamic>))
                .toList();
            await _dbService.clearCategory(category, parentId: parentId);
            await _dbService.saveItems(items, category);
            final totalCount = response['TotalRecordCount'] as int?;
            if (totalCount != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('total_count_$category', totalCount);
            }
          },
          '$category (parentId: $parentId, recursive: $recursive, isFavorite: $isFavorite)',
        );

        final prefs = await SharedPreferences.getInstance();
        final savedTotal = prefs.getInt('total_count_$category');
        final totalRecordCount = savedTotal ??
            (cached.length >= (limit ?? 20)
                ? cached.length + 1
                : cached.length);

        return {
          'Items': cached.map((item) => item.toJson()).toList(),
          'TotalRecordCount': totalRecordCount,
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
      includeItemTypes: includeItemTypes,
      genreIds: genreIds,
    );

    if (isFirstPage) {
      final items = (response['Items'] as List)
          .map((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();
      await _dbService.clearCategory(category, parentId: parentId);
      await _dbService.saveItems(items, category);
      final totalCount = response['TotalRecordCount'] as int?;
      if (totalCount != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('total_count_$category', totalCount);
      }
    }

    return response;
  }

  Future<void> toggleFavorite(
    String url,
    String userId,
    String itemId,
    String token,
    bool isFavorite,
  ) async {
    await _apiService.toggleFavorite(url, userId, itemId, token, isFavorite);
    await _dbService.updateItemUserData(itemId, isFavorite: isFavorite);
  }

  Future<void> togglePlayed(
    String url,
    String userId,
    String itemId,
    String token,
    bool played,
  ) async {
    await _apiService.togglePlayed(url, userId, itemId, token, played);
    await _dbService.updateItemUserData(itemId, played: played);
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
      _refreshInBackground(() async {
        final rawItem = await _apiService.getItemDetails(
          url,
          userId,
          token,
          itemId,
        );
        final item = Item.fromJson(rawItem);
        await _dbService.saveItems([item], 'details');
      }, 'item details (itemId: $itemId)');

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

  /// Fire-and-forget background cache refresh. Catches errors silently.
  Future<void> _refreshInBackground(
    Future<void> Function() refresh,
    String label,
  ) async {
    try {
      await refresh();
    } catch (e) {
      debugPrint('Background cache refresh failed for $label: $e');
    }
  }
}
