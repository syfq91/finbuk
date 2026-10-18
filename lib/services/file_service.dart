import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../services/jellyfin_service.dart';
import '../services/database_service.dart';
import '../models/item.dart';
import 'package:path_provider/path_provider.dart';

class FileService {
  final JellyfinService _jellyfinService = JellyfinService();
  final DatabaseService _dbService = DatabaseService();

  Future<String> getEffectiveDownloadPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File?> getBookFile(String itemId, String extension) async {
    final basePath = await getEffectiveDownloadPath();

    // Check downloads DB for a record
    final download = await _dbService.getDownload(itemId);
    if (download != null) {
      final filename = download['filename'] as String;
      final filePath = p.join(basePath, filename);
      final file = File(filePath);
      if (await file.exists()) {
        return file;
      } else {
        await _dbService.deleteDownload(itemId);
      }
    }

    // Fallback to old pattern for backwards compatibility
    final filePath = p.join(basePath, '$itemId$extension');
    final file = File(filePath);
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Find a downloaded file by itemId, regardless of extension.
  /// Scans the download directory for a file whose basename (without extension)
  /// matches the given itemId. This handles cases where the stored file extension
  /// differs from the current item metadata extension.
  Future<File?> findDownloadedFileByItemId(String itemId) async {
    final basePath = await getEffectiveDownloadPath();

    // Check downloads DB first
    final download = await _dbService.getDownload(itemId);
    if (download != null) {
      final filename = download['filename'] as String;
      final filePath = p.join(basePath, filename);
      final file = File(filePath);
      if (await file.exists()) {
        return file;
      } else {
        await _dbService.deleteDownload(itemId);
      }
    }

    // Fallback: scan directory for itemId pattern (legacy)
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      return null;
    }
    try {
      final files = await dir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      for (var file in files) {
        if (p.basenameWithoutExtension(file.path) == itemId) {
          return file;
        }
      }
    } catch (e) {
      debugPrint(
        'Failed to scan directory for item $itemId in path $basePath: $e',
      );
      return null;
    }
    return null;
  }

  Future<File> downloadAndSaveBook(
    String url,
    String token,
    String itemId,
    String extension,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken, {
    String? fileName,
  }) async {
    final basePath = await getEffectiveDownloadPath();

    String effectiveFileName;
    if (fileName != null && fileName.isNotEmpty) {
      effectiveFileName = fileName;
    } else {
      effectiveFileName =
          await _jellyfinService.getDownloadFilename(url, token, itemId) ??
          itemId + extension;
    }

    // Sanitize filename
    effectiveFileName = _sanitizeFilename(effectiveFileName);

    // Ensure extension present
    if (p.extension(effectiveFileName).isEmpty && extension.isNotEmpty) {
      effectiveFileName = '$effectiveFileName$extension';
    }

    // Ensure uniqueness
    final uniqueFileName = await _ensureUniqueFilename(
      basePath,
      effectiveFileName,
    );
    final filePath = p.join(basePath, uniqueFileName);
    final file = File(filePath);

    // Ensure directory exists
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    try {
      await _jellyfinService.downloadItemToPath(
        url,
        token,
        itemId,
        filePath,
        onProgress,
        cancelToken,
      );

      // Save download record with the actual filename
      await _dbService.saveDownload(itemId, uniqueFileName);

      return file;
    } on DioException catch (_) {
      // If cancelled, remove partial file
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint(
            'Failed to delete partial file after cancellation at $filePath: $e',
          );
        }
      }
      rethrow;
    }
  }

  String getExtension(Map<String, dynamic> item) {
    String container = (item['Container'] ?? '').toString().toLowerCase();
    String path = (item['Path'] ?? '').toString().toLowerCase();

    // Check nested MediaSources if container or path is empty
    if (container.isEmpty || path.isEmpty) {
      final mediaSources = item['MediaSources'] as List<dynamic>?;
      if (mediaSources != null && mediaSources.isNotEmpty) {
        final firstSource = mediaSources.first;
        if (firstSource is Map<String, dynamic>) {
          if (container.isEmpty) {
            container =
                (firstSource['Container'] ?? '').toString().toLowerCase();
          }
          if (path.isEmpty) {
            path = (firstSource['Path'] ?? '').toString().toLowerCase();
          }
        }
      }
    }

    // Books & Comics
    if (container.contains('epub') || path.endsWith('.epub')) return '.epub';
    if (container.contains('cbz') || path.endsWith('.cbz')) return '.cbz';
    if (container.contains('cbr') || path.endsWith('.cbr')) return '.cbr';
    if (container.contains('pdf') || path.endsWith('.pdf')) return '.pdf';

    // Video Formats
    if (container.contains('mp4') ||
        path.endsWith('.mp4') ||
        container.contains('m4v') ||
        path.endsWith('.m4v')) {
      return '.mp4';
    }
    if (container.contains('mkv') ||
        container.contains('matroska') ||
        path.endsWith('.mkv')) {
      return '.mkv';
    }
    if (container.contains('webm') || path.endsWith('.webm')) return '.webm';
    if (container.contains('avi') || path.endsWith('.avi')) return '.avi';
    if (container.contains('mov') || path.endsWith('.mov')) return '.mov';
    if (container.contains('flv') || path.endsWith('.flv')) return '.flv';
    if (container.contains('3gp') || path.endsWith('.3gp')) return '.3gp';
    if (container.contains('ts') || path.endsWith('.ts')) return '.ts';

    // Audio Formats
    if (container.contains('mp3') || path.endsWith('.mp3')) return '.mp3';
    if (container.contains('flac') || path.endsWith('.flac')) return '.flac';
    if (container.contains('m4b') || path.endsWith('.m4b')) return '.m4b';
    if (container.contains('m4a') || path.endsWith('.m4a')) return '.m4a';
    if (container.contains('aac') || path.endsWith('.aac')) return '.aac';
    if (container.contains('ogg') ||
        container.contains('oga') ||
        path.endsWith('.ogg') ||
        path.endsWith('.oga')) {
      return '.ogg';
    }
    if (container.contains('opus') || path.endsWith('.opus')) return '.opus';
    if (container.contains('wav') || path.endsWith('.wav')) return '.wav';
    if (container.contains('wma') || path.endsWith('.wma')) return '.wma';

    // Fallback: extract extension directly from Path if available
    if (path.isNotEmpty) {
      final ext = p.extension(path);
      if (ext.isNotEmpty && ext.length <= 5) {
        return ext;
      }
    }

    return '';
  }

  Future<List<Item>> getDownloadedItems() async {
    final basePath = await getEffectiveDownloadPath();
    final List<Item> downloadedItems = [];

    // Get all download records from DB
    final downloads = await _dbService.getAllDownloads();

    for (var rec in downloads) {
      final itemId = rec['itemId'] as String;
      final filename = rec['filename'] as String;
      final filePath = p.join(basePath, filename);
      if (await File(filePath).exists()) {
        final item = await _dbService.getItemById(itemId);
        if (item != null) {
          downloadedItems.add(item);
        }
      } else {
        // Clean up missing file
        await _dbService.deleteDownload(itemId);
      }
    }

    // Also include legacy downloads (files named by itemId) that aren't in DB.
    // This helps transition. We'll scan but exclude those already in DB.
    final dir = Directory(basePath);
    if (await dir.exists()) {
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final Set<String> knownItemIds = downloads
          .map((r) => r['itemId'] as String)
          .toSet();
      for (var file in files) {
        final baseName = p.basenameWithoutExtension(file.path);
        if (!knownItemIds.contains(baseName)) {
          final item = await _dbService.getItemById(baseName);
          if (item != null) {
            downloadedItems.add(item);
            // Optionally, we could create a download record for it now
            await _dbService.saveDownload(baseName, p.basename(file.path));
          }
        }
      }
    }

    return downloadedItems;
  }

  Future<void> deleteDownloadedItem(String itemId, String? extension) async {
    final basePath = await getEffectiveDownloadPath();

    // Check if we have a download record
    final download = await _dbService.getDownload(itemId);
    String? filename;
    if (download != null) {
      filename = download['filename'] as String?;
    }

    if (filename != null) {
      final filePath = p.join(basePath, filename);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      await _dbService.deleteDownload(itemId);
    } else {
      // Fallback to old pattern if extension provided
      if (extension != null && extension.isNotEmpty) {
        final filePath = p.join(basePath, '$itemId$extension');
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  String _sanitizeFilename(String filename) {
    var sanitized = filename.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    sanitized = sanitized.trim();
    sanitized = sanitized.replaceAll(RegExp(r'^\.+'), '');
    sanitized = sanitized.replaceAll(RegExp(r'\.+$'), '');
    if (sanitized.isEmpty) {
      sanitized = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return sanitized;
  }

  Future<String> _ensureUniqueFilename(String basePath, String filename) async {
    String finalName = filename;
    int counter = 1;
    final ext = p.extension(filename);
    final nameWithoutExt = p.basenameWithoutExtension(filename);
    while (await File(p.join(basePath, finalName)).exists()) {
      finalName = '$nameWithoutExt ($counter)$ext';
      counter++;
    }
    return finalName;
  }
}
