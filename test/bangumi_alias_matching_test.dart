import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/source/source_candidates.dart';

BangumiItem parse(Map<String, dynamic> extra) => BangumiItem.fromJson({
  'id': 975,
  'type': 2,
  'name': 'ONE PIECE',
  'name_cn': '航海王',
  'rating': <String, dynamic>{},
  'images': <String, String>{},
  ...extra,
});

void main() {
  test('mirror Wiki aliases are usable by actual source matching', () {
    final work = parse({
      'info':
          '{{Infobox animanga/TVAnime\r\n|中文名= 航海王\r\n|别名={\r\n[ワンピース]\r\n[海贼王]\r\n}\r\n|话数= 1155\r\n|原作= 尾田栄一郎\r\n}}',
    });
    expect(work.alias, ['ワンピース', '海贼王']);
    expect(SourceCandidates().matches(work, '海贼王'), isTrue);
    for (final title in ['海贼王女', '海贼王剧场版Z', '海贼王 鱼人岛篇特别编辑版', '航海王总集篇']) {
      expect(SourceCandidates().matches(work, title), isFalse, reason: title);
    }
  });

  test(
    'structured v0 and p1 aliases and Wiki values are merged and deduplicated',
    () {
      final work = parse({
        'infobox': [
          {
            'key': '别名',
            'value': [
              {'v': '海贼王'},
              {'v': ' ONE PIECE '},
            ],
          },
          {
            'key': '别名',
            'values': ['ワンピース'],
          },
        ],
        'info': '{{Infobox\n|别名= 海贼王\n|导演= 不属于别名\n}}',
      });
      expect(work.alias, ['海贼王', 'ONE PIECE', 'ワンピース']);
    },
  );

  test(
    'a labeled Wiki alias uses its value without leaking surrounding fields',
    () {
      final work = parse({
        'info':
            '{{Infobox\n|别名={\n[简体中文|海贼王]\n[日文|ワンピース]\n}\n|其他={\n[海贼王女]\n}\n}}',
      });
      expect(work.alias, ['海贼王', 'ワンピース']);
      expect(parse({'info': '{{Infobox\n|其他= 海贼王\n}}'}).alias, isEmpty);
      expect(parse({'summary': '也称海贼王'}).alias, isEmpty);
    },
  );
}
