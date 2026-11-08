import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/layout/app_content_frame.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/browser_info_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/browser_info_web.dart';
import 'package:pdd_app/data/services/pending_payment.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/web_checkout_route.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/user_avatar.dart';
import 'package:pdd_app/presentation/widgets/premium_plan_card.dart';
import 'package:pdd_app/presentation/widgets/premium_checkout_header.dart';
import 'package:url_launcher/url_launcher.dart';

/// Browser-only entry point. Native apps retain their store/region policies.
class PremiumWebCheckoutScreen extends StatefulWidget {
  const PremiumWebCheckoutScreen({
    super.key,
    this.initialTier = PremiumTier.threeMonths,
    this.campaignId,
    this.paymentReturn,
    this.openPayment,
  });

  final PremiumTier initialTier;
  final String? campaignId;
  final ({String result, String order})? paymentReturn;
  final Future<bool> Function(Uri)? openPayment;

  @override
  State<PremiumWebCheckoutScreen> createState() =>
      _PremiumWebCheckoutScreenState();
}

class _PremiumWebCheckoutScreenState extends State<PremiumWebCheckoutScreen>
    with WidgetsBindingObserver {
  final _auth = AuthService.instance;
  final _premium = PremiumService.instance;
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late PremiumTier _tier;
  String? _owner;
  String? _order;
  String? _status;
  String? _error;
  Uri? _paymentUrl;
  bool _available = false;
  bool _loadingAvailability = false;
  bool _creating = false;
  bool _checking = false;
  bool _restoreFailed = false;
  bool _restoring = false;
  bool _changingAccount = false;
  bool _uncertainCreate = false;
  bool _active = true;
  int _checks = 0;
  Timer? _poll;
  int _revision = 0;

  bool get _signedIn => _auth.hasServerSession && _auth.currentUser != null;
  bool get _busy => _creating || _checking || _changingAccount || _restoring;
  bool get _locked => _busy || _order != null || _uncertainCreate;
  bool get _paid => _status == 'confirmed';
  bool get _terminal => const [
    'canceled',
    'failed',
    'create_failed',
    'chargebacked',
  ].contains(_status);
  bool get _review => const [
    'creation_unknown',
    'requires_refund',
    'mismatch',
  ].contains(_status);

  @override
  void initState() {
    super.initState();
    _tier = widget.initialTier;
    setWebCheckoutTier(_tier.name);
    _auth.addListener(_accountChanged);
    _premium.addListener(_premiumChanged);
    WidgetsBinding.instance.addObserver(this);
    final returned = widget.paymentReturn ?? takePaymentReturn();
    if (WebCheckoutRoute.validOrder(returned?.order)) _order = returned!.order;
    // Even a failed redirect is only a hint. Verify with our server before
    // saying whether money arrived, or allowing another purchase.
    _accountChanged();
    unawaited(_loadAvailability());
  }

  void _showStageStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _premiumChanged() {
    if (mounted) setState(() {});
  }

  void _accountChanged() {
    final owner = _signedIn ? _auth.currentUser!.id : null;
    if (owner == _owner) return;
    final firstOwner = _owner == null && _revision == 0;
    _owner = owner;
    _revision++;
    _showStageStart();
    _creating = false;
    _checking = false;
    _restoring = false;
    _poll?.cancel();
    _checks = 0;
    _paymentUrl = null;
    _error = null;
    _status = null;
    _uncertainCreate = false;
    _restoreFailed = false;
    // A return URL does not prove ownership. Keep it on first login so the
    // server can check it; never carry it over to another authenticated user.
    if (!firstOwner) _order = null;
    final email = _auth.currentUser?.email ?? '';
    _email.text = email.contains('@') && !email.endsWith('@telegram.local')
        ? email
        : '';
    if (mounted) setState(() {});
    if (owner != null) {
      _restoring = true;
      unawaited(_restoreOrder(owner, _revision));
    }
  }

  Future<void> _restoreOrder(String owner, int revision) async {
    try {
      final pending = await PendingPayment.current(ownerId: owner);
      if (!mounted || revision != _revision) return;
      _order ??= pending;
      await _check();
    } finally {
      if (mounted && revision == _revision) setState(() => _restoring = false);
    }
  }

  Future<void> _loadAvailability() async {
    if (_loadingAvailability) return;
    setState(() => _loadingAvailability = true);
    final available = await _premium.webPaymentsAvailable();
    if (!mounted) return;
    setState(() {
      _available = available;
      _loadingAvailability = false;
    });
  }

  Future<void> _changeAccount() async {
    if (_creating || _changingAccount) return;
    setState(() => _changingAccount = true);
    try {
      await _auth.signOut();
    } finally {
      if (mounted) setState(() => _changingAccount = false);
    }
  }

  Future<void> _pay() async {
    if (_busy ||
        _restoreFailed ||
        _order != null ||
        !_available ||
        !_signedIn ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final revision = _revision;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final result = await _premium.startWebPayment(
        tier: _tier,
        email: _email.text.trim(),
        checkout: true,
        campaignId: widget.campaignId,
      );
      if (!mounted || revision != _revision) return;
      if (result == null) {
        // Freeze the submitted choice. A retry asks for the same order, rather
        // than silently making another purchase after an ambiguous response.
        setState(() {
          _uncertainCreate = true;
          _error = appL10n.checkoutCreateRetry;
        });
        return;
      }
      if (result.order == null) {
        setState(() {
          _available = false;
          _error = appL10n.checkoutUnavailable;
        });
        return;
      }
      setState(() {
        _order = result.order;
        _status = switch (result.errorCode) {
          'payment_creation_pending' => 'creating',
          'payment_creation_unknown' => 'creation_unknown',
          _ => 'pending',
        };
        _paymentUrl = result.url == null ? null : Uri.tryParse(result.url!);
        _uncertainCreate = false;
      });
      _showStageStart();
      if (_paymentUrl != null) await _openPayment();
      _scheduleCheck();
    } finally {
      if (mounted && revision == _revision) setState(() => _creating = false);
    }
  }

  Future<void> _openPayment() async {
    final url = _paymentUrl;
    if (url == null) return;
    try {
      final opened =
          await (widget.openPayment?.call(url) ??
              launchUrl(
                url,
                webOnlyWindowName: '_self',
                mode: LaunchMode.platformDefault,
              ));
      if (!opened && mounted) setState(() => _error = appL10n.webPayFailed);
    } catch (_) {
      if (mounted) setState(() => _error = appL10n.webPayFailed);
    }
  }

  Future<void> _check() async {
    final order = _order;
    if (_checking || _creating || !_signedIn) return;
    _poll?.cancel();
    final revision = _revision;
    setState(() => _checking = true);
    try {
      final details = await _premium.checkWebPaymentDetails(order: order);
      final status = details?.status;
      if (!mounted || revision != _revision || order != _order) return;
      final previousStatus = _status;
      setState(() {
        _restoreFailed = status == null && order == null;
        if (details != null && WebCheckoutRoute.validOrder(details.order)) {
          _order = details.order;
          _paymentUrl = details.url == null ? null : Uri.tryParse(details.url!);
        }
        _status = status ?? _status;
        _error = status == null ? appL10n.checkoutCheckFailed : null;
        _checks++;
      });
      if (previousStatus != _status && (_paid || _terminal || _review)) {
        _showStageStart();
      }
      if (_paid || _terminal) {
        final pending = await PendingPayment.current(ownerId: _owner);
        if (mounted && revision == _revision && pending == order) {
          await PendingPayment.clear(ownerId: _owner);
        }
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _checking = false);
        _scheduleCheck();
      }
    }
  }

  void _scheduleCheck() {
    _poll?.cancel();
    if (!_active ||
        _order == null ||
        _paid ||
        _terminal ||
        _review ||
        _checks >= 12) {
      return;
    }
    _poll = Timer(Duration(seconds: _checks < 6 ? 5 : 15), _check);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _active = state == AppLifecycleState.resumed);
    if (_active) {
      _checks = 0;
      if (!_paid && !_terminal && !_review) unawaited(_check());
    } else {
      _poll?.cancel();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _auth.removeListener(_accountChanged);
    _premium.removeListener(_premiumChanged);
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _provider(AuthProviderType provider) => switch (provider) {
    AuthProviderType.google => 'Google',
    AuthProviderType.apple => 'Apple',
    AuthProviderType.yandex => appL10n.checkoutYandex,
    AuthProviderType.telegram => 'Telegram',
  };

  Widget _card(List<Widget> children, AppThemeColors colors) => Material(
    color: colors.cardBackground,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _result(AppThemeColors colors) {
    final message = _terminal
        ? appL10n.checkoutCanceled
        : _review
        ? appL10n.webPayCreationReview(_order!)
        : _status == 'creating'
        ? appL10n.webPayCreationPending(_order!)
        : appL10n.webPayPending;
    return _card([
      Icon(
        Icons.receipt_long_rounded,
        size: 44,
        color: colors.primaryText.withValues(alpha: 0.7),
      ),
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        child: Text(
          message,
          key: const ValueKey('checkout-result'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 12),
      SelectableText(
        appL10n.checkoutOrder(_order!),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: colors.primaryText.withValues(alpha: 0.7),
        ),
      ),
      const SizedBox(height: 12),
      if (!_terminal)
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () {
                  _checks = 0;
                  unawaited(_check());
                },
          icon: const Icon(Icons.refresh_rounded),
          label: Text(appL10n.checkoutCheck),
        ),
      if (_paymentUrl != null && _status == 'pending')
        TextButton(
          onPressed: _busy ? null : _openPayment,
          child: Text(appL10n.checkoutContinue),
        ),
      if (_terminal)
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _order = null;
                  _status = null;
                  _error = null;
                }),
          child: Text(appL10n.checkoutChooseAgain),
        ),
    ], colors);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final user = _auth.currentUser;
    final stage = !_signedIn
        ? 0
        : _paid
        ? 2
        : 1;
    const pageForeground = AppColors.white;
    const pageBackground = AppColors.accent;
    final title = !_signedIn
        ? appL10n.checkoutSignInTitle
        : _paid
        ? appL10n.premiumCelebrationPurchasedTitle
        : _order != null
        ? (_terminal || _review)
              ? appL10n.checkoutIssueTitle
              : appL10n.checkoutWaitingTitle
        : appL10n.checkoutChoosePlan;
    final subtitle = !_signedIn
        ? appL10n.checkoutSignInSubtitle
        : _paid
        ? appL10n.checkoutStepReturn
        : _order != null
        ? appL10n.checkoutWaitingSubtitle
        : null;
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: pageBackground,
        foregroundColor: pageForeground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(18) > 26
            ? 88
            : 64,
        title: AppContentFrame(
          maxWidth: 600,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 32,
                  height: 32,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  CountryConfig.current.appTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: pageForeground,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
        centerTitle: false,
      ),
      body: _paid
          ? SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 64).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: Center(
                      child: AppContentFrame(
                        maxWidth: 600,
                        child: TickerMode(
                          enabled: _active,
                          child: PremiumCheckoutHeader(
                            stage: stage,
                            title: title,
                            subtitle: subtitle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: AppContentFrame(
                  maxWidth: 600,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TickerMode(
                        enabled: _active,
                        child: PremiumCheckoutHeader(
                          stage: stage,
                          title: title,
                          subtitle: subtitle,
                          onAccountTap:
                              _signedIn && !_creating && !_changingAccount
                              ? _changeAccount
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_signedIn)
                        Theme(
                          data: AppTheme.lightTheme.copyWith(
                            platform: Theme.of(context).platform,
                            extensions: [
                              AppThemeColors.light.copyWith(
                                searchFieldFill: AppColors.white,
                              ),
                            ],
                          ),
                          child: const AuthModalSheet(embedded: true),
                        )
                      else ...[
                        _card([
                          Text(
                            _paid
                                ? appL10n.checkoutAccountPaid
                                : appL10n.checkoutAccount,
                            style: TextStyle(
                              color: colors.primaryText.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(
                                child: UserAvatar(
                                  key: const ValueKey('checkout-avatar'),
                                  url: user!.avatarUrl,
                                  useDefault: user.useDefaultAvatar,
                                  size: 48,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.name,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      key: const ValueKey('checkout-account'),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Tooltip(
                                          message: _provider(user.provider),
                                          child: SvgPicture.asset(
                                            'assets/icons/auth/${user.provider.name}.svg',
                                            width: 18,
                                            height: 18,
                                            excludeFromSemantics: true,
                                            colorFilter:
                                                user.provider ==
                                                    AuthProviderType.apple
                                                ? ColorFilter.mode(
                                                    colors.primaryText,
                                                    BlendMode.srcIn,
                                                  )
                                                : null,
                                          ),
                                        ),
                                        if (user.email.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              user.email,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Tooltip(
                                message: appL10n.checkoutChangeAccount,
                                child: AppChromeIconButton(
                                  key: const ValueKey(
                                    'checkout-change-account',
                                  ),
                                  icon: Icons.close_rounded,
                                  backgroundColor: colors.searchFieldFill,
                                  onTap: _creating || _changingAccount
                                      ? null
                                      : _changeAccount,
                                ),
                              ),
                            ],
                          ),
                          if (_premium.isPremium && !_paid)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                appL10n.checkoutExistingPremium,
                                style: TextStyle(color: colors.accent),
                              ),
                            ),
                        ], colors),
                        const SizedBox(height: 16),
                        if (_order != null)
                          _result(colors)
                        else
                          _card([
                            for (final tier in [
                              PremiumTier.threeMonths,
                              PremiumTier.weekly,
                            ]) ...[
                              PremiumPlanCard(
                                key: ValueKey('checkout-plan-${tier.name}'),
                                title: tier == PremiumTier.weekly
                                    ? appL10n.webWeek
                                    : appL10n.webQuarter,
                                price: tier == PremiumTier.weekly
                                    ? '99 ₽'
                                    : '290 ₽',
                                period: tier == PremiumTier.weekly
                                    ? appL10n.checkoutDurationWeek
                                    : appL10n.checkoutDurationQuarter,
                                selected: _tier == tier,
                                badge: tier == PremiumTier.threeMonths
                                    ? appL10n.paywallBadgeBest
                                    : null,
                                onTap: _locked
                                    ? null
                                    : () => setState(() {
                                        _tier = tier;
                                        setWebCheckoutTier(tier.name);
                                      }),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Form(
                              key: _form,
                              child: TextFormField(
                                key: const ValueKey('checkout-email'),
                                controller: _email,
                                enabled: !_locked,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: InputDecoration(
                                  labelText: appL10n.checkoutReceiptEmailLabel,
                                ),
                                validator: (value) =>
                                    RegExp(
                                      r'^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$',
                                    ).hasMatch(value?.trim() ?? '')
                                    ? null
                                    : appL10n.webPayEmailInvalid,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_restoreFailed)
                              TextButton(
                                onPressed: _busy ? null : _check,
                                child: Text(appL10n.checkoutCheck),
                              ),
                            if (!_available && !_loadingAvailability) ...[
                              Text(
                                appL10n.checkoutUnavailable,
                                style: TextStyle(
                                  color: colors.primaryText.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _loadAvailability,
                                child: Text(appL10n.checkoutRetryAvailability),
                              ),
                            ],
                            const SizedBox(height: 8),
                            ElevatedButton(
                              key: const ValueKey('checkout-pay'),
                              onPressed: _restoreFailed || _busy || !_available
                                  ? null
                                  : _pay,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.accent,
                                foregroundColor: AppColors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: const EdgeInsets.all(16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDimensions.buttonRadius,
                                  ),
                                ),
                              ),
                              child: _creating || _loadingAvailability
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.white,
                                      ),
                                    )
                                  : Text(
                                      _uncertainCreate
                                          ? appL10n.checkoutRetryCreate
                                          : appL10n.webPayButton,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              appL10n.checkoutPaymentTerms,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: colors.primaryText.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ], colors),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _card([
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                key: const ValueKey('checkout-error'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ], colors),
                        ),
                      const SizedBox(height: 32),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          _link(
                            appL10n.paywallTerms,
                            CountryConfig.current.termsUrl,
                          ),
                          _link(
                            appL10n.paywallPrivacy,
                            CountryConfig.current.privacyUrl,
                          ),
                          _link(
                            appL10n.checkoutSupport,
                            'mailto:${CountryConfig.current.supportEmail}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _link(String label, String url) => TextButton(
    onPressed: () =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    style: TextButton.styleFrom(foregroundColor: AppColors.white),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
  );
}
