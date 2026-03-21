import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../services/jellyfin_service.dart';
import '../services/permission_service.dart';
import '../services/database_service.dart';
import '../models/item.dart';

class FileService {
  final JellyfinService _jellyfinService = JellyfinService();
  final PermissionService _permissionService = PermissionService();
  final DatabaseService _dbService = DatabaseService();

  Future<String> getEffectiveDownloadPath(String? customPath) async {
    if (customPath != null && customPath.isNotEmpty) {
      return customPath;
    }
    throw Exception(
      'Download path is not set. Please set a download location in Settings.',
    );
  }

  Future<File?> getBookFile(
    String itemId,
    String? customPath,
    String extension,
  ) async {
    final basePath = await getEffectiveDownloadPath(customPath);

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
  Future<File?> findDownloadedFileByItemId(
    String itemId,
    String? customPath,
  ) async {
    final basePath = await getEffectiveDownloadPath(customPath);

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
      debugPrint('Failed to scan directory for item $itemId in path $basePath: $e');
      return null;
    }
    return null;
  }

  Future<File> downloadAndSaveBook(
    String url,
    String token,
    String itemId,
    String? customPath,
    String extension,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken, {
    String? fileName,
  }) async {
    final basePath = await getEffectiveDownloadPath(customPath);

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
      if (customPath != null && customPath.isNotEmpty) {
        final hasPermission = await _permissionService
            .requestStoragePermission();
        if (!hasPermission) {
          throw Exception('Storage permission required for custom path');
        }
      }
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
          debugPrint('Failed to delete partial file after cancellation at $filePath: $e');
        }
      }
      rethrow;
    }
  }

  String getExtension(Map<String, dynamic> item) {
    final container = (item['Container'] ?? '').toString().toLowerCase();
    final path = (item['Path'] ?? '').toString().toLowerCase();

    if (container.contains('pdf') || path.endsWith('.pdf')) return '.pdf';
    if (container.contains('cbz') || path.endsWith('.cbz')) return '.cbz';
    if (container.contains('cbr') || path.endsWith('.cbr')) return '.cbr';

    return '';
  }

  Future<List<Item>> getDownloadedItems(String? customPath) async {
    final basePath = await getEffectiveDownloadPath(customPath);
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

  Future<void> deleteDownloadedItem(
    String itemId,
    String? customPath,
    String? extension,
  ) async {
    final basePath = await getEffectiveDownloadPath(customPath);

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
