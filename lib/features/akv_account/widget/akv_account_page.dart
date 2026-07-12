import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/features/akv_account/model/akv_account_models.dart';
import 'package:hiddify/features/akv_account/notifier/akv_account_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// AKV account: sign in with email+password and pull subscriptions from the
/// controller — replaces pasting the `/subs/{uuid}` link from the clipboard.
class AkvAccountPage extends HookConsumerWidget {
  const AkvAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final account = ref.watch(akvAccountNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.akv.account.title)),
      body: switch (account) {
        AsyncData(value: final loggedIn?) => _AccountView(account: loggedIn),
        AsyncData() => const _SignInForm(),
        AsyncError(:final error) => Center(child: Text(t.presentShortError(error))),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

String _describeApiError(Translations t, Object error) => switch (error) {
  AkvApiException(code: AkvApiErrorCode.invalidCredentials) => t.akv.account.errors.invalidCredentials,
  AkvApiException(code: AkvApiErrorCode.emailTaken) => t.akv.account.errors.emailTaken,
  AkvApiException(code: AkvApiErrorCode.rateLimited) => t.akv.account.errors.rateLimited,
  AkvApiException(code: AkvApiErrorCode.network) => t.akv.account.errors.network,
  AkvApiException(:final detail) => "${t.akv.account.errors.server}${detail != null ? " ($detail)" : ""}",
  _ => t.presentShortError(error),
};

class _SignInForm extends HookConsumerWidget {
  const _SignInForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final savedServerUrl = ref.watch(akvServerUrlProvider).valueOrNull ?? "";
    final formKey = useMemoized(() => GlobalKey<FormState>());
    // keyed by the saved value: prefs may resolve after the first frame
    final serverController = useTextEditingController(text: savedServerUrl, keys: [savedServerUrl]);
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final isRegister = useState(false);
    final isSubmitting = useState(false);
    final errorText = useState<String?>(null);
    final obscurePassword = useState(true);

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      isSubmitting.value = true;
      errorText.value = null;
      try {
        await ref
            .read(akvAccountNotifierProvider.notifier)
            .signIn(
              serverUrl: serverController.text,
              email: emailController.text.trim(),
              password: passwordController.text,
              registerNewAccount: isRegister.value,
            );
      } catch (e) {
        errorText.value = _describeApiError(t, e);
      } finally {
        isSubmitting.value = false;
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.account_circle_rounded, size: 64, color: theme.colorScheme.primary),
            const Gap(8),
            Text(
              isRegister.value ? t.akv.account.registerTitle : t.akv.account.loginTitle,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const Gap(24),
            Form(
              key: formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: serverController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t.akv.account.serverUrl,
                      hintText: t.akv.account.serverUrlHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? t.akv.account.errors.serverRequired : null,
                  ),
                  const Gap(16),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: t.akv.account.email, border: const OutlineInputBorder()),
                    validator: (value) =>
                        (value == null || !value.contains('@') || !value.contains('.')) ? t.akv.account.errors.emailInvalid : null,
                  ),
                  const Gap(16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword.value,
                    decoration: InputDecoration(
                      labelText: t.akv.account.password,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword.value ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                        onPressed: () => obscurePassword.value = !obscurePassword.value,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return t.akv.account.errors.passwordTooShort;
                      // The controller requires >= 8 chars on registration.
                      if (isRegister.value && value.length < 8) return t.akv.account.errors.passwordTooShort;
                      return null;
                    },
                    onFieldSubmitted: (_) => submit(),
                  ),
                ],
              ),
            ),
            if (errorText.value != null) ...[
              const Gap(16),
              Text(errorText.value!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
            ],
            const Gap(24),
            FilledButton(
              onPressed: isSubmitting.value ? null : submit,
              child: isSubmitting.value
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isRegister.value ? t.akv.account.register : t.akv.account.login),
            ),
            const Gap(8),
            TextButton(
              onPressed: isSubmitting.value
                  ? null
                  : () {
                      isRegister.value = !isRegister.value;
                      errorText.value = null;
                    },
              child: Text(isRegister.value ? t.akv.account.toLogin : t.akv.account.toRegister),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountView extends HookConsumerWidget {
  const _AccountView({required this.account});

  final AkvAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final subscriptions = ref.watch(akvSubscriptionsProvider);

    // When a subscription profile is added successfully, jump to home so the
    // user can connect right away (the toast is shown by AddProfileNotifier).
    ref.listen(addProfileNotifierProvider, (previous, next) {
      if (next case AsyncData(value: final _?)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.goNamed('home');
        });
      }
    });

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(akvSubscriptionsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(Icons.account_circle_rounded, size: 40, color: theme.colorScheme.primary),
            title: Text(account.email),
            subtitle: Text(t.akv.account.loggedIn),
            trailing: IconButton(
              tooltip: t.akv.account.logout,
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => ref.read(akvAccountNotifierProvider.notifier).signOut(),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(t.akv.account.subscriptions, style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: t.akv.account.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => ref.invalidate(akvSubscriptionsProvider),
                ),
              ],
            ),
          ),
          switch (subscriptions) {
            AsyncData(:final value) when value.active.isEmpty => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(t.akv.account.noSubscriptions, textAlign: TextAlign.center),
            ),
            AsyncData(:final value) => Column(
              children: [for (final sub in value.active) _SubscriptionCard(subscription: sub)],
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_describeApiError(t, error), textAlign: TextAlign.center),
            ),
            _ => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          },
        ],
      ),
    );
  }
}

class _SubscriptionCard extends HookConsumerWidget {
  const _SubscriptionCard({required this.subscription});

  final AkvSubscription subscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final isAdding = ref.watch(addProfileNotifierProvider).isLoading;

    final endDate = subscription.endDate;
    final details = <String>[
      if (endDate != null) "${t.akv.account.expires}: ${DateFormat('dd.MM.yyyy').format(endDate.toLocal())}",
      if (subscription.trafficLimitGb != null)
        subscription.trafficLimitGb == 0 ? t.akv.account.unlimitedTraffic : "${subscription.trafficLimitGb} GB",
      if (subscription.maxDevices != null) "${t.akv.account.devices}: ${subscription.maxDevices}",
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subscription.displayName, style: theme.textTheme.titleMedium),
            if (details.isNotEmpty) ...[
              const Gap(4),
              Text(details.join("  ·  "), style: theme.textTheme.bodySmall),
            ],
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(t.akv.account.useSubscription),
                onPressed: isAdding || subscription.subscriptionUrl == null
                    ? null
                    : () => ref
                          .read(addProfileNotifierProvider.notifier)
                          .addManual(
                            url: subscription.subscriptionUrl!,
                            userOverride: UserOverride(name: subscription.displayName),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
