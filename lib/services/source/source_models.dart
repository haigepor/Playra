import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

class SourceException implements Exception {
  const SourceException(this.code, this.message, {this.providerId});
  final String code, message;
  final String? providerId;
  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (providerId != null) 'providerId': providerId,
  };
  @override
  String toString() => '$code: $message';
}

class SourceContext {
  SourceContext({
    this.sessionId = 'local',
    RuleCancelToken? cancelToken,
    this.providerId,
    this.timeout = const Duration(seconds: 30),
  }) : cancelToken = RuleCancelToken() {
    if (cancelToken != null) {
      if (cancelToken.isCancelled) {
        this.cancelToken.cancel(cancelToken.cancelError);
      }
      unawaited(
        cancelToken.whenCancel.then((error) => this.cancelToken.cancel(error)),
      );
    }
  }
  final String sessionId;
  final String? providerId;
  final RuleCancelToken cancelToken;
  final Duration timeout;
  void checkActive() {
    if (cancelToken.isCancelled) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
  }
}

class SourceManifest {
  const SourceManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.apiLevel,
    this.origin = 'imported',
    this.capabilities = const ['search', 'episodes', 'resolve'],
  });
  final String id, name, version, origin;
  final int apiLevel;
  final List<String> capabilities;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'ruleApiLevel': apiLevel,
    'origin': origin,
    'capabilities': capabilities,
  };
}

class SourceRef {
  const SourceRef({required this.providerId, required this.rawRef});
  final String providerId, rawRef;
  String get id =>
      sha256.convert(utf8.encode('$providerId\u0000$rawRef')).toString();
  // rawRef 仅用于内部规则执行，HTTP 使用不透明 ID，避免泄漏签名参数。
  Map<String, dynamic> toJson() => {'providerId': providerId, 'id': id};
}

class SourceClassification {
  const SourceClassification({
    this.kind = 'unknown',
    this.region,
    this.format,
    this.rawCategory,
    this.evidence = 'unknown',
  });
  final String kind, evidence;
  final String? region, format, rawCategory;
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'region': region,
    'format': format,
    'rawCategory': rawCategory,
    'evidence': evidence,
  };
}

class SourceContent {
  const SourceContent({
    required this.ref,
    required this.title,
    this.coverUrl,
    this.classification = const SourceClassification(),
    this.sourceUpdatedAt,
    this.broadcastAt,
  });
  final SourceRef ref;
  final String title;
  final String? coverUrl;
  final SourceClassification classification;
  final DateTime? sourceUpdatedAt, broadcastAt;
  Map<String, dynamic> toJson() => {
    ...ref.toJson(),
    'title': title,
    'coverUrl': coverUrl,
    'classification': classification.toJson(),
    'sourceUpdatedAt': sourceUpdatedAt?.toIso8601String(),
    'broadcastAt': broadcastAt?.toIso8601String(),
  };
}

class SourcePagination {
  const SourcePagination({
    required this.page,
    required this.pageSize,
    required this.mode,
    this.total,
    this.hasMore,
  });
  final int page, pageSize;
  final String mode;
  final int? total;
  final bool? hasMore;
  Map<String, dynamic> toJson() => {
    'page': page,
    'pageSize': pageSize,
    'mode': mode,
    'total': total,
    'hasMore': hasMore,
  };
}

class SourcePage<T> {
  const SourcePage(this.items, this.pagination);
  final List<T> items;
  final SourcePagination pagination;
  static void validate(int page, int pageSize) {
    if (page < 1 || pageSize < 1 || pageSize > 100) {
      throw const SourceException(
        'INVALID_ARGUMENT',
        'page 必须大于零，pageSize 范围为 1–100',
      );
    }
  }

  static SourcePage<T> local<T>(
    List<T> items, {
    int page = 1,
    int pageSize = 20,
  }) {
    validate(page, pageSize);
    // 先比较页数再乘偏移，避免极大合法整数在 VM 上溢出。
    final lastPage = (items.length + pageSize - 1) ~/ pageSize;
    final start = page > lastPage ? items.length : (page - 1) * pageSize;
    return SourcePage(
      items.skip(start).take(pageSize).toList(),
      SourcePagination(
        page: page,
        pageSize: pageSize,
        mode: 'local',
        total: items.length,
        hasMore: page < lastPage,
      ),
    );
  }
}

class SourceEpisode {
  const SourceEpisode({
    required this.id,
    required this.title,
    required this.pageUrl,
    required this.index,
  });
  final String id, title, pageUrl;
  final int index;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'index': index};
}

class SourceLine {
  const SourceLine({
    required this.id,
    required this.name,
    required this.episodes,
  });
  final String id, name;
  final List<SourceEpisode> episodes;
  Road toRoad() => Road(
    name: name,
    data: episodes.map((e) => e.pageUrl).toList(),
    identifier: episodes.map((e) => e.title).toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}

class SourceHealth {
  const SourceHealth({
    required this.operation,
    required this.status,
    required this.checkedAt,
    required this.elapsedMs,
    this.errorCode,
  });
  final String operation, status;
  final DateTime checkedAt;
  final int elapsedMs;
  final String? errorCode;
  Map<String, dynamic> toJson() => {
    'operation': operation,
    'status': status,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'elapsedMs': elapsedMs,
    'errorCode': errorCode,
  };
}
