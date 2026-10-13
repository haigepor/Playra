import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:kazumi/services/source/source_gateway.dart';
import 'package:kazumi/services/source/source_http_server.dart';
import 'package:kazumi/services/source/source_service.dart';
import 'package:kazumi/services/source/source_policy.dart';

Future<void> main(List<String> args) async {
  String? option(String key) {
    final index = args.indexOf(key);
    if (index < 0) return null;
    if (index + 1 >= args.length) throw ArgumentError('$key requires a value');
    return args[index + 1];
  }

  final port = int.parse(option('--port') ?? '8940');
  final policyPath = option('--policy');
  if (policyPath != null) {
    final policyFile = File(policyPath);
    if (await policyFile.exists()) {
      SourcePolicy.shared.restore(
        await policyFile.readAsString(encoding: utf8),
      );
    }
    SourcePolicy.shared.environment = 'http';
    SourcePolicy.shared.persist = (json) =>
        policyFile.writeAsString(json, encoding: utf8).then((_) {});
  }
  final gatewayUri = Uri.parse(option('--gateway') ?? 'http://127.0.0.1:8933');
  if (!['127.0.0.1', 'localhost'].contains(gatewayUri.host) ||
      gatewayUri.scheme != 'http') {
    throw ArgumentError('Browser gateway must be a local HTTP service');
  }
  final sources = <SourceDefinition>[];
  void append(Object? json, String origin) {
    for (final entry in json is List ? json : [json]) {
      if (entry is! Map) throw const FormatException('Rule must be an object');
      sources.add(
        SourceDefinition.fromJson(
          Map<String, dynamic>.from(entry),
          origin: origin,
        ),
      );
    }
  }

  for (final file in Directory('assets/plugins').listSync().whereType<File>()) {
    if (file.path.endsWith('.json')) {
      append(jsonDecode(await file.readAsString(encoding: utf8)), 'bundled');
    }
  }
  final rulesPath = option('--rules');
  if (rulesPath != null) {
    append(
      jsonDecode(await File(rulesPath).readAsString(encoding: utf8)),
      'imported',
    );
  }
  final gateway = SourceGateway(gatewayUri);
  if (args.contains('--catalog')) {
    const root = 'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';
    final index = await gateway.client.get<String>(
      gatewayUri
          .resolve('/api/proxy')
          .replace(queryParameters: {'url': '${root}index.json'})
          .toString(),
      options: Options(responseType: ResponseType.plain),
    );
    final catalog = jsonDecode(index.data!) as List;
    for (final entry in catalog) {
      final name = (entry as Map)['name'] as String;
      final rule = await gateway.client.get<String>(
        gatewayUri
            .resolve('/api/proxy')
            .replace(
              queryParameters: {
                'url': '$root${Uri.encodeComponent(name)}.json',
              },
            )
            .toString(),
        options: Options(responseType: ResponseType.plain),
      );
      append(jsonDecode(rule.data!), 'store');
    }
  }
  final server = SourceHttpServer(sources: sources, gateway: gateway);
  final bound = await server.start(port: port);
  stdout.writeln(
    'Source HTTP API: http://127.0.0.1:$bound/api/v1 (${server.sources.length} sources)',
  );
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    exit(0);
  });
}
