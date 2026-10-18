import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finbuk/services/jellyfin_service.dart';

class MockHttpAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  Map<String, dynamic> responseData;
  int statusCode;

  MockHttpAdapter({required this.responseData, this.statusCode = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    final jsonString = jsonEncode(responseData);
    return ResponseBody.fromString(
      jsonString,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('JellyfinService Unit Tests', () {
    late Dio dio;
    late MockHttpAdapter mockAdapter;
    late JellyfinService jellyfinService;

    setUp(() {
      mockAdapter = MockHttpAdapter(
        responseData: <String, dynamic>{
          'AccessToken': 'mock_token_123',
          'User': <String, dynamic>{'Id': 'user_abc', 'Name': 'TestUser'},
        },
      );
      dio = Dio();
      dio.httpClientAdapter = mockAdapter;
      jellyfinService = JellyfinService(dio: dio);
      JellyfinService.defaultDeviceId = null;
    });

    test('normalizes URLs and strips trailing slashes', () {
      final downloadUrl = jellyfinService.getDownloadUrl(
        'http://jellyfin.local:8096///',
        'item-42',
        'my-token',
      );
      expect(
        downloadUrl,
        equals('http://jellyfin.local:8096/Items/item-42/Download'),
      );
    });

    test('generates comic page image URL correctly', () {
      final pageUrl = jellyfinService.getPageImageUrl(
        'https://my-server.com/',
        'item-99',
        'token-abc',
        3,
      );
      expect(
        pageUrl,
        equals(
          'https://my-server.com/Items/item-99/Images/Primary?index=3&maxWidth=1920',
        ),
      );
    });

    test(
      'authenticate transmits credentials and custom deviceId in headers',
      () async {
        final result = await jellyfinService.authenticate(
          'http://example.com:8096/',
          'jellyuser',
          'secretpass',
          deviceId: 'custom-device-uuid-1234',
        );

        expect(result['AccessToken'], equals('mock_token_123'));
        expect(mockAdapter.lastOptions, isNotNull);
        expect(
          mockAdapter.lastOptions!.path,
          equals('http://example.com:8096/Users/AuthenticateByName'),
        );

        final embyAuthHeader =
            mockAdapter.lastOptions!.headers['X-Emby-Authorization'] as String;
        expect(embyAuthHeader, contains('DeviceId="custom-device-uuid-1234"'));
        expect(embyAuthHeader, contains('Client="Finbuk Android"'));

        final standardAuthHeader =
            mockAdapter.lastOptions!.headers['Authorization'] as String;
        expect(
          standardAuthHeader,
          contains('DeviceId="custom-device-uuid-1234"'),
        );
        expect(standardAuthHeader, contains('Client="Finbuk Android"'));

        final body = mockAdapter.lastOptions!.data as Map<String, dynamic>;
        expect(body['Username'], equals('jellyuser'));
        expect(body['Pw'], equals('secretpass'));
      },
    );

    test(
      'authenticate falls back to defaultDeviceId when deviceId param is omitted',
      () async {
        JellyfinService.defaultDeviceId = 'global-device-id-5678';

        await jellyfinService.authenticate(
          'http://example.com:8096',
          'jellyuser',
          'secretpass',
        );

        final embyAuthHeader =
            mockAdapter.lastOptions!.headers['X-Emby-Authorization'] as String;
        expect(embyAuthHeader, contains('DeviceId="global-device-id-5678"'));

        final standardAuthHeader =
            mockAdapter.lastOptions!.headers['Authorization'] as String;
        expect(
          standardAuthHeader,
          contains('DeviceId="global-device-id-5678"'),
        );
      },
    );

    test(
      'toggleFavorite sends POST when isFavorite is true and DELETE when false',
      () async {
        await jellyfinService.toggleFavorite(
          'http://example.com',
          'user-1',
          'item-2',
          'token-3',
          true,
        );

        expect(mockAdapter.lastOptions!.method, equals('POST'));
        expect(
          mockAdapter.lastOptions!.path,
          equals('http://example.com/Users/user-1/FavoriteItems/item-2'),
        );

        await jellyfinService.toggleFavorite(
          'http://example.com',
          'user-1',
          'item-2',
          'token-3',
          false,
        );

        expect(mockAdapter.lastOptions!.method, equals('DELETE'));
        expect(
          mockAdapter.lastOptions!.path,
          equals('http://example.com/Users/user-1/FavoriteItems/item-2'),
        );
      },
    );

    test(
      'togglePlayed sends POST when isPlayed is true and DELETE when false',
      () async {
        await jellyfinService.togglePlayed(
          'http://example.com',
          'user-1',
          'item-2',
          'token-3',
          true,
        );

        expect(mockAdapter.lastOptions!.method, equals('POST'));
        expect(
          mockAdapter.lastOptions!.path,
          equals('http://example.com/Users/user-1/PlayedItems/item-2'),
        );

        await jellyfinService.togglePlayed(
          'http://example.com',
          'user-1',
          'item-2',
          'token-3',
          false,
        );

        expect(mockAdapter.lastOptions!.method, equals('DELETE'));
        expect(
          mockAdapter.lastOptions!.path,
          equals('http://example.com/Users/user-1/PlayedItems/item-2'),
        );
      },
    );

    test(
      'reportPlaybackStopped sends position ticks to session endpoint',
      () async {
        await jellyfinService.reportPlaybackStopped(
          'http://example.com',
          'user-1',
          'token-1',
          'item-10',
          12345678,
        );

        expect(mockAdapter.lastOptions!.method, equals('POST'));
        expect(
          mockAdapter.lastOptions!.path,
          equals('http://example.com/Sessions/Playing/Stopped'),
        );

        final body = mockAdapter.lastOptions!.data as Map<String, dynamic>;
        expect(body['ItemId'], equals('item-10'));
        expect(body['PositionTicks'], equals(12345678));
      },
    );
  });
}
