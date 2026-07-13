import 'package:dio/dio.dart';
import 'package:hiddify/features/akv_account/model/akv_account_models.dart';
import 'package:hiddify/utils/custom_loggers.dart';

/// Thin client for the AKV controller web API (`/webapi/v1`, Bearer auth).
///
/// Servers are baked into the build (see `akv_servers.dart`): every request is
/// tried against each base URL in order and fails over to the next mirror on
/// network-level errors (unreachable / timeout). An HTTP response from the
/// server (401/409/429/5xx) stops the failover — the server was reached.
///
/// Uses its own direct Dio instances: account calls must work with the VPN off
/// and never depend on the tunnel proxy.
class AkvApiClient with InfraLogger {
  AkvApiClient({required List<String> baseUrls, required String userAgent, this.onBaseUrlSelected})
    : assert(baseUrls.isNotEmpty),
      _baseUrls = baseUrls.map(normalizeBaseUrl).toList(),
      _userAgent = userAgent;

  final List<String> _baseUrls;
  final String _userAgent;

  /// Called with the normalized base URL that served a successful request —
  /// persist it and pass it first on the next app run.
  final void Function(String baseUrl)? onBaseUrlSelected;

  final Map<String, Dio> _dioPerBase = {};

  Dio _dio(String baseUrl) => _dioPerBase.putIfAbsent(
    baseUrl,
    () => Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {"User-Agent": _userAgent},
      ),
    ),
  );

  /// Accepts a bare host ("vpn.example.com"), an origin, or a full API URL and
  /// normalizes it to the controller web API base
  /// (`https://<host>/vpn/webapi/v1` behind nginx — the default deployment).
  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.contains('/webapi')) {
      url = '$url/vpn/webapi/v1';
    } else if (url.endsWith('/webapi')) {
      url = '$url/v1';
    }
    return url;
  }

  /// Runs [request] against each configured server until one is reachable.
  Future<T> _withFailover<T>(Future<T> Function(Dio dio) request) async {
    Object? lastNetworkError;
    for (final baseUrl in _baseUrls) {
      try {
        final result = await request(_dio(baseUrl));
        onBaseUrlSelected?.call(baseUrl);
        return result;
      } on DioException catch (e) {
        if (e.response == null) {
          // No HTTP response — server unreachable, try the next mirror.
          loggy.warning("server unreachable, trying next mirror: [${Uri.parse(baseUrl).host}] ${e.message}");
          lastNetworkError = e.message ?? e.toString();
          continue;
        }
        onBaseUrlSelected?.call(baseUrl);
        _mapHttpError(e);
      }
    }
    throw AkvApiException(AkvApiErrorCode.network, lastNetworkError?.toString());
  }

  Never _mapHttpError(DioException e) {
    final status = e.response?.statusCode;
    final detail = switch (e.response?.data) {
      {'detail': final Object d} => d.toString(),
      _ => null,
    };
    loggy.warning("api error [$status] detail=[$detail]");
    throw switch (status) {
      401 => AkvApiException(AkvApiErrorCode.invalidCredentials, detail),
      409 => AkvApiException(AkvApiErrorCode.emailTaken, detail),
      429 => AkvApiException(AkvApiErrorCode.rateLimited, detail),
      _ => AkvApiException(AkvApiErrorCode.server, detail ?? status.toString()),
    };
  }

  Options _auth(String token) => Options(headers: {"Authorization": "Bearer $token"});

  Future<AkvAccount> _authRequest(
    String path, {
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) => _withFailover((dio) async {
    final res = await dio.post<Map<String, dynamic>>(
      path,
      data: {"email": email, "password": password, "device_name": deviceName, "platform": platform},
    );
    final data = res.data!;
    return AkvAccount(
      token: data['access_token'] as String,
      email: email,
      userUuid: data['user_uuid'] as String,
    );
  });

  Future<AkvAccount> login({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) => _authRequest("/auth/login", email: email, password: password, deviceName: deviceName, platform: platform);

  Future<AkvAccount> register({
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) => _authRequest("/auth/register", email: email, password: password, deviceName: deviceName, platform: platform);

  Future<AkvSubscriptionsBuckets> subscriptions(String token) => _withFailover((dio) async {
    final res = await dio.get<Map<String, dynamic>>("/user/subscriptions", options: _auth(token));
    final data = res.data!;
    List<AkvSubscription> parse(String key) => ((data[key] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AkvSubscription.fromJson)
        .toList();
    return AkvSubscriptionsBuckets(active: parse('active'), inactive: parse('inactive'));
  });

  Future<void> logout(String token) async {
    try {
      await _withFailover((dio) => dio.post<dynamic>("/auth/logout", options: _auth(token)));
    } on AkvApiException catch (e) {
      // Logging out locally must succeed even if the server is unreachable.
      loggy.warning("logout request failed, ignoring", e);
    }
  }
}
