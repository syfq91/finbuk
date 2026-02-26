import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'file_service.dart';

/// Background download status for an item
enum DownloadStatus {
  notStarted,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// Represents the current state of a download
class DownloadTask {
  final String itemId;
  final String itemName;
  final String url;
  final String token;
  final String fileExtension;
  final String? customPath;
  final String? fileName;

  DownloadStatus status;
  double progress;
  String? error;
  CancelToken? cancelToken;
  File? file;

  DownloadTask({
    required this.itemId,
    required this.itemName,
    required this.url,
    required this.token,
    required this.fileExtension,
    this.customPath,
    this.fileName,
    this.status = DownloadStatus.notStarted,
    this.progress = 0.0,
    this.error,
  });

  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.paused;
  bool get isComplete => status == DownloadStatus.completed;
  bool get hasFailed =>
      status == DownloadStatus.failed || status == DownloadStatus.cancelled;
}

/// A singleton service that manages background downloads independently of widget lifecycle
class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  static const int _concurrentDownloads = 3;

  factory DownloadManager() => _instance;
  DownloadManager._internal()
    : _globalProgressController =
          StreamController<Map<String, double>>.broadcast();

  final FileService _fileService = FileService();

  // Active downloads map: itemId -> DownloadTask
  final Map<String, DownloadTask> _activeDownloads = {};

  // Stream controllers for each download item
  final Map<String, StreamController<DownloadTask>> _streamControllers = {};

  // Queue for pending downloads
  final List<DownloadTask> _downloadQueue = [];

  // Global progress controller for overall download progress
  final StreamController<Map<String, double>> _globalProgressController;

  /// Get the current download task for an item
  DownloadTask? getTask(String itemId) => _activeDownloads[itemId];

  /// Check if an item is currently downloading
  bool isDownloading(String itemId) {
    final task = _activeDownloads[itemId];
    return task?.status == DownloadStatus.downloading;
  }

  /// Get progress for a specific item (0.0 to 1.0)
  double getProgress(String itemId) {
    return _activeDownloads[itemId]?.progress ?? 0.0;
  }

  /// Start a background download for a book
  Future<void> startDownload({
    required String itemId,
    required String itemName,
    required String url,
    required String token,
    required String extension,
    String? customPath,
    String? fileName,
    bool enqueueIfBusy = true,
  }) async {
    // If already downloading, return
    if (_activeDownloads.containsKey(itemId) &&
        _activeDownloads[itemId]!.isActive) {
      debugPrint('Download already in progress for $itemId');
      return;
    }

    // If already completed, don't restart
    if (_activeDownloads.containsKey(itemId) &&
        _activeDownloads[itemId]!.isComplete) {
      debugPrint('Download already completed for $itemId');
      return;
    }

    // Create new task
    final task = DownloadTask(
      itemId: itemId,
      itemName: itemName,
      url: url,
      token: token,
      fileExtension: extension,
      customPath: customPath,
      fileName: fileName,
      status: DownloadStatus.downloading,
    );
    _activeDownloads[itemId] = task;

    // Ensure we have a stream controller for this item
    _ensureStreamController(itemId);

    // Check current active download count
    final activeCount = _activeDownloads.values
        .where((t) => t.status == DownloadStatus.downloading)
        .length;

    if (activeCount >= _concurrentDownloads && enqueueIfBusy) {
      // Add to queue instead of starting immediately
      _downloadQueue.add(task);
      task.status = DownloadStatus.paused;
      _notifyListeners(itemId);
      debugPrint(
        'Download for $itemId queued (max concurrent: $_concurrentDownloads)',
      );
      return;
    }

    // Start the actual download
    _startDownloadTask(task);
  }

  /// Cancel a specific download
  Future<void> cancelDownload(String itemId) async {
    final task = _activeDownloads[itemId];
    if (task == null) return;

    // Cancel the Dio request
    task.cancelToken?.cancel('cancelled by user');

    task.status = DownloadStatus.cancelled;

    // Notify listeners before removal
    _notifyListeners(itemId);

    // Remove from active downloads
    _activeDownloads.remove(itemId);

    // Remove from queue if present
    _downloadQueue.removeWhere((t) => t.itemId == itemId);

    // Clean up partial file if exists
    try {
      final file = await _fileService.getBookFile(
        itemId,
        task.customPath,
        task.fileExtension,
      );
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error cleaning up cancelled download: $e');
    }

    // Try to start next queued download
    _processQueue();
  }

  /// Pause a download
  Future<void> pauseDownload(String itemId) async {
    final task = _activeDownloads[itemId];
    if (task == null || task.cancelToken == null) return;

    task.cancelToken?.cancel('paused by user');
    task.cancelToken = null;
    task.status = DownloadStatus.paused;
    _notifyListeners(itemId);

    _processQueue();
  }

  /// Get stream for a specific item's download progress
  Stream<DownloadTask> getDownloadStream(String itemId) {
    _ensureStreamController(itemId);
    return _streamControllers[itemId]!.stream;
  }

  /// Ensure a stream controller exists for the given item
  void _ensureStreamController(String itemId) {
    if (!_streamControllers.containsKey(itemId)) {
      _streamControllers[itemId] = StreamController<DownloadTask>.broadcast(
        onListen: () {
          debugPrint('Listener attached for download: $itemId');
          // Emit current task state when someone starts listening
          if (_activeDownloads.containsKey(itemId)) {
            _streamControllers[itemId]?.add(_activeDownloads[itemId]!);
          }
        },
        onCancel: () {
          debugPrint('Listener detached from download: $itemId');
          // Don't close controller immediately - might have multiple listeners
          // Let _activeDownloads cleanup handle it when download finishes
        },
      );
    }
  }

  /// Start the actual download task
  void _startDownloadTask(DownloadTask task) async {
    task.cancelToken = CancelToken();
    task.status = DownloadStatus.downloading;
    _notifyListeners(task.itemId);

    try {
      final file = await _fileService.downloadAndSaveBook(
        task.url,
        task.token,
        task.itemId,
        task.customPath,
        task.fileExtension,
        (received, total) {
          if (total > 0) {
            task.progress = received / total;
            _notifyListeners(task.itemId);
          }
        },
        task.cancelToken,
        fileName: task.fileName,
      );

      // Download completed successfully
      task.file = file;
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      _notifyListeners(task.itemId);
      _globalProgressController.add({task.itemId: 1.0});
      _activeDownloads.remove(task.itemId);

      // Clean up stream controller after a delay (to allow UI to get final state)
      _scheduleStreamCleanup(task.itemId);

      // Process queued downloads
      _processQueue();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (e.message?.contains('paused') == true) {
          task.status = DownloadStatus.paused;
        } else {
          task.status = DownloadStatus.cancelled;
        }
      } else {
        task.status = DownloadStatus.failed;
        task.error = e.message;
      }
      _notifyListeners(task.itemId);
      if (task.status == DownloadStatus.cancelled ||
          task.status == DownloadStatus.failed) {
        _activeDownloads.remove(task.itemId);
      }
      _processQueue();
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      _notifyListeners(task.itemId);
      _activeDownloads.remove(task.itemId);
      _processQueue();
    }
  }

  /// Process the download queue
  void _processQueue() {
    // Find next queued item that can be started
    for (final task in _downloadQueue.toList()) {
      final activeCount = _activeDownloads.values
          .where((t) => t.status == DownloadStatus.downloading)
          .length;

      if (activeCount < _concurrentDownloads) {
        _downloadQueue.remove(task);
        task.status = DownloadStatus.downloading;
        _activeDownloads[task.itemId] = task;
        _startDownloadTask(task);
      } else {
        break;
      }
    }
  }

  /// Notify all listeners for a specific item
  void _notifyListeners(String itemId) {
    final task = _activeDownloads[itemId];
    if (task != null && _streamControllers.containsKey(itemId)) {
      _streamControllers[itemId]?.add(task);
    }
  }

  /// Schedule cleanup of stream controller after download finishes
  void _scheduleStreamCleanup(String itemId) {
    // Keep the controller alive for a bit to allow UI to read final state
    Future.delayed(const Duration(seconds: 5), () {
      if (!_activeDownloads.containsKey(itemId)) {
        _closeStreamController(itemId);
      }
    });
  }

  /// Close and remove stream controller
  void _closeStreamController(String itemId) {
    final controller = _streamControllers[itemId];
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
    _streamControllers.remove(itemId);
  }

  /// Get all active downloads
  List<DownloadTask> getActiveDownloads() {
    return _activeDownloads.values.toList();
  }

  /// Get all queued downloads
  List<DownloadTask> getQueuedDownloads() {
    return List.unmodifiable(_downloadQueue);
  }

  /// Get total active + queued count
  int getTotalPendingDownloads() {
    return _activeDownloads.length + _downloadQueue.length;
  }

  /// Check if there are any active downloads
  bool get hasActiveDownloads => _activeDownloads.isNotEmpty;

  /// Check if there are any queued downloads
  bool get hasQueuedDownloads => _downloadQueue.isNotEmpty;

  /// Cleanup - call on app shutdown
  void dispose() {
    // Cancel all active downloads
    for (final task in _activeDownloads.values) {
      task.cancelToken?.cancel('service disposed');
    }
    _activeDownloads.clear();
    _downloadQueue.clear();

    // Close all stream controllers
    for (final controller in _streamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _streamControllers.clear();

    _globalProgressController.close();
  }
}
