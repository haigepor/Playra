import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/bundled_anime_migration.dart';

void main() {
  final legacy =
      (jsonDecode(
                File('assets/migrations/anifive-v1.json').readAsStringSync(),
              )['legacyRules']
              as List)
          .map((e) => Plugin.fromJson(Map<String, dynamic>.from(e)))
          .toList();
  final bundled =
      (jsonDecode(
                File('assets/migrations/kazumi-v1.json').readAsStringSync(),
              )['previousRules']
              as List)
          .map((p) => Plugin.fromJson(Map<String, dynamic>.from(p)))
          .toList();

  test('fresh install has four anime sources and migration is idempotent', () {
    expect(bundled, hasLength(4));
    final fresh = migrateBundledAnime([], legacy, bundled);
    expect(fresh, hasLength(4));
    expect(fresh.every((p) => p.type == 'anime' && p.usesApiSearch), isTrue);
    expect(
      migrateBundledAnime(fresh, legacy, bundled).map((p) => p.toJson()),
      fresh.map((p) => p.toJson()),
    );
  });
  test(
    'sixteen untouched rules become four with stable retained identities',
    () {
      final result = migrateBundledAnime(legacy, legacy, bundled);
      expect(result, hasLength(4));
      expect(result.map((p) => p.providerId).toSet(), {
        'dm84',
        'mxdm',
        'akianime',
        'moonci',
      });
      expect(
        result.every((p) => p.sourceConfig['managedBy'] == 'playra-anifive'),
        isTrue,
      );
    },
  );
  test('edited and custom rules survive including same-name collisions', () {
    final modified = Plugin.fromJson(
      legacy.firstWhere((p) => p.name == 'DM84').toJson(),
    )..searchName = '//my-custom';
    final custom = Plugin.fromJson(legacy.first.toJson())
      ..name = '我的规则'
      ..sourceId = 'my-source';
    final installed = [
      ...legacy.where((p) => p.name != 'DM84'),
      modified,
      custom,
    ];
    final result = migrateBundledAnime(installed, legacy, bundled);
    expect(result, hasLength(6));
    expect(result.contains(modified), isTrue);
    expect(result.contains(custom), isTrue);
    expect(result.map((p) => p.providerId).toSet(), hasLength(6));
    expect(result.map((p) => p.name).toSet(), hasLength(6));
    expect(migrateBundledAnime(result, legacy, bundled).length, 6);
  });
}
