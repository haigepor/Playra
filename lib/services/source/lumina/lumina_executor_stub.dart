import 'package:dio/dio.dart';
import '../source_models.dart';

Future<Map<String, dynamic>> executeLumina(
  String operation,
  Map<String, dynamic> payload,
  CancelToken? cancel,
) async => throw const SourceException('PLATFORM_UNSUPPORTED', '当前平台尚无动漫引擎');
