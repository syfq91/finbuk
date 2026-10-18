import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finbuk/models/item.dart';
import 'package:finbuk/repositories/book_repository.dart';
import 'package:finbuk/services/jellyfin_service.dart';
import 'package:finbuk/services/database_service.dart';

class FakeDatabaseService extends DatabaseService {
  FakeDatabaseService() : super._internal();

  final Map<String, List<Item>> _categoryStore = <String, List<Item>>{};
  final Map<String, Map<String, dynamic>> _itemUserData =
      <String, Map<String, dynamic>>{};

  @override
  Future<List<Item>> getItemsByCategory(
    String category, {
    String? parentId,
  }) async {
    return _categoryStore[category] ?? <Item>[];
  }

  @override
  Future<void> saveItems(List<Item> items, String category) async {
    _categoryStore[category] = List<Item>.from(items);
  }

  @override
  Future<void> clearCategory(String category, {String? parentId}) async {
    _categoryStore.remove(category);
  }

  @override
  Future<void> updateItemUserData(
    String itemId, {
    bool? isFavorite,
    bool? played,
    int? playbackPositionTicks,
  }) async {
    _itemUserData[itemId] = <String, dynamic>{
      'isFavorite': isFavorite,
      'played': played,
      'playbackPositionTicks': playbackPositionTicks,
    };
  }
}

class FakeJellyfinService extends JellyfinService {
  List<Map<String, dynamic>> userViewsResponse = <Map<String, dynamic>>[];
  Map<String, dynamic> itemsResponse = <String, dynamic>{};
  bool toggleFavoriteCalled = false;
  bool togglePlayedCalled = false;
  bool? lastFavoriteValue;
  bool? lastPlayedValue;

  @override
  Future<List<dynamic>> getUserViews(
    String url,
    String userId,
    String token,
  ) async {
    return userViewsResponse;
  }

  @override
  Future<Map<String, dynamic>> getItems(
    String url,
    String userId,
    String token, {
    String? parentId,
    bool recursive = false,
    int? limit,
    int? startIndex,
    bool isFavorite = false,
    String? includeItemTypes,
    String? genreIds,
  }) async {
    return itemsResponse;
  }

  @override
  Future<void> toggleFavorite(
    String url,
    String userId,
    String itemId,
    String token,
    bool isFavorite,
  ) async {
    toggleFavoriteCalled = true;
    lastFavoriteValue = isFavorite;
  }

  @override
  Future<void> togglePlayed(
    String url,
    String userId,
    String itemId,
    String token,
    bool isPlayed,
  ) async {
    togglePlayedCalled = true;
    lastPlayedValue = isPlayed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookRepository Unit Tests', () {
    late FakeDatabaseService fakeDb;
    late FakeJellyfinService fakeApi;
    late BookRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      fakeDb = FakeDatabaseService();
      fakeApi = FakeJellyfinService();
      repository = BookRepository(
        apiService: fakeApi,
        dbService: fakeDb,
      );
    });

    test('getUserViews fetches from API and caches to DB when cache is empty', () async {
      fakeApi.userViewsResponse = <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'lib-1',
          'Name': 'Comics Library',
          'Type': 'CollectionFolder',
        },
      ];

      final items = await repository.getUserViews(
        'http://localhost:8096',
        'user-1',
        'token-1',
      );

      expect(items.length, equals(1));
      expect(items.first.id, equals('lib-1'));
      expect(items.first.name, equals('Comics Library'));

      // Check that it was saved to DB cache
      final cached = await fakeDb.getItemsByCategory('user_views');
      expect(cached.length, equals(1));
      expect(cached.first.id, equals('lib-1'));
    });

    test('getUserViews returns cached items immediately without waiting for API', () async {
      final cachedItem = Item.fromJson(<String, dynamic>{
        'Id': 'cached-1',
        'Name': 'Cached Library',
        'Type': 'CollectionFolder',
      });
      await fakeDb.saveItems(<Item>[cachedItem], 'user_views');

      final items = await repository.getUserViews(
        'http://localhost:8096',
        'user-1',
        'token-1',
      );

      expect(items.length, equals(1));
      expect(items.first.id, equals('cached-1'));
    });

    test('getItems caches first page and calculates TotalRecordCount correctly', () async {
      fakeApi.itemsResponse = <String, dynamic>{
        'Items': <Map<String, dynamic>>[
          <String, dynamic>{
            'Id': 'book-1',
            'Name': 'Batman Year One',
            'Type': 'Book',
          },
        ],
        'TotalRecordCount': 42,
      };

      final result = await repository.getItems(
        'http://localhost:8096',
        'user-1',
        'token-1',
        startIndex: 0,
        limit: 10,
      );

      expect(result['TotalRecordCount'], equals(42));
      final items = result['Items'] as List<dynamic>;
      expect(items.length, equals(1));
      expect(items.first['Id'], equals('book-1'));
    });

    test('toggleFavorite delegates to both JellyfinService and DatabaseService', () async {
      await repository.toggleFavorite(
        'http://localhost:8096',
        'user-1',
        'item-99',
        'token-1',
        true,
      );

      expect(fakeApi.toggleFavoriteCalled, isTrue);
      expect(fakeApi.lastFavoriteValue, isTrue);
      expect(fakeDb._itemUserData['item-99']?['isFavorite'], isTrue);
    });

    test('togglePlayed delegates to both JellyfinService and DatabaseService', () async {
      await repository.togglePlayed(
        'http://localhost:8096',
        'user-1',
        'item-88',
        'token-1',
        true,
      );

      expect(fakeApi.togglePlayedCalled, isTrue);
      expect(fakeApi.lastPlayedValue, isTrue);
      expect(fakeDb._itemUserData['item-88']?['played'], isTrue);
    });
  });
}
