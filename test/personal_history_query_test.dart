import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/history/history_list_query.dart';
import 'package:kazumi/pages/history/personal_history_query.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';
import 'modern_home_controller_test.dart' show item;

void main() {
  test(
    'mixed history uses true timestamps, namespaces, search and cache filter',
    () {
      final legacy = History(
        item(42),
        68,
        'DM84',
        DateTime(2026, 10, 16, 10),
        '/work',
        '第68集',
      );
      final sdk = SdkLibraryRecord(
        providerId: 'lumina',
        contentId: '42',
        title: 'SDK作品',
        lastWatch: SdkWatchProgress(
          episode: const SdkEpisode(number: 99, name: '第99集', code: 'mp4'),
          position: const Duration(seconds: 46),
          duration: const Duration(minutes: 20),
          updatedAt: DateTime(2026, 10, 16, 11),
        ),
      );
      final entries = groupPersonalHistory([legacy], [sdk]).single.entries;
      expect(entries.length, 2);
      expect(entries.first.sdk, sdk);
      expect(entries.first.key, isNot(entries.last.key));
      expect(
        groupPersonalHistory(
          [legacy],
          [sdk],
          query: 'Lumina',
        ).single.entries.single.sdk,
        sdk,
      );
      expect(
        groupPersonalHistory(
          [legacy],
          [sdk],
          source: HistorySourceFilter.offline,
        ),
        isEmpty,
      );
      expect(
        groupPersonalHistory(
          [legacy],
          [sdk],
          query: 'DM84',
        ).single.entries.single.history,
        legacy,
      );
    },
  );
}
