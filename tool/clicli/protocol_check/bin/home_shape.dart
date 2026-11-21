// Focused dump: one banner + module metadata (no item payloads).
//
//   cd tool/clicli/protocol_check && dart run bin/home_shape.dart
import 'dart:convert';
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_client.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_config.dart';

Future<void> main() async {
  final client = CliCliClient();
  const p = CliCliConfig.apiPrefix;

  final banners = await client.callData('$p/banner/list', {'categoryId': ''});
  final list = (banners['banners'] as List?) ?? const [];
  stdout.writeln('banners=${list.length}');
  stdout.writeln('linkTypes=${list.map((b) => (b as Map)['linkType']).toSet()}');
  if (list.isNotEmpty) {
    stdout.writeln(jsonEncode(list.first));
  }
  for (final banner in list.take(5)) {
    final map = banner as Map;
    stdout.writeln('  img=${map['imageUrl']}');
  }

  final modules = await client.callData('$p/video/modules', {
    'categoryId': '',
    'pageIndex': 1,
    'pageSize': 20,
  });
  final mods = (modules['list'] as List?) ?? const [];
  for (final mod in mods) {
    final map = Map<String, dynamic>.from(mod as Map);
    final items = map.remove('items');
    stdout.writeln('--- module ${map['name']} (${map['id']})');
    stdout.writeln(jsonEncode(map));
    stdout.writeln('items=${(items as List?)?.length}');
    if (items is List && items.isNotEmpty) {
      final first = Map<String, dynamic>.from(items.first as Map);
      stdout.writeln('firstItem=${jsonEncode(first)}');
    }
  }
  client.close();
}
