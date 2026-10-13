import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/content_source_controller.dart';

class DirectoryProvider extends ContentSearchProvider {
  DirectoryProvider(this.id, this.result);
  @override
  final String id;
  @override
  String get name => id;
  @override
  Set<ContentGroup> get groups => {ContentGroup.anime};
  @override
  bool get canPlay => true;
  final Completer<List<ContentLine>> result;
  @override
  Future<ContentSearchPage> search(
    ContentQuery q,
    int page,
    CancelToken c,
  ) async => const ContentSearchPage([], hasMore: false);
  @override
  Future<List<ContentLine>> lines(ContentHit hit, CancelToken c) =>
      result.future;
}

void main() {
  test(
    'a fast directory becomes selectable without waiting for slow directories',
    () async {
      final slow = Completer<List<ContentLine>>(),
          fast = Completer<List<ContentLine>>();
      final session = ContentSearchSession([]);
      addTearDown(session.dispose);
      final work = ContentWork(
        const ContentHit(
          providerId: 'a',
          contentId: '1',
          title: '甲',
          group: ContentGroup.anime,
        ),
      );
      final controller = ContentSourceController([
        DirectoryProvider('a', slow),
        DirectoryProvider('b', fast),
      ]);
      addTearDown(controller.dispose);
      controller.add(work.primary);
      controller.add(
        const ContentHit(
          providerId: 'b',
          contentId: '2',
          title: '甲',
          group: ContentGroup.anime,
        ),
      );
      final ready = Completer<void>();
      controller.addListener(() {
        if (controller.bindings.any(
              (b) => b.status == ContentDirectoryStatus.ready,
            ) &&
            !ready.isCompleted) {
          ready.complete();
        }
      });
      fast.complete(const [
        ContentLine('line', '线路', [ContentEpisode('ep', '第1集')]),
      ]);
      await ready.future;
      expect(controller.bindings.first.status, ContentDirectoryStatus.pending);
      expect(controller.bindings.last.status, ContentDirectoryStatus.ready);
      slow.complete(const []);
    },
  );
  test(
    'disposing directory validation drops late results and cancels its lifecycle',
    () async {
      final pending = Completer<List<ContentLine>>();
      final controller = ContentSourceController([
        DirectoryProvider('a', pending),
      ]);
      controller.add(
        const ContentHit(
          providerId: 'a',
          contentId: '1',
          title: '甲',
          group: ContentGroup.anime,
        ),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.dispose();
      final before = notifications;
      pending.complete(const [
        ContentLine('line', '线路', [ContentEpisode('ep', '第1集')]),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, before);
    },
  );
}
