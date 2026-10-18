import 'package:flutter_test/flutter_test.dart';
import 'package:finbuk/services/download_manager.dart';

void main() {
  group('DownloadTask Model Tests', () {
    test('initializes with default status and values', () {
      final task = DownloadTask(
        itemId: 'book-100',
        itemName: 'Dune',
        url: 'http://localhost:8096',
        token: 'token-xyz',
        fileExtension: '.epub',
      );

      expect(task.itemId, equals('book-100'));
      expect(task.itemName, equals('Dune'));
      expect(task.url, equals('http://localhost:8096'));
      expect(task.token, equals('token-xyz'));
      expect(task.fileExtension, equals('.epub'));
      expect(task.status, equals(DownloadStatus.notStarted));
      expect(task.progress, equals(0.0));
      expect(task.isActive, isFalse);
      expect(task.isComplete, isFalse);
      expect(task.hasFailed, isFalse);
    });

    test('isActive returns true only when downloading or paused', () {
      final task = DownloadTask(
        itemId: '1',
        itemName: 'Item 1',
        url: 'http://localhost',
        token: 'token',
        fileExtension: '.cbz',
      );

      task.status = DownloadStatus.downloading;
      expect(task.isActive, isTrue);

      task.status = DownloadStatus.paused;
      expect(task.isActive, isTrue);

      task.status = DownloadStatus.completed;
      expect(task.isActive, isFalse);

      task.status = DownloadStatus.failed;
      expect(task.isActive, isFalse);

      task.status = DownloadStatus.cancelled;
      expect(task.isActive, isFalse);
    });

    test('isComplete returns true only when completed', () {
      final task = DownloadTask(
        itemId: '2',
        itemName: 'Item 2',
        url: 'http://localhost',
        token: 'token',
        fileExtension: '.pdf',
      );

      task.status = DownloadStatus.completed;
      expect(task.isComplete, isTrue);

      task.status = DownloadStatus.downloading;
      expect(task.isComplete, isFalse);
    });

    test('hasFailed returns true when failed or cancelled', () {
      final task = DownloadTask(
        itemId: '3',
        itemName: 'Item 3',
        url: 'http://localhost',
        token: 'token',
        fileExtension: '.mp4',
      );

      task.status = DownloadStatus.failed;
      expect(task.hasFailed, isTrue);

      task.status = DownloadStatus.cancelled;
      expect(task.hasFailed, isTrue);

      task.status = DownloadStatus.downloading;
      expect(task.hasFailed, isFalse);
    });
  });

  group('DownloadManager Singleton Tests', () {
    late DownloadManager manager;

    setUp(() {
      manager = DownloadManager();
    });

    test('returns the identical singleton instance', () {
      final instance1 = DownloadManager();
      final instance2 = DownloadManager();
      expect(identical(instance1, instance2), isTrue);
    });

    test('returns default values for non-existent downloads', () {
      expect(manager.isDownloading('non-existent-id'), isFalse);
      expect(manager.getProgress('non-existent-id'), equals(0.0));
      expect(manager.getTask('non-existent-id'), isNull);
    });

    test('getDownloadStream provides a valid stream for an item', () {
      final stream = manager.getDownloadStream('stream-test-item');
      expect(stream, isNotNull);
      expect(stream.isBroadcast, isTrue);
    });

    test('download queries return valid collections', () {
      expect(manager.getActiveDownloads(), isA<List<DownloadTask>>());
      expect(manager.getQueuedDownloads(), isA<List<DownloadTask>>());
      expect(manager.getTotalDownloadCount(), isNonNegative);
    });
  });
}
