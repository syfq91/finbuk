import 'package:dio/dio.dart';

class JellyfinService {
  final Dio _dio;
  static String? defaultDeviceId;

  JellyfinService({Dio? dio}) : _dio = dio ?? Dio();

  static String _normalizeUrl(String url) {
    return url.trim().replaceAll(RegExp(r'/+$'), '');
  }

  static Map<String, String> _authHeaders(
    String token, {
    bool json = false,
    String? deviceId,
  }) {
    final devId = deviceId ?? defaultDeviceId ?? 'finbuk-android-device';
    final headers = <String, String>{
      'X-Emby-Token': token,
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="$devId", Version="1.0.0"',
    };
    if (json) headers['Content-Type'] = 'application/json';
    return headers;
  }

  Future<Map<String, dynamic>> authenticate(
    String url,
    String username,
    String password, {
    String? deviceId,
  }) async {
    final baseUrl = _normalizeUrl(url);
    final devId = deviceId ?? defaultDeviceId ?? 'finbuk-android-device';

    final headers = {
      'X-Emby-Authorization':
          'MediaBrowser Client="Finbuk Android", Device="Android Device", DeviceId="$devId", Version="1.0.0"',
      'Content-Type': 'application/json',
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data == null) {
          throw Exception('Authentication failed');
        }
        return data;
      } else {
        throw Exception('Authentication failed');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final errorData = e.response?.data;
        throw Exception(
          errorData is Map<String, dynamic>
              ? errorData['ErrorMessage'] as String? ?? 'Authentication failed'
              : 'Authentication failed',
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
    final baseUrl = _normalizeUrl(url);

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/Users/$userId/Views',
        options: Options(headers: _authHeaders(token)),
      );
      // Return all library views (books, movies, tvshows, music, etc.)
      return response.data?['Items'] as List<dynamic>? ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getResumeItems(
    String url,
    String userId,
    String token,
  ) async {
    final baseUrl = _normalizeUrl(url);

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/Users/$userId/Items/Resume',
        queryParameters: {
          'IncludeItemTypes': 'Book,Movie,Episode,Audio,AudioBook',
          'Recursive': true,
        },
        options: Options(headers: _authHeaders(token)),
      );
      return response.data?['Items'] as List<dynamic>? ?? [];
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
    final baseUrl = _normalizeUrl(url);

    final Map<String, dynamic> queryParameters = {};
    if (parentId != null) {
      queryParameters['ParentId'] = parentId;
    }

    try {
      final response = await _dio.get<List<dynamic>>(
        '$baseUrl/Users/$userId/Items/Latest',
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders(token)),
      );
      return response.data ?? [];
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
    bool isFavorite = false,
    String? includeItemTypes,
    String? genreIds,
  }) async {
    final baseUrl = _normalizeUrl(url);

    final Map<String, dynamic> queryParameters = {
      'IncludeItemTypes':
          includeItemTypes ??
          'Book,Folder,CollectionFolder,Movie,Episode,Series,Season,Audio,MusicAlbum,MusicArtist,AudioBook',
      'Recursive': recursive,
      'Fields': 'PrimaryImageAspectRatio,SortName,Type,UserData',
      'SortBy': 'SortName',
      'SortOrder': 'Ascending',
    };
    if (limit != null) queryParameters['Limit'] = limit;
    if (startIndex != null) queryParameters['StartIndex'] = startIndex;
    if (parentId != null) {
      queryParameters['ParentId'] = parentId;
    }
    if (isFavorite) {
      queryParameters['Filters'] = 'IsFavorite';
    }
    if (genreIds != null) {
      queryParameters['GenreIds'] = genreIds;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/Users/$userId/Items',
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders(token)),
      );
      return {
        'Items': response.data?['Items'] ?? <dynamic>[],
        'TotalRecordCount': response.data?['TotalRecordCount'] ?? 0,
      };
    } catch (e) {
      return {'Items': <dynamic>[], 'TotalRecordCount': 0};
    }
  }

  Future<Map<String, dynamic>> getItemDetails(
    String url,
    String userId,
    String token,
    String itemId,
  ) async {
    final baseUrl = _normalizeUrl(url);

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/Users/$userId/Items/$itemId',
        options: Options(headers: _authHeaders(token)),
      );
      return response.data ?? <String, dynamic>{};
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
    final cleanBaseUrl = _normalizeUrl(baseUrl);
    return '$cleanBaseUrl/Items/$itemId/Images/Primary?index=$index&maxWidth=1920';
  }

  String getDownloadUrl(String url, String itemId, String token) {
    final baseUrl = _normalizeUrl(url);
    return '$baseUrl/Items/$itemId/Download';
  }

  Future<List<int>> downloadItem(
    String url,
    String token,
    String itemId,
  ) async {
    final downloadUrl = getDownloadUrl(url, itemId, token);
    final response = await _dio.get<List<int>>(
      downloadUrl,
      options: Options(
        headers: _authHeaders(token),
        responseType: ResponseType.bytes,
      ),
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

    await _dio.download(
      downloadUrl,
      savePath,
      options: Options(
        headers: _authHeaders(token),
        responseType: ResponseType.stream,
      ),
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
    final baseUrl = _normalizeUrl(url);
    final endpoint = '$baseUrl/Users/$userId/FavoriteItems/$itemId';

    if (isFavorite) {
      await _dio.post<void>(
        endpoint,
        options: Options(headers: _authHeaders(token)),
      );
    } else {
      await _dio.delete<void>(
        endpoint,
        options: Options(headers: _authHeaders(token)),
      );
    }
  }

  Future<void> togglePlayed(
    String url,
    String userId,
    String itemId,
    String token,
    bool isPlayed,
  ) async {
    final baseUrl = _normalizeUrl(url);
    final endpoint = '$baseUrl/Users/$userId/PlayedItems/$itemId';

    if (isPlayed) {
      await _dio.post<void>(
        endpoint,
        options: Options(headers: _authHeaders(token)),
      );
    } else {
      await _dio.delete<void>(
        endpoint,
        options: Options(headers: _authHeaders(token)),
      );
    }
  }

  Future<String?> getDownloadFilename(
    String url,
    String token,
    String itemId,
  ) async {
    final downloadUrl = getDownloadUrl(url, itemId, token);
    try {
      final response = await _dio.head<void>(
        downloadUrl,
        options: Options(headers: _authHeaders(token)),
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
    final baseUrl = _normalizeUrl(url);

    try {
      await _dio.post<void>(
        '$baseUrl/Sessions/Playing',
        data: {'ItemId': itemId},
        options: Options(headers: _authHeaders(token, json: true)),
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
    final baseUrl = _normalizeUrl(url);

    try {
      await _dio.post<void>(
        '$baseUrl/Sessions/Playing/Stopped',
        data: {'ItemId': itemId, 'PositionTicks': positionTicks},
        options: Options(headers: _authHeaders(token, json: true)),
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
    final baseUrl = _normalizeUrl(url);

    try {
      await _dio.post<void>(
        '$baseUrl/Sessions/Playing/Progress',
        data: {
          'ItemId': itemId,
          'PositionTicks': positionTicks,
          'IsPaused': isPaused,
        },
        options: Options(headers: _authHeaders(token, json: true)),
      );
    } catch (e) {
      // Silently fail
    }
  }

  Future<List<dynamic>> getGenres(
    String url,
    String userId,
    String token, {
    String? parentId,
  }) async {
    final baseUrl = _normalizeUrl(url);

    final Map<String, dynamic> queryParameters = <String, dynamic>{};
    if (parentId != null) {
      queryParameters['ParentId'] = parentId;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/Genres',
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders(token)),
      );
      return response.data?['Items'] as List<dynamic>? ?? [];
    } catch (e) {
      return [];
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
