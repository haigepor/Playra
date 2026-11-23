/// CliCli (Myuko Ktor client) protocol constants.
///
/// Values are stable for app version 1.0.10 and were recovered during the
/// protocol RE documented in `D:/project-Auto/CliCli动漫/dm-client`.
library;

class CliCliConfig {
  CliCliConfig._();

  static const String sourceId = 'clicli';
  static const String sourceName = 'CliCli';

  static const String baseUrl = 'http://1.14.219.185:7090';
  static const String apiPrefix = '/api/v1/app/client';

  static const String appId = '317176586754400256';
  static const String signSecret = String.fromEnvironment(
    'CLICLI_SIGN_SECRET',
  );
  static const String masterSecret = String.fromEnvironment(
    'CLICLI_MASTER_SECRET',
  );
  static const String deviceId = String.fromEnvironment(
    'CLICLI_DEVICE_ID',
  );

  /// Bootstrap session key baked into the APK. Used until `auth/negotiate`
  /// hands out a per-device secret (or a 4020 forces renegotiation).
  static const String bootstrapSessionSecret = String.fromEnvironment(
    'CLICLI_BOOTSTRAP_SESSION_SECRET',
  );

  /// Code-unmask salt. The service uses the same init salt in both directions;
  /// the `wire-code-code-mask` constant exists in the native blob but is not
  /// what the live gateway signs responses with (verified by live probe).
  static const String serverCodeSalt = 'wire-code-mask';

  static const String platform = 'android';
  static const String userAgent = 'Myuko Ktor Client';

  static const String deviceFingerprint = String.fromEnvironment(
    'CLICLI_DEVICE_FINGERPRINT',
  );
  static const String fingerPrintSign = String.fromEnvironment(
    'CLICLI_FINGERPRINT_SIGNATURE',
  );
  static const String fingerPrintAlgo = '1';

  static bool get isConfigured => <String>[
    signSecret,
    masterSecret,
    bootstrapSessionSecret,
    deviceId,
    deviceFingerprint,
    fingerPrintSign,
  ].every((value) => value.trim().isNotEmpty);

  static const String playerPreRollSlot = 'player_pre_roll';
  static const String defaultPlayerCode = 'mao';
  static const List<String> caps = <String>['hls', 'mp4'];

  // ---- endpoint paths (relative to [apiPrefix]) ----
  static const String pathHome = '$apiPrefix/home/recommend';
  static const String pathBanners = '$apiPrefix/banner/list';
  static const String pathModules = '$apiPrefix/video/modules';
  static const String pathTypes = '$apiPrefix/type/listActive';
  static const String pathCategoryVideos = '$apiPrefix/video/categoryList';
  static const String pathSearch = '$apiPrefix/video/search';
  static const String pathDetail = '$apiPrefix/video/detail';
  static const String pathEpisodes = '$apiPrefix/resolve/episodes';
  static const String pathQualities = '$apiPrefix/resolve/qualities';
  static const String pathExchange = '$apiPrefix/resolve/exchange';
  static const String pathAdSlots = '$apiPrefix/ad/getSlots';
  static const String pathAdConfig = '$apiPrefix/ad/getConfig';
  static const String pathAdSignature = '$apiPrefix/ad/getSignature';
  static const String pathAdReportEvent = '$apiPrefix/ad/reportEvent';
  static const String pathAdClaimReward = '$apiPrefix/ad/claimReward';
  static const String pathNegotiate = '$apiPrefix/auth/negotiate';
  static const String pathRefreshToken = '$apiPrefix/auth/refreshToken';
}
