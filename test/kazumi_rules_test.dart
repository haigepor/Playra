import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/source/source_sdk_group.dart';

void main() {
  final rules = Directory('assets/plugins')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map(
        (f) => Plugin.fromJson(jsonDecode(f.readAsStringSync(encoding: utf8))),
      )
      .toList();

  test(
    'the original sixteen official rules replace the four runtime adapters',
    () {
      expect(rules.map((p) => p.name).toSet(), {
        '7sefun',
        'aafun',
        'AGE',
        'akianime',
        'baimao',
        'dalvdm',
        'DM84',
        'ezdmw',
        'giriGiriLove',
        'mgnacg',
        'moonci',
        'mutefun',
        'MXdm',
        'sorani',
        'xfdmneo',
        'xfdmnext',
      });
      expect(rules.every((p) => !p.requiresNewerClient), isTrue);
      expect(
        rules.every(
          (p) => !p.searchApiConfig.request.url.contains(
            'source-runtime.playra.invalid',
          ),
        ),
        isTrue,
      );
      final groups = PlaybackSourceGroup.fromPlugins(rules);
      expect(groups, hasLength(1));
      expect(groups.single.id, 'kazumi');
      expect(groups.single.name, '动漫 · Kazumi');
    },
  );

  test(
    'official API 9 search templates survive persistence and build detail URLs',
    () {
      final config = ApiSearchConfig.fromJson({
        'listPath': r'$.list[*]',
        'namePath': r'$.name',
        'sourcePath': r'$.id',
        'sourceTemplate': 'https://ani.girigirilove.com/GV@source/',
      });
      final restored = ApiSearchConfig.fromJson(config.toJson());
      final result = const ApiRuleStrategy().parseSearch(
        jsonEncode({
          'list': [
            {'name': '测试动漫', 'id': 'a/b ?'},
          ],
        }),
        restored,
      );
      expect(
        result.items.single.src,
        'https://ani.girigirilove.com/GVa%2Fb%20%3F/',
      );
    },
  );

  test(
    'invalid detail templates fail explicitly instead of becoming a wrong source',
    () {
      final config = ApiSearchConfig.fromJson({
        'sourceTemplate': 'https://example.com/fixed',
      });
      expect(
        () => const ApiRuleStrategy().validateSearchConfig(config),
        throwsA(isA<ApiRuleFormatException>()),
      );
    },
  );
}
