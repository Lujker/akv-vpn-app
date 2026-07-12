/// Minimal models for the AKV controller web API (`/webapi/v1`).
/// Kept as plain Dart (no codegen) — the account feature is a thin client.
library;

class AkvAccount {
  const AkvAccount({required this.token, required this.email, required this.userUuid});

  final String token;
  final String email;
  final String userUuid;
}

class AkvSubscription {
  const AkvSubscription({
    required this.uuid,
    required this.isActive,
    this.name,
    this.planName,
    this.status,
    this.endDate,
    this.subscriptionUrl,
    this.trafficLimitGb,
    this.maxDevices,
  });

  final String uuid;
  final bool isActive;
  final String? name;
  final String? planName;
  final String? status;
  final DateTime? endDate;

  /// Universal HTTPS subscription link served by the controller
  /// (`subscription_url` field) — importable as a remote profile as-is.
  final String? subscriptionUrl;
  final int? trafficLimitGb;
  final int? maxDevices;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final p = planName?.trim();
    if (p != null && p.isNotEmpty) return p;
    return "AKV VPN";
  }

  factory AkvSubscription.fromJson(Map<String, dynamic> json) => AkvSubscription(
    uuid: json['uuid'] as String,
    isActive: json['is_active'] == true,
    name: json['name'] as String?,
    planName: json['plan_name'] as String?,
    status: json['status'] as String?,
    endDate: json['end_date'] != null ? DateTime.tryParse(json['end_date'] as String) : null,
    subscriptionUrl: json['subscription_url'] as String?,
    trafficLimitGb: (json['traffic_limit_gb'] as num?)?.toInt(),
    maxDevices: (json['max_devices'] as num?)?.toInt(),
  );
}

class AkvSubscriptionsBuckets {
  const AkvSubscriptionsBuckets({required this.active, required this.inactive});

  final List<AkvSubscription> active;
  final List<AkvSubscription> inactive;
}

enum AkvApiErrorCode { invalidCredentials, emailTaken, rateLimited, unauthorized, network, server }

class AkvApiException implements Exception {
  const AkvApiException(this.code, [this.detail]);

  final AkvApiErrorCode code;
  final String? detail;

  @override
  String toString() => "AkvApiException(${code.name}${detail != null ? ": $detail" : ""})";
}
