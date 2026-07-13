import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/akv_account/data/akv_api_client.dart';
import 'package:hiddify/features/akv_account/data/akv_servers.dart';
import 'package:hiddify/features/akv_account/model/akv_account_models.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'akv_account_notifier.g.dart';

// TODO(akv, Phase 2): move the session token (and HWID) to flutter_secure_storage.
const _tokenPrefKey = "akv_token";
const _emailPrefKey = "akv_email";
const _userUuidPrefKey = "akv_user_uuid";
const _lastWorkingServerPrefKey = "akv_last_working_server";

/// Server addresses are baked into the build (`akv_servers.dart`) — the user
/// never enters one. The client remembers which mirror last answered and
/// tries it first, then falls back through the rest of the list.
@Riverpod(keepAlive: true)
Future<List<String>> akvServerBaseUrls(Ref ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final candidates = akvServerCandidates();
  final lastWorking = prefs.getString(_lastWorkingServerPrefKey);
  if (lastWorking == null) return candidates;
  return [lastWorking, ...candidates.where((c) => AkvApiClient.normalizeBaseUrl(c) != lastWorking)];
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
    final candidates = await ref.read(akvServerBaseUrlsProvider.future);
    final appInfo = await ref.read(appInfoProvider.future);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    return AkvApiClient(
      baseUrls: candidates,
      userAgent: appInfo.userAgent,
      onBaseUrlSelected: (baseUrl) => prefs.setString(_lastWorkingServerPrefKey, baseUrl),
    );
  }

  Future<void> signIn({required String email, required String password, bool registerNewAccount = false}) async {
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
    final prefs = await ref.read(sharedPreferencesProvider.future);
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
  final candidates = await ref.watch(akvServerBaseUrlsProvider.future);
  final appInfo = await ref.watch(appInfoProvider.future);
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final client = AkvApiClient(
    baseUrls: candidates,
    userAgent: appInfo.userAgent,
    onBaseUrlSelected: (baseUrl) => prefs.setString(_lastWorkingServerPrefKey, baseUrl),
  );
  try {
    return await client.subscriptions(account.token);
  } on AkvApiException catch (e) {
    if (e.code == AkvApiErrorCode.invalidCredentials) {
      // Session revoked on the server — drop the stale local session.
      await ref.read(akvAccountNotifierProvider.notifier).signOut();
      return const AkvSubscriptionsBuckets(active: [], inactive: []);
    }
    rethrow;
  }
}
