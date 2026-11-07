import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/referral_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:share_plus/share_plus.dart';

class ReferralModalSheet extends StatefulWidget {
  const ReferralModalSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedbackHelper.tap();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => const ReferralModalSheet(),
    );
  }

  @override
  State<ReferralModalSheet> createState() => _ReferralModalSheetState();
}

class _ReferralModalSheetState extends State<ReferralModalSheet> {
  final TextEditingController _codeController = TextEditingController();
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    ReferralService.instance.addListener(_onServiceUpdate);
    AuthService.instance.addListener(_onServiceUpdate);
    if (AuthService.instance.isAuthenticated) {
      ReferralService.instance.getReferralInfo();
    }
  }

  @override
  void dispose() {
    ReferralService.instance.removeListener(_onServiceUpdate);
    AuthService.instance.removeListener(_onServiceUpdate);
    _codeController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _handleCopy(String code) async {
    HapticFeedbackHelper.select();
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    AppToast.show(
      context,
      appL10n.referralCodeCopied,
      type: AppToastType.success,
    );
  }

  Future<void> _handleShare(ReferralInfo info) async {
    HapticFeedbackHelper.tap();
    final text = appL10n.referralShareText(info.code, info.link);
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? Rect.fromCenter(
            center: box.localToGlobal(box.size.center(Offset.zero)),
            width: 1,
            height: 1,
          )
        : null;
    try {
      final res = await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      );
      if (res.status == ShareResultStatus.unavailable) {
        await _handleCopy(text);
      }
    } catch (_) {
      await _handleCopy(text);
    }
  }

  Future<void> _handleClaim() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    if (!AuthService.instance.isAuthenticated) {
      await ReferralService.instance.savePendingCode(code);
      if (!mounted) return;
      await AuthModalSheet.show(context);
      return;
    }

    setState(() => _claiming = true);
    HapticFeedbackHelper.select();

    final result = await ReferralService.instance.claimCode(code);
    if (!mounted) return;
    setState(() => _claiming = false);

    switch (result.status) {
      case ReferralClaimStatus.success:
        HapticFeedbackHelper.success();
        _codeController.clear();
        AppToast.show(
          context,
          appL10n.referralSuccessClaimed,
          type: AppToastType.success,
        );
      case ReferralClaimStatus.selfReferral:
        HapticFeedbackHelper.error();
        AppToast.show(
          context,
          appL10n.referralErrorSelf,
          type: AppToastType.error,
        );
      case ReferralClaimStatus.alreadyClaimed:
        HapticFeedbackHelper.error();
        AppToast.show(
          context,
          appL10n.referralErrorAlreadyUsed,
          type: AppToastType.error,
        );
      case ReferralClaimStatus.notFound:
      case ReferralClaimStatus.invalidCode:
        HapticFeedbackHelper.error();
        AppToast.show(
          context,
          appL10n.referralErrorNotFound,
          type: AppToastType.error,
        );
      case ReferralClaimStatus.unauthenticated:
        await AuthModalSheet.show(context);
      case ReferralClaimStatus.error:
        HapticFeedbackHelper.error();
        AppToast.show(
          context,
          appL10n.referralErrorNotFound,
          type: AppToastType.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAuthenticated = AuthService.instance.isAuthenticated;
    final info = ReferralService.instance.info;
    final loading = ReferralService.instance.loading && info == null;

    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusExtraLarge),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        12,
        AppDimensions.screenPadding,
        MediaQuery.of(context).viewPadding.bottom + 20 + bottomPadding,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colors.primaryText.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Close Button
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  key: const ValueKey('referral-close-button'),
                  icon: Icon(Icons.close_rounded, color: colors.secondaryText),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              // Top Gift Icon Badge
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2BC280), Color(0xFF0065FD)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2BC280).withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.card_giftcard_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                appL10n.referralModalTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                  fontFamily: 'Onest',
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                appL10n.referralBannerDescription,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: colors.secondaryText,
                  fontFamily: 'Onest',
                ),
              ),
              const SizedBox(height: 20),

              if (loading) ...[
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ] else if (!isAuthenticated) ...[
                _buildSignInCard(colors),
              ] else if (info != null) ...[
                _buildCodeCard(colors, isDark, info),
                const SizedBox(height: 16),
                _buildStatsRow(colors, isDark, info),
              ],

              const SizedBox(height: 20),
              _buildFriendCodeSection(colors, isDark, info),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignInCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 36,
            color: colors.secondaryText,
          ),
          const SizedBox(height: 8),
          Text(
            appL10n.referralSignInRequired,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: colors.secondaryText,
              fontFamily: 'Onest',
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            key: const ValueKey('referral-sign-in-button'),
            onPressed: () => AuthModalSheet.show(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
            ),
            child: Text(
              appL10n.referralSignInButton,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(
    AppThemeColors colors,
    bool isDark,
    ReferralInfo info,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2633) : const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(
          color: colors.accent.withValues(alpha: isDark ? 0.3 : 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appL10n.referralYourCode,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SelectableText(
                info.code,
                key: const ValueKey('referral-user-code'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: colors.accent,
                  fontFamily: 'Onest',
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('referral-copy-button'),
                icon: const Icon(Icons.copy_rounded, size: 20),
                color: colors.accent,
                tooltip: appL10n.referralCopyCode,
                onPressed: () => _handleCopy(info.code),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const ValueKey('referral-share-button'),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: Text(
              appL10n.referralShareButton,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
            ),
            onPressed: () => _handleShare(info),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
    AppThemeColors colors,
    bool isDark,
    ReferralInfo info,
  ) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
              border: Border.all(color: colors.divider.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 20,
                  color: colors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appL10n.referralStatsInvited(info.invitedCount),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
              border: Border.all(color: colors.divider.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.stars_rounded,
                  size: 20,
                  color: Color(0xFF2BC280),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appL10n.referralStatsDays(info.rewardDays),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFriendCodeSection(
    AppThemeColors colors,
    bool isDark,
    ReferralInfo? info,
  ) {
    if (info != null && info.hasUsedReferral) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF162B1D) : const Color(0xFFE8F8F0),
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          border: Border.all(
            color: const Color(0xFF2BC280).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF2BC280),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                appL10n.referralAlreadyClaimed(info.referralCodeUsed ?? ''),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2BC280),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appL10n.referralEnterCodeTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('referral-input-field'),
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    LengthLimitingTextInputFormatter(16),
                  ],
                  decoration: InputDecoration(
                    hintText: appL10n.referralEnterCodeHint,
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: colors.secondaryText.withValues(alpha: 0.6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: colors.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                      borderSide: BorderSide(
                        color: colors.divider.withValues(alpha: 0.6),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                      borderSide: BorderSide(
                        color: colors.divider.withValues(alpha: 0.6),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                      borderSide: BorderSide(color: colors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: const ValueKey('referral-activate-button'),
                onPressed: _claiming ? null : _handleClaim,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2BC280),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(100, 48),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDimensions.buttonRadius,
                    ),
                  ),
                ),
                child: _claiming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        appL10n.referralActivateButton,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
