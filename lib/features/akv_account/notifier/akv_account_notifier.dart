import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/akv_account/data/akv_api_client.dart';
import 'package:hiddify/features/akv_account/model/akv_account_models.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'akv_account_notifier.g.dart';

// Compile-time default for the controller address (see docs/private/BUILD_RU.md):
// flutter build ... --dart-define=AKV_API_BASE_URL=https://<host>
const _defaultServerUrl = String.fromEnvironment('AKV_API_BASE_URL');

const _serverUrlPrefKey = "akv_server_url";
// TODO(akv, Phase 2): move the token (and HWID) to flutter_secure_storage.
const _tokenPrefKey = "akv_token";
const _emailPrefKey = "akv_email";
const _userUuidPrefKey = "akv_user_uuid";

/// Persisted controller address as entered by the user (may be a bare host).
@Riverpod(keepAlive: true)
Future<String> akvServerUrl(Ref ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return prefs.getString(_serverUrlPrefKey) ?? _defaultServerUrl;
}

/// Logged-in AKV account (null — signed out). Session token is persisted so
/// the account survives app restarts; the controller keeps one session per
/// device (`user_sessions`), so other devices stay logged in.
@Riverpod(keepAlive: true)
class AkvAccountNotifier extends _$AkvAccountNotifier with AppLogger {
  @override
  Future<AkvAccount?> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final token = prefs.getString(_tokenPrefKey);
    if (token == null || token.isEmpty) return null;
    return AkvAccount(
      token: token,
      email: prefs.getString(_emailPrefKey) ?? "",
      userUuid: prefs.getString(_userUuidPrefKey) ?? "",
    );
  }

  Future<AkvApiClient> _client() async {
    final serverUrl = await ref.read(akvServerUrlProvider.future);
    final appInfo = await ref.read(appInfoProvider.future);
    return AkvApiClient(baseUrl: AkvApiClient.normalizeBaseUrl(serverUrl), userAgent: appInfo.userAgent);
  }

  Future<void> signIn({
    required String serverUrl,
    required String email,
    required String password,
    bool registerNewAccount = false,
  }) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_serverUrlPrefKey, serverUrl.trim());
    ref.invalidate(akvServerUrlProvider);

    final appInfo = await ref.read(appInfoProvider.future);
    final client = await _client();
    final deviceName = "${appInfo.operatingSystem} ${appInfo.operatingSystemVersion}";
    loggy.debug("signing in (register=$registerNewAccount)");
    final account = registerNewAccount
        ? await client.register(
            email: email,
            password: password,
            deviceName: deviceName,
            platform: appInfo.operatingSystem,
          )
        : await client.login(
            email: email,
            password: password,
            deviceName: deviceName,
            platform: appInfo.operatingSystem,
          );
    await prefs.setString(_tokenPrefKey, account.token);
    await prefs.setString(_emailPrefKey, account.email);
    await prefs.setString(_userUuidPrefKey, account.userUuid);
    state = AsyncData(account);
    loggy.info("signed in");
  }

  Future<void> signOut() async {
    final account = state.valueOrNull;
    if (account != null) {
      final client = await _client();
      await client.logout(account.token);
    }
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.remove(_tokenPrefKey);
    await prefs.remove(_emailPrefKey);
    await prefs.remove(_userUuidPrefKey);
    state = const AsyncData(null);
    loggy.info("signed out");
  }
}

/// Subscriptions of the logged-in account, newest server state on every watch.
@riverpod
Future<AkvSubscriptionsBuckets> akvSubscriptions(Ref ref) async {
  final account = await ref.watch(akvAccountNotifierProvider.future);
  if (account == null) return const AkvSubscriptionsBuckets(active: [], inactive: []);
  final serverUrl = await ref.watch(akvServerUrlProvider.future);
  final appInfo = await ref.watch(appInfoProvider.future);
  final client = AkvApiClient(baseUrl: AkvApiClient.normalizeBaseUrl(serverUrl), userAgent: appInfo.userAgent);
  try {
    return await client.subscriptions(account.token);
  } on AkvApiException catch (e) {
    if (e.code == AkvApiErrorCode.invalidCredentials || e.code == AkvApiErrorCode.unauthorized) {
      // Session revoked on the server — drop the stale local session.
      await ref.read(akvAccountNotifierProvider.notifier).signOut();
      return const AkvSubscriptionsBuckets(active: [], inactive: []);
    }
    rethrow;
  }
}
