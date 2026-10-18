import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/anime_playback_quality.dart';

void main() {
  test(
    'automatic selection requires real 1080p or higher decoded dimensions',
    () {
      expect(automaticAnimeQualityError(width: 1920, height: 1080), isNull);
      expect(automaticAnimeQualityError(width: 3840, height: 2160), isNull);
      expect(
        automaticAnimeQualityError(width: 1280, height: 720),
        'QUALITY_BELOW_MINIMUM',
      );
      expect(
        automaticAnimeQualityError(width: 1920, height: 800),
        'QUALITY_BELOW_MINIMUM',
      );
    },
  );
  test(
    'missing dimensions cannot be promoted by source names or guessed quality',
    () {
      expect(automaticAnimeQualityError(), 'QUALITY_UNCONFIRMED');
      expect(automaticAnimeQualityError(width: 1920), 'QUALITY_UNCONFIRMED');
      expect(
        automaticAnimeQualityError(width: 0, height: 2160),
        'QUALITY_UNCONFIRMED',
      );
    },
  );
}
