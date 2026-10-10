import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_catalog.dart';

void main() {
  test(
    'airing badges retain calendar day and read a single explicit airtime',
    () {
      final airing = const HomeAiring(6).withDetail({
        'airtime': {'date': '2026-10-05'},
        'infobox': [
          {
            'key': '放送时间',
            'values': [
              {'v': '每周六 21:05'},
            ],
          },
        ],
      });
      expect(airing.label, '周六 | 21:05');
    },
  );
  test('missing, conflicting and 24+ times do not invent a clock', () {
    for (final values in [
      [''],
      ['25:30'],
      ['21:05', '22:05'],
    ]) {
      final airing = const HomeAiring(6).withDetail({
        'infobox': [
          {'key': '放送星期', 'value': values},
        ],
      });
      expect(airing.label, '周六 | 待定');
    }
    expect(const HomeAiring(0).label, '时间待定');
  });
  test('unrelated production times are not treated as broadcast times', () {
    final airing = const HomeAiring(1).withDetail({
      'infobox': [
        {
          'key': '其他',
          'values': [
            {'v': '21:05'},
          ],
        },
      ],
    });
    expect(airing.time, isNull);
  });
}
