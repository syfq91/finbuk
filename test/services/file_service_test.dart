import 'package:flutter_test/flutter_test.dart';
import 'package:finbuk/services/file_service.dart';

void main() {
  group('FileService.getExtension Tests', () {
    late FileService fileService;

    setUp(() {
      fileService = FileService();
    });

    test('detects book and comic extensions correctly', () {
      expect(fileService.getExtension({'Container': 'epub'}), equals('.epub'));
      expect(
        fileService.getExtension({'Path': '/books/novel.epub'}),
        equals('.epub'),
      );
      expect(fileService.getExtension({'Container': 'cbz'}), equals('.cbz'));
      expect(
        fileService.getExtension({'Path': '/comics/issue1.cbz'}),
        equals('.cbz'),
      );
      expect(fileService.getExtension({'Container': 'cbr'}), equals('.cbr'));
      expect(
        fileService.getExtension({'Path': '/comics/issue2.cbr'}),
        equals('.cbr'),
      );
      expect(fileService.getExtension({'Container': 'pdf'}), equals('.pdf'));
      expect(
        fileService.getExtension({'Path': '/documents/manual.pdf'}),
        equals('.pdf'),
      );
    });

    test('detects video containers correctly', () {
      expect(fileService.getExtension({'Container': 'mp4'}), equals('.mp4'));
      expect(fileService.getExtension({'Container': 'm4v'}), equals('.mp4'));
      expect(
        fileService.getExtension({'Path': '/movies/clip.m4v'}),
        equals('.mp4'),
      );
      expect(fileService.getExtension({'Container': 'mkv'}), equals('.mkv'));
      expect(
        fileService.getExtension({'Container': 'matroska'}),
        equals('.mkv'),
      );
      expect(fileService.getExtension({'Container': 'webm'}), equals('.webm'));
      expect(fileService.getExtension({'Container': 'avi'}), equals('.avi'));
      expect(fileService.getExtension({'Container': 'mov'}), equals('.mov'));
      expect(fileService.getExtension({'Container': 'flv'}), equals('.flv'));
      expect(fileService.getExtension({'Container': '3gp'}), equals('.3gp'));
      expect(fileService.getExtension({'Container': 'ts'}), equals('.ts'));
    });

    test('detects audio containers correctly', () {
      expect(fileService.getExtension({'Container': 'mp3'}), equals('.mp3'));
      expect(fileService.getExtension({'Container': 'flac'}), equals('.flac'));
      expect(fileService.getExtension({'Container': 'm4b'}), equals('.m4b'));
      expect(fileService.getExtension({'Container': 'm4a'}), equals('.m4a'));
      expect(fileService.getExtension({'Container': 'aac'}), equals('.aac'));
      expect(fileService.getExtension({'Container': 'ogg'}), equals('.ogg'));
      expect(fileService.getExtension({'Container': 'oga'}), equals('.ogg'));
      expect(fileService.getExtension({'Container': 'opus'}), equals('.opus'));
      expect(fileService.getExtension({'Container': 'wav'}), equals('.wav'));
      expect(fileService.getExtension({'Container': 'wma'}), equals('.wma'));
    });

    test('detects extension from nested MediaSources if top-level empty', () {
      final itemWithNestedSource = <String, dynamic>{
        'Container': '',
        'Path': '',
        'MediaSources': <Map<String, dynamic>>[
          <String, dynamic>{'Container': 'flac', 'Path': '/audio/track01.flac'},
        ],
      };
      expect(fileService.getExtension(itemWithNestedSource), equals('.flac'));
    });

    test('falls back to file path extension when container is absent', () {
      final itemWithPathOnly = <String, dynamic>{
        'Path': '/storage/emulated/0/Books/guide.epub',
      };
      expect(fileService.getExtension(itemWithPathOnly), equals('.epub'));
    });

    test('returns empty string for missing or unrecognized format', () {
      expect(fileService.getExtension(<String, dynamic>{}), equals(''));
      expect(
        fileService.getExtension(<String, dynamic>{'Container': 'unknown_xyz'}),
        equals(''),
      );
    });
  });
}
