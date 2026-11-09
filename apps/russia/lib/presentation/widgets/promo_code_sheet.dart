import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/referral_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_celebration_screen.dart';

class PromoCodeSheet extends StatefulWidget {
  const PromoCodeSheet({super.key});

  static Future<bool?> show(BuildContext context) async {
    HapticFeedbackHelper.tap();
    final result = await showModalBottomSheet<ReferralClaimResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => const PromoCodeSheet(),
    );
    if (result == null) return null;

    final premium = PremiumService.instance;
    if (context.mounted && !result.alreadyApplied && premium.isPremium) {
      await PremiumCelebrationScreen.show(
        context,
        reason: PremiumCelebrationReason.promoCode,
        expiresAt: premium.expiresAt,
        message: context.l10n.referralSuccessDays(result.daysAdded),
      );
    }
    return true;
  }

  @override
  State<PromoCodeSheet> createState() => _PromoCodeSheetState();
}

class _PromoCodeSheetState extends State<PromoCodeSheet> {
  final _service = ReferralService.instance;
  final _auth = AuthService.instance;
  late final TextEditingController _code;
  late (String?, int, bool) _account;
  ReferralClaimResult? _result;
  bool _signingIn = false;

  (String?, int, bool) get _currentAccount =>
      (_auth.currentUser?.id, _auth.accountRevision, _auth.hasServerSession);

  @override
  void initState() {
    super.initState();
    _account = _currentAccount;
    _code = TextEditingController(text: _service.pendingCode);
    _service.addListener(_changed);
    _auth.addListener(_authChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_authChanged);
    _service.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_service.pendingCode case final String pending
        when _code.text.isEmpty) {
      _code.text = pending;
    }
    setState(() {});
  }

  void _authChanged() {
    if (_account != _currentAccount) {
      _account = _currentAccount;
      _result = null;
      if (!_signingIn) _code.text = _service.pendingCode ?? '';
    }
    _changed();
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    FocusScope.of(context).unfocus();
    await _service.savePendingCode(_code.text);
    if (!mounted) return;
    await AuthModalSheet.show(context);
    if (mounted) setState(() => _signingIn = false);
  }

  Future<void> _activate() async {
    if (_service.claiming || _signingIn) return;
    if (referralCodeFromInput(_code.text) == null) {
      setState(
        () => _result = const ReferralClaimResult(
          status: ReferralClaimStatus.invalidCode,
        ),
      );
      return;
    }
    if (!_auth.hasServerSession) {
      await _signIn();
      return;
    }
    final account = _account;
    FocusScope.of(context).unfocus();
    setState(() => _result = null);
    final result = await _service.claimCode(_code.text);
    if (!mounted || _currentAccount != account) return;
    if (result.status == ReferralClaimStatus.success &&
        !result.alreadyApplied) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(result);
      }
      return;
    }
    setState(() => _result = result);
    if (result.status == ReferralClaimStatus.success) {
      HapticFeedbackHelper.success();
    } else {
      HapticFeedbackHelper.error();
    }
  }

  bool get _alreadyApplied => _result?.alreadyApplied == true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final renewSignIn = _result?.status == ReferralClaimStatus.unauthenticated;
    final error = switch (_result?.status) {
      ReferralClaimStatus.invalidCode => l10n.referralErrorInvalid,
      ReferralClaimStatus.ineligible => l10n.promoReferralIneligible,
      ReferralClaimStatus.unavailable => l10n.promoUnavailable,
      ReferralClaimStatus.expired => l10n.promoExpired,
      ReferralClaimStatus.notStarted => l10n.promoNotStarted,
      ReferralClaimStatus.exhausted => l10n.promoExhausted,
      ReferralClaimStatus.alreadyClaimed => l10n.referralErrorAlreadyUsed,
      ReferralClaimStatus.selfReferral => l10n.referralErrorSelf,
      ReferralClaimStatus.notFound => l10n.referralErrorNotFound,
      ReferralClaimStatus.rateLimited => l10n.referralErrorRateLimited,
      ReferralClaimStatus.pending => l10n.referralClaimPending,
      ReferralClaimStatus.error => l10n.referralClaimError,
      ReferralClaimStatus.unauthenticated => l10n.referralSignInRequired,
      _ => null,
    };

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            AppDimensions.spacingXS,
            AppDimensions.screenPadding,
            AppDimensions.spacingXXL,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.promoTitle,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXXL),
              if (_alreadyApplied) ...[
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.promoAlreadyApplied,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingXL),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_result),
                  child: Text(l10n.done),
                ),
              ] else ...[
                TextField(
                  key: const ValueKey('promo-input-field'),
                  controller: _code,
                  enabled: !_service.claiming && !_signingIn,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [LengthLimitingTextInputFormatter(512)],
                  onChanged: (_) => setState(() => _result = null),
                  onSubmitted: (_) {
                    if (_code.text.trim().isNotEmpty) _activate();
                  },
                  decoration: InputDecoration(
                    hintText: l10n.promoFieldTitle,
                    contentPadding: const EdgeInsets.all(
                      AppDimensions.spacingL,
                    ),
                    filled: true,
                    fillColor: colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    errorText: error,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingXL),
                ElevatedButton(
                  key: const ValueKey('promo-activate-button'),
                  onPressed:
                      _code.text.trim().isEmpty ||
                          _service.claiming ||
                          _signingIn
                      ? null
                      : (renewSignIn ? _signIn : _activate),
                  child: Text(
                    _service.claiming
                        ? l10n.referralActivating
                        : (renewSignIn
                              ? l10n.signInCardTitle
                              : l10n.referralActivateButton),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
