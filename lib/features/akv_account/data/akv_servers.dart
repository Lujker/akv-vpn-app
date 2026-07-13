/// Controller addresses baked into the build — the user never types a server.
///
/// To ship a new mirror list: edit [akvServerMirrors] and rebuild the app.
/// Entries may be a bare host ("mirror.example.com") or a full URL; they are
/// normalized by `AkvApiClient.normalizeBaseUrl`. The client tries the
/// last-known-working server first, then this list in order.
library;

const akvPrimaryServer = "akv-server.com";

const akvServerMirrors = <String>[
  // "mirror1.example.com",
];

// Optional build-time override, tried before everything else (dev/staging):
// flutter build ... --dart-define=AKV_API_BASE_URL=https://staging-host
const _buildOverride = String.fromEnvironment("AKV_API_BASE_URL");

List<String> akvServerCandidates() => [
  if (_buildOverride.isNotEmpty) _buildOverride,
  akvPrimaryServer,
  ...akvServerMirrors,
];
