import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/bundled_anime_migration.dart';
import 'package:kazumi/services/source/source_sdk_group.dart';

void main() {
  List<Plugin> snapshot(String file, String key) =>
      (jsonDecode(File(file).readAsStringSync(encoding: utf8))[key] as List)
          .map((p) => Plugin.fromJson(Map<String, dynamic>.from(p)))
          .toList();
  final legacy = snapshot('assets/migrations/anifive-v1.json', 'legacyRules');
  final previous = snapshot(
    'assets/migrations/kazumi-v1.json',
    'previousRules',
  );
  final bundled = kazumiRuleOrigins.keys
      .map(
        (name) => Plugin.fromJson(
          jsonDecode(
            File('assets/plugins/$name.json').readAsStringSync(encoding: utf8),
          ),
        ),
      )
      .toList();
  List<Plugin> migrate(List<Plugin> installed) =>
      migrateBundledKazumi(installed, legacy, previous, bundled);

  test(
    'fresh, untouched legacy and four-source installs converge on the same sixteen rules',
    () {
      for (final installed in [<Plugin>[], legacy, previous]) {
        final result = migrate(installed);
        expect(result, hasLength(16));
        expect(result.every(isManagedKazumi), isTrue);
        expect(result.map((p) => p.providerId).toSet(), hasLength(16));
        expect(
          migrate(result).map((p) => p.toJson()),
          result.map((p) => p.toJson()),
        );
        for (final old in installed) {
          expect(
            result.any(
              (p) => p.providerId == old.providerId && p.name == old.name,
            ),
            isTrue,
          );
        }
      }
    },
  );

  test(
    'edited and same-name custom rules survive while official rules receive separate identities',
    () {
      final edited = Plugin.fromJson(legacy.first.toJson())
        ..searchName = '//custom';
      final changedSdk = Plugin.fromJson(previous.first.toJson())
        ..referer = 'https://custom.example/';
      final result = migrate([edited, changedSdk]);
      expect(result, hasLength(18));
      expect(result, containsAll([edited, changedSdk]));
      expect(result.map((p) => p.providerId).toSet(), hasLength(18));
      expect(result.map((p) => p.name.toLowerCase()).toSet(), hasLength(18));
      expect(
        migrate(result).map((p) => p.toJson()),
        result.map((p) => p.toJson()),
      );
    },
  );

  test(
    'renamed managed source retains its ID and joins Kazumi instead of AniFive',
    () {
      final old = Plugin.fromJson(previous.first.toJson())
        ..name = 'DM84 SDK'
        ..sourceId = 'my-dm84';
      final result = migrate([old]);
      final restored = result.singleWhere(
        (p) => p.providerId == old.providerId,
      );
      expect(restored.name, old.name);
      expect(playbackSdkId(restored), 'kazumi');
      expect(
        restored.searchApiConfig.request.url,
        isNot(contains('source-runtime')),
      );
    },
  );

  test('a display name or copied marker cannot group an unrelated site', () {
    final custom = Plugin.fromJson(bundled.first.toJson())
      ..baseUrl = 'https://other.example/';
    expect(isManagedKazumi(custom), isFalse);
    expect(playbackSdkId(custom), 'rule:${custom.providerId}');
  });
}
