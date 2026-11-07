import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/referral_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _service.getReferralInfo(forceRefresh: true);
    });
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
      _service.getReferralInfo(forceRefresh: true);
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
    setState(() => _result = result);
    if (result.status == ReferralClaimStatus.success) {
      HapticFeedbackHelper.success();
    } else {
      HapticFeedbackHelper.error();
    }
  }

  bool get _claimed => _result?.status == ReferralClaimStatus.success;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final info = _service.info;
    final signedIn = _auth.hasServerSession;
    final renewSignIn = _result?.status == ReferralClaimStatus.unauthenticated;
    final used =
        _claimed ||
        info?.hasUsedReferral == true ||
        _result?.status == ReferralClaimStatus.alreadyClaimed;
    final error = switch (_result?.status) {
      ReferralClaimStatus.invalidCode => l10n.referralErrorInvalid,
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
            0,
            AppDimensions.screenPadding,
            20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.referralModalTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Tooltip(
                    message: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    child: AppChromeIconButton(
                      key: const ValueKey('referral-close-button'),
                      icon: Icons.close_rounded,
                      onTap: () =>
                          Navigator.of(context).pop(_claimed ? true : null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.referralRules(
                  info?.inviterBonusDays ?? 2,
                  info?.friendBonusDays ?? 1,
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
              else ...[
                Text(l10n.referralLoadError, style: theme.textTheme.bodyMedium),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('referral-retry-button'),
                    onPressed: () =>
                        _service.getReferralInfo(forceRefresh: true),
                    child: Text(l10n.referralRetryButton),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              if (used)
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
                          _claimed
                              ? l10n.referralSuccessDays(_result!.daysAdded)
                              : l10n.referralErrorAlreadyUsed,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  l10n.referralEnterCodeTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('referral-input-field'),
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
                    labelText: l10n.referralEnterCodeHint,
                    helperText: l10n.referralCodeOnce,
                    helperMaxLines: 2,
                    errorText: error,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  key: const ValueKey('referral-activate-button'),
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

  Widget _invitation(BuildContext context, ReferralInfo info) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: colors.divider),
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
                      Text(l10n.referralYourCode, style: text.labelLarge),
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
            FilledButton.icon(
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
        ),
      ),
    );
  }
}
