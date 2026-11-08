import 'package:flutter/material.dart';
import 'package:pdd_app/presentation/widgets/inline_load_error.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/referral_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/promo_code_sheet.dart';
import 'package:pdd_app/presentation/widgets/result_share.dart';
import 'package:share_plus/share_plus.dart';

class ReferralModalSheet extends StatefulWidget {
  const ReferralModalSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => const ReferralModalSheet(),
    );
  }

  @override
  State<ReferralModalSheet> createState() => _ReferralModalSheetState();
}

class _ReferralModalSheetState extends State<ReferralModalSheet> {
  final _service = ReferralService.instance;
  final _auth = AuthService.instance;
  late (String?, int, bool) _account;
  bool _signingIn = false;

  (String?, int, bool) get _currentAccount =>
      (_auth.currentUser?.id, _auth.accountRevision, _auth.hasServerSession);

  @override
  void initState() {
    super.initState();
    _account = _currentAccount;
    _service.addListener(_changed);
    _auth.addListener(_authChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _service.getReferralInfo(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_authChanged);
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  void _authChanged() {
    if (_account != _currentAccount) {
      _account = _currentAccount;
      _service.getReferralInfo(forceRefresh: true);
    }
    _changed();
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    FocusScope.of(context).unfocus();
    if (!mounted) return;
    await AuthModalSheet.show(context);
    if (mounted) setState(() => _signingIn = false);
  }

  Future<void> _copy(String value, String message) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!mounted) return;
      HapticFeedbackHelper.select();
      AppToast.show(context, message, type: AppToastType.success);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n.referralCopyError,
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _share(ReferralInfo info) async {
    final l10n = context.l10n;
    final text = l10n.referralShareText(
      info.code,
      info.link,
      info.friendBonusDays,
    );
    final origin = sharePositionOrigin(context);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {}
    if (mounted) await _copy(text, l10n.referralInviteCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final info = _service.info;
    final signedIn = _auth.hasServerSession;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            0,
            AppDimensions.screenPadding,
            20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.referralModalTitle,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.referralRules(
                  info?.inviterBonusDays ?? 2,
                  info?.friendBonusDays ?? 2,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              if (info != null)
                _invitation(context, info)
              else if (!signedIn)
                OutlinedButton(
                  key: const ValueKey('referral-sign-in-button'),
                  onPressed: _signingIn ? null : _signIn,
                  child: Text(l10n.referralSignInButton),
                )
              else if (_service.loading)
                const LinearProgressIndicator()
              else
                InlineLoadError(
                  message: l10n.referralLoadError,
                  action: TextButton.icon(
                    key: const ValueKey('referral-retry-button'),
                    onPressed: () =>
                        _service.getReferralInfo(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.referralRetryButton),
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Text(
                l10n.promoReferralTerms,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('referral-open-promo-button'),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  PromoCodeSheet.show(navigator.context);
                },
                child: Text(l10n.promoTitle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _invitation(BuildContext context, ReferralInfo info) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.referralYourCode,
                        style: text.bodySmall?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      SelectableText(
                        info.code,
                        key: const ValueKey('referral-user-code'),
                        style: text.headlineSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('referral-copy-button'),
                  tooltip: l10n.referralCopyCode,
                  onPressed: () => _copy(info.code, l10n.referralCodeCopied),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              key: const ValueKey('referral-share-button'),
              onPressed: () => _share(info),
              icon: const Icon(Icons.share_outlined),
              label: Text(l10n.referralShareButton),
            ),
            TextButton(
              key: const ValueKey('referral-copy-link-button'),
              onPressed: () => _copy(info.link, l10n.referralLinkCopied),
              child: Text(l10n.referralCopyLink),
            ),
            if (info.invitedCount > 0) ...[
              const Divider(height: 12),
              Text(
                l10n.referralStatsInvited(info.invitedCount),
                style: text.bodyMedium?.copyWith(color: colors.secondaryText),
              ),
              Text(
                l10n.referralStatsDays(info.rewardDays),
                style: text.bodyMedium?.copyWith(color: colors.secondaryText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
