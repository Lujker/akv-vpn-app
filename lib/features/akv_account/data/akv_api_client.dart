import 'package:dio/dio.dart';
import 'package:hiddify/features/akv_account/model/akv_account_models.dart';
import 'package:hiddify/utils/custom_loggers.dart';

/// Thin client for the AKV controller web API (`/webapi/v1`, Bearer auth).
/// Uses its own direct Dio instance: account calls must work with the VPN off
/// and never depend on the tunnel proxy.
class AkvApiClient with InfraLogger {
  AkvApiClient({required String baseUrl, required String userAgent})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {"User-Agent": userAgent},
        ),
      );

  final Dio _dio;

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

  Options _auth(String token) => Options(headers: {"Authorization": "Bearer $token"});

  Never _mapError(DioException e) {
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
      != null => AkvApiException(AkvApiErrorCode.server, detail ?? status.toString()),
      _ => AkvApiException(AkvApiErrorCode.network, e.message),
    };
  }

  Future<AkvAccount> _authRequest(
    String path, {
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: {"email": email, "password": password, "device_name": deviceName, "platform": platform},
      );
      final data = res.data!;
      return AkvAccount(
        token: data['access_token'] as String,
        email: email,
        userUuid: data['user_uuid'] as String,
      );
    } on DioException catch (e) {
      _mapError(e);
    }
  }

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

  Future<AkvSubscriptionsBuckets> subscriptions(String token) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>("/user/subscriptions", options: _auth(token));
      final data = res.data!;
      List<AkvSubscription> parse(String key) => ((data[key] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AkvSubscription.fromJson)
          .toList();
      return AkvSubscriptionsBuckets(active: parse('active'), inactive: parse('inactive'));
    } on DioException catch (e) {
      _mapError(e);
    }
  }

  Future<void> logout(String token) async {
    try {
      await _dio.post<dynamic>("/auth/logout", options: _auth(token));
    } on DioException catch (e) {
      // Logging out locally must succeed even if the server is unreachable.
      loggy.warning("logout request failed, ignoring", e);
    }
  }
}
