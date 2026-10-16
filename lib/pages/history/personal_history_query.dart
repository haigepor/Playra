import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';
import 'history_list_query.dart';

class PersonalHistoryEntry {
  PersonalHistoryEntry.legacy(this.history) : sdk = null;
  PersonalHistoryEntry.sdk(this.sdk) : history = null;
  final History? history;
  final SdkLibraryRecord? sdk;
  String get key => sdk == null ? 'legacy:${history!.key}' : 'sdk:${sdk!.key}';
  DateTime get watchedAt => sdk?.lastWatch?.updatedAt ?? history!.lastWatchTime;
}

class PersonalHistoryGroup {
  PersonalHistoryGroup(this.date, this.entries);
  final DateTime date;
  final List<PersonalHistoryEntry> entries;
  String label(DateTime now) {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);
    if (date == today) return '今天';
    if (date == DateTime(local.year, local.month, local.day - 1)) return '昨天';
    return '${date.year == local.year ? '' : '${date.year}年'}${date.month}月${date.day}日';
  }
}

List<PersonalHistoryGroup> groupPersonalHistory(
  Iterable<History> legacy,
  Iterable<SdkLibraryRecord> sdk, {
  String query = '',
  HistorySourceFilter source = HistorySourceFilter.all,
}) {
  final keyword = query.trim().toLowerCase();
  final entries = [
    for (final group in groupHistoryEntries(
      legacy,
      query: query,
      source: source,
    ))
      for (final entry in group.entries) PersonalHistoryEntry.legacy(entry),
    if (source != HistorySourceFilter.offline)
      for (final record in sdk)
        if (record.lastWatch != null &&
            (keyword.isEmpty ||
                '${record.title} ${record.sourceName}'.toLowerCase().contains(
                  keyword,
                )))
          PersonalHistoryEntry.sdk(record),
  ]..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
  final groups = <PersonalHistoryGroup>[];
  for (final entry in entries) {
    final local = entry.watchedAt.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    if (groups.isEmpty || groups.last.date != date)
      groups.add(PersonalHistoryGroup(date, []));
    groups.last.entries.add(entry);
  }
  return groups;
}
