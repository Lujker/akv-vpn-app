import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'hwid_provider.g.dart';

const _hwidPrefKey = "akv_hwid";

/// Stable per-install device id sent as `x-hwid` to the AKV controller
/// subscription endpoint (required: the backend enforces HWID device slots).
/// A random UUID generated on first use — never a raw hardware identifier.
@Riverpod(keepAlive: true)
Future<String> hwid(Ref ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final existing = prefs.getString(_hwidPrefKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final generated = const Uuid().v4();
  await prefs.setString(_hwidPrefKey, generated);
  return generated;
}
