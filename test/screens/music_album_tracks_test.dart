import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Music Album and Track Handling Tests', () {
    String formatDurationFromTicks(num? ticks) {
      if (ticks == null || ticks <= 0) return '--:--';
      final d = Duration(microseconds: (ticks / 10).round());
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final minutes = twoDigits(d.inMinutes.remainder(60));
      final seconds = twoDigits(d.inSeconds.remainder(60));
      if (d.inHours > 0) {
        return '${d.inHours}:$minutes:$seconds';
      }
      return '$minutes:$seconds';
    }

    test('formats duration under 1 hour as MM:SS', () {
      // 2706475000 ticks = 270.6475 seconds = 4 min 30 sec
      expect(formatDurationFromTicks(2706475000), equals('04:30'));

      // 650000000 ticks = 65 seconds = 1 min 05 sec
      expect(formatDurationFromTicks(650000000), equals('01:05'));

      // 50000000 ticks = 5 seconds = 00:05
      expect(formatDurationFromTicks(50000000), equals('00:05'));
    });

    test('formats duration of 1 hour or longer as H:MM:SS', () {
      // 36610000000 ticks = 3661 seconds = 1 hr 1 min 1 sec
      expect(formatDurationFromTicks(36610000000), equals('1:01:01'));

      // 72000000000 ticks = 7200 seconds = 2 hr 0 min 0 sec
      expect(formatDurationFromTicks(72000000000), equals('2:00:00'));
    });

    test('returns --:-- for null or zero ticks', () {
      expect(formatDurationFromTicks(null), equals('--:--'));
      expect(formatDurationFromTicks(0), equals('--:--'));
      expect(formatDurationFromTicks(-100), equals('--:--'));
    });

    test('sorts album tracks by disc number then track number', () {
      final tracks = <Map<String, dynamic>>[
        {
          'Name': 'Disc 2 Track 1',
          'ParentIndexNumber': 2,
          'IndexNumber': 1,
        },
        {
          'Name': 'Disc 1 Track 3',
          'ParentIndexNumber': 1,
          'IndexNumber': 3,
        },
        {
          'Name': 'Disc 1 Track 1',
          'ParentIndexNumber': 1,
          'IndexNumber': 1,
        },
        {
          'Name': 'Disc 1 Track 2',
          'ParentIndexNumber': 1,
          'IndexNumber': 2,
        },
      ];

      tracks.sort((a, b) {
        final discA = (a['ParentIndexNumber'] as num?)?.toInt() ?? 1;
        final discB = (b['ParentIndexNumber'] as num?)?.toInt() ?? 1;
        if (discA != discB) {
          return discA.compareTo(discB);
        }
        final trackA = (a['IndexNumber'] as num?)?.toInt() ?? 0;
        final trackB = (b['IndexNumber'] as num?)?.toInt() ?? 0;
        return trackA.compareTo(trackB);
      });

      expect(tracks[0]['Name'], equals('Disc 1 Track 1'));
      expect(tracks[1]['Name'], equals('Disc 1 Track 2'));
      expect(tracks[2]['Name'], equals('Disc 1 Track 3'));
      expect(tracks[3]['Name'], equals('Disc 2 Track 1'));
    });

    test('resolves track image item ID falling back to AlbumId', () {
      String resolveImageId(Map<String, dynamic> item) {
        final hasPrimaryImage = item['ImageTags'] is Map &&
            (item['ImageTags'] as Map)['Primary'] != null;
        return hasPrimaryImage
            ? item['Id'] as String
            : ((item['AlbumId'] ?? item['Id']) as String);
      }

      final trackWithImage = {
        'Id': 'track-123',
        'AlbumId': 'album-456',
        'ImageTags': {'Primary': 'tag-abc'},
      };
      expect(resolveImageId(trackWithImage), equals('track-123'));

      final trackWithoutImage = {
        'Id': 'track-789',
        'AlbumId': 'album-456',
        'ImageTags': <String, dynamic>{},
      };
      expect(resolveImageId(trackWithoutImage), equals('album-456'));
    });
  });
}
