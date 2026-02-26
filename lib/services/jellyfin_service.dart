import 'package:dio/dio.dart';

class JellyfinService {
  final Dio _dio = Dio();

  Future<Map<String, dynamic>> authenticate(
    String url,
    String username,
    String password,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    final headers = {
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
      'Content-Type': 'application/json',
    };

    try {
      final response = await _dio.post(
        '$baseUrl/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Authentication failed');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
          e.response?.data['ErrorMessage'] ?? 'Authentication failed',
        );
      } else {
        throw Exception('Connection failed: ${e.message}');
      }
    }
  }

  Future<List<dynamic>> getUserViews(
    String url,
    String userId,
    String token,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    try {
      final response = await _dio.get(
        '$baseUrl/Users/$userId/Views',
        options: Options(headers: headers),
      );
      // Filter for libraries that are specifically for books
      final items = response.data['Items'] as List<dynamic>? ?? [];
      return items.where((item) => item['CollectionType'] == 'books').toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getResumeItems(
    String url,
    String userId,
    String token,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    try {
      final response = await _dio.get(
        '$baseUrl/Users/$userId/Items/Resume',
        queryParameters: {'IncludeItemTypes': 'Book', 'Recursive': true},
        options: Options(headers: headers),
      );
      return response.data['Items'] ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getLatestMedia(
    String url,
    String userId,
    String token, {
    String? parentId,
  }) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    final Map<String, dynamic> queryParameters = {'IncludeItemTypes': 'Book'};
    if (parentId != null) {
      queryParameters['ParentId'] = parentId;
    }

    try {
      final response = await _dio.get(
        '$baseUrl/Users/$userId/Items/Latest',
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return response.data;
    } catch (e) {
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
  }) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    final Map<String, dynamic> queryParameters = {
      'IncludeItemTypes': 'Book,Folder,CollectionFolder',
      'Recursive': recursive,
      'Fields': 'PrimaryImageAspectRatio,SortName,Type',
      'SortBy': 'SortName',
      'SortOrder': 'Ascending',
    };
    if (limit != null) queryParameters['Limit'] = limit;
    if (startIndex != null) queryParameters['StartIndex'] = startIndex;
    if (parentId != null) {
      queryParameters['ParentId'] = parentId;
    }

    try {
      final response = await _dio.get(
        '$baseUrl/Users/$userId/Items',
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return {
        'Items': response.data['Items'] ?? [],
        'TotalRecordCount': response.data['TotalRecordCount'] ?? 0,
      };
    } catch (e) {
      return {'Items': [], 'TotalRecordCount': 0};
    }
  }

  Future<Map<String, dynamic>> getItemDetails(
    String url,
    String userId,
    String token,
    String itemId,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    try {
      final response = await _dio.get(
        '$baseUrl/Users/$userId/Items/$itemId',
        options: Options(headers: headers),
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to fetch item details');
    }
  }

  String getPageImageUrl(
    String baseUrl,
    String itemId,
    String token,
    int index,
  ) {
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBaseUrl/Items/$itemId/Images/Primary?index=$index&maxWidth=1920';
  }

  String getDownloadUrl(String url, String itemId, String token) {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return '$baseUrl/Items/$itemId/Download?api_key=$token';
  }

  Future<List<int>> downloadItem(
    String url,
    String token,
    String itemId,
  ) async {
    final downloadUrl = getDownloadUrl(url, itemId, token);
    final response = await _dio.get<List<int>>(
      downloadUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? [];
  }

  Future<void> downloadItemToPath(
    String url,
    String token,
    String itemId,
    String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  ) async {
    final downloadUrl = getDownloadUrl(url, itemId, token);
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    await _dio.download(
      downloadUrl,
      savePath,
      options: Options(headers: headers, responseType: ResponseType.stream),
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<void> toggleFavorite(
    String url,
    String userId,
    String itemId,
    String token,
    bool isFavorite,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    final endpoint = '$baseUrl/Users/$userId/FavoriteItems/$itemId';

    if (isFavorite) {
      await _dio.post(endpoint, options: Options(headers: headers));
    } else {
      await _dio.delete(endpoint, options: Options(headers: headers));
    }
  }

  Future<void> togglePlayed(
    String url,
    String userId,
    String itemId,
    String token,
    bool isPlayed,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };

    final endpoint = '$baseUrl/Users/$userId/PlayedItems/$itemId';

    if (isPlayed) {
      await _dio.post(endpoint, options: Options(headers: headers));
    } else {
      await _dio.delete(endpoint, options: Options(headers: headers));
    }
  }

  Future<String?> getDownloadFilename(
    String url,
    String token,
    String itemId,
  ) async {
    final downloadUrl = getDownloadUrl(url, itemId, token);
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
    };
    try {
      final response = await _dio.head(
        downloadUrl,
        options: Options(headers: headers),
      );
      final contentDisposition = response.headers.value('content-disposition');
      if (contentDisposition != null) {
        final filename = _extractFilenameFromContentDisposition(
          contentDisposition,
        );
        if (filename.isNotEmpty) {
          return filename;
        }
      }
    } catch (e) {
      // ignore errors
    }
    return null;
  }

  Future<void> reportPlaybackStart(
    String url,
    String userId,
    String token,
    String itemId,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
      'Content-Type': 'application/json',
    };

    try {
      await _dio.post(
        '$baseUrl/Sessions/Playing',
        data: {'ItemId': itemId},
        options: Options(headers: headers),
      );
    } catch (e) {
      // Silently fail for progress reporting
    }
  }

  Future<void> reportPlaybackStopped(
    String url,
    String userId,
    String token,
    String itemId,
    int positionTicks,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
      'Content-Type': 'application/json',
    };

    try {
      await _dio.post(
        '$baseUrl/Sessions/Playing/Stopped',
        data: {'ItemId': itemId, 'PositionTicks': positionTicks},
        options: Options(headers: headers),
      );
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> reportProgress(
    String url,
    String userId,
    String token,
    String itemId,
    int positionTicks,
    bool isPaused,
  ) async {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final headers = {
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="finbuk-android-device", Version="1.0.0"',
      'Content-Type': 'application/json',
    };

    try {
      await _dio.post(
        '$baseUrl/Sessions/Playing/Progress',
        data: {
          'ItemId': itemId,
          'PositionTicks': positionTicks,
          'IsPaused': isPaused,
        },
        options: Options(headers: headers),
      );
    } catch (e) {
      // Silently fail
    }
  }

  String _extractFilenameFromContentDisposition(String contentDisposition) {
    // Example: attachment; filename="filename.ext"
    // Or: attachment; filename*=UTF-8''filename.ext
    final parts = contentDisposition.split(';');
    for (var part in parts) {
      part = part.trim();
      if (part.startsWith('filename=')) {
        String filename = part.substring(9);
        if (filename.startsWith('"') && filename.endsWith('"')) {
          filename = filename.substring(1, filename.length - 1);
        }
        return Uri.decodeFull(filename);
      } else if (part.startsWith('filename*=')) {
        String filename = part.substring(10);
        // Remove charset'' if present
        final index = filename.indexOf("''");
        if (index != -1) {
          filename = filename.substring(index + 2);
        }
        return Uri.decodeFull(filename);
      }
    }
    return '';
  }
}
