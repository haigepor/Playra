import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/source/source_sdk_group.dart';

void main() {
  test('retired rules are absent from the application bundle', () {
    final directory = Directory('assets/plugins');
    final files = directory.existsSync()
        ? directory.listSync().whereType<File>()
        : <File>[];
    expect(files.where((file) => file.path.endsWith('.json')), isEmpty);
    expect(PlaybackSourceGroup.fromPlugins([]), isEmpty);
  });

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
