import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/school_group_route.dart';
import 'package:pdd_app/data/services/school_group_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/school_group_location_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/school_group_location_web.dart';

class SchoolGroupScreen extends StatefulWidget {
  const SchoolGroupScreen({super.key, this.invite = 'my', this.authReturn});
  final String invite;
  final Map<String, String>? authReturn;
  @override
  State<SchoolGroupScreen> createState() => _SchoolGroupScreenState();
}

class _SchoolGroupScreenState extends State<SchoolGroupScreen> {
  final auth = AuthService.instance;
  final code = TextEditingController(), name = TextEditingController();
  late String invite = widget.invite;
  String? owner, error;
  bool ready = false;
  static const pendingKey = 'school_group_invite';
  int generation = 0;
  bool busy = false, agreed = false, processedReturn = false;
  bool enteringCode = false;
  SchoolMembership? membership;

  @override
  void initState() {
    super.initState();
    auth.addListener(_accountChanged);
    unawaited(_restoreInvite());
  }

  Future<void> _restoreInvite() async {
    if (!kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (invite == 'my') {
        invite = SchoolGroupRoute.parse(prefs.getString(pendingKey)) ?? 'my';
      } else {
        await prefs.setString(pendingKey, invite);
        if (!mounted) return;
      }
    } else {
      setSchoolGroupLocation(invite);
    }
    ready = true;
    _accountChanged();
  }

  Future<void> _remember(String value) async {
    if (kIsWeb) {
      setSchoolGroupLocation(value);
    } else {
      final prefs = await SharedPreferences.getInstance();
      if (value == 'my') {
        await prefs.remove(pendingKey);
      } else {
        await prefs.setString(pendingKey, value);
      }
    }
  }

  @override
  void dispose() {
    auth.removeListener(_accountChanged);
    code.dispose();
    name.dispose();
    super.dispose();
  }

  void _accountChanged() {
    final id = auth.hasServerSession ? auth.currentUser?.id : null;
    if (!ready || id == owner) return;
    generation++;
    setState(() {
      owner = id;
      agreed = busy = false;
      membership = null;
      error = null;
      name.text = auth.currentUser?.name ?? '';
    });
    if (id != null) unawaited(_load());
  }

  Future<void> _load() => _request(invite == 'my' ? 'mine' : 'preview', {
    if (invite != 'my') 'invite': invite,
  });

  Future<void> _request(String action, Map<String, String> data) async {
    if (busy || owner == null) return;
    final sequence = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await schoolGroupRequest(action, data);
      if (!mounted || sequence != generation) return;
      setState(() {
        membership = result;
        if (action == 'join' || action == 'leave') {
          invite = 'my';
          unawaited(_remember('my'));
          enteringCode = false;
          agreed = false;
        }
      });
    } on SchoolGroupError catch (e) {
      if (!mounted || sequence != generation) return;
      if (e.status == 401) {
        await auth.signOut();
      } else if (e.status == 409) {
        setState(() {
          busy = false;
          agreed = false;
          membership = null;
        });
        await _load();
        if (mounted &&
            owner != null &&
            sequence + 1 == generation &&
            error == null) {
          setState(() => error = appL10n.studentSchoolConflict);
        }
      } else {
        setState(() {
          if (e.status == 410) {
            membership = null;
            agreed = false;
          }
          error = switch (e.status) {
            400 => appL10n.studentSchoolNameRequired,
            410 => appL10n.studentSchoolUnavailable,
            429 => appL10n.studentSchoolLimit,
            _ => appL10n.authErrorNetwork,
          };
        });
      }
    } catch (_) {
      if (mounted && sequence == generation) {
        setState(() => error = appL10n.authErrorNetwork);
      }
    } finally {
      if (mounted && sequence == generation) setState(() => busy = false);
    }
  }

  void _findGroup() {
    if (busy) return;
    final raw = code.text.trim();
    final key =
        SchoolGroupRoute.parse(raw) ??
        SchoolGroupRoute.fromLink(Uri.tryParse(raw) ?? Uri());
    if (key == null || key == 'my') {
      setState(() => error = appL10n.studentSchoolUnavailable);
      return;
    }
    setState(() {
      invite = key;
      unawaited(_remember(key));
      agreed = false;
      enteringCode = false;
      membership = null;
    });
    _load();
  }

  void _join() {
    if (!agreed || name.text.trim().isEmpty) {
      setState(() => error = appL10n.studentSchoolNameRequired);
      return;
    }
    final state = membership!;
    _request('join', {
      'invite': invite,
      'version': state.version,
      'consentVersion': state.consentVersion!,
      'name': name.text.trim(),
    });
  }

  Future<void> _leave() async {
    final state = membership!, account = owner;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appL10n.studentSchoolLeaveTitle(state.current!.name)),
        content: Text(appL10n.studentSchoolLeaveNote),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(appL10n.studentSchoolLeave),
          ),
        ],
      ),
    );
    if (mounted &&
        accepted == true &&
        account == owner &&
        identical(state, membership)) {
      await _request('leave', {'version': state.version});
    }
  }

  void _enterCode() {
    setState(() {
      enteringCode = true;
      invite = 'my';
      unawaited(_remember('my'));
      error = null;
      agreed = false;
      code.clear();
    });
  }

  Future<void> _study() async {
    if (kIsWeb) {
      await launchUrl(
        Uri.https('pdd-drive.app', '/app/'),
        webOnlyWindowName: '_self',
      );
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Widget _button(String label, VoidCallback? action) => FilledButton(
    onPressed: busy ? null : action,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context), state = membership;
    final invited = state?.invited, current = state?.current;
    final isCandidate = invited != null && invited.id != current?.id;
    final group = isCandidate ? invited : current;
    final signed = owner != null;
    final selectCode =
        signed &&
        (enteringCode || (invite == 'my' && state != null && current == null));
    final title = selectCode || group == null
        ? (invite == 'my' || selectCode
              ? appL10n.studentSchoolTitle
              : appL10n.studentSchoolJoinTitle)
        : group.name;
    return Scaffold(
      appBar: Navigator.of(context).canPop() ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Material(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.asset(
                              'assets/images/app_icon.png',
                              width: 34,
                              height: 34,
                              excludeFromSemantics: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              appL10n.schoolPortalBrand,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (group != null && !selectCode)
                        Text(
                          group.school,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontSize: 30,
                                height: 1.12,
                                letterSpacing: -.7,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (group != null && !selectCode) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${appL10n.studentSchoolTeacher} · ${group.instructor}',
                        ),
                      ],
                      const SizedBox(height: 22),
                      if (!signed)
                        AuthModalSheet(
                          embedded: true,
                          embeddedErrorColor: Theme.of(
                            context,
                          ).colorScheme.error,
                          initialAction:
                              widget.authReturn == null || processedReturn
                              ? null
                              : () {
                                  processedReturn = true;
                                  return auth.completeWebSignIn(
                                    widget.authReturn!,
                                  );
                                },
                        )
                      else if (selectCode) ...[
                        TextField(
                          controller: code,
                          enabled: !busy,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: appL10n.studentSchoolCode,
                            hintText: appL10n.studentSchoolCodeHint,
                          ),
                          onSubmitted: (_) => _findGroup(),
                        ),
                        const SizedBox(height: 16),
                        _button(appL10n.studentSchoolFind, _findGroup),
                      ] else if (isCandidate) ...[
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              appL10n.studentSchoolAccount,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            TextButton(
                              onPressed: busy ? null : auth.signOut,
                              child: Text(appL10n.schoolPortalSwitch),
                            ),
                          ],
                        ),
                        Text(
                          auth.currentUser!.email.isNotEmpty
                              ? auth.currentUser!.email
                              : auth.currentUser!.name,
                          style: TextStyle(
                            fontSize: 16,
                            color: colors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: name,
                          maxLength: 100,
                          enabled: !busy,
                          decoration: InputDecoration(
                            labelText: appL10n.studentSchoolName,
                            counterText: '',
                          ),
                        ),
                        if (current != null) ...[
                          const SizedBox(height: 12),
                          Text(appL10n.studentSchoolTransferNote(current.name)),
                        ],
                        CheckboxListTile(
                          value: agreed,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => agreed = v ?? false),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            appL10n.studentSchoolConsent,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _button(
                          current == null
                              ? appL10n.studentSchoolJoin
                              : appL10n.studentSchoolTransfer,
                          agreed ? _join : null,
                        ),
                      ] else if (current != null) ...[
                        Text(
                          appL10n.studentSchoolJoined,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _button(appL10n.studentSchoolStudy, _study),
                        TextButton(
                          onPressed: busy ? null : _enterCode,
                          child: Text(appL10n.studentSchoolAnother),
                        ),
                        TextButton(
                          onPressed: busy ? null : _leave,
                          child: Text(appL10n.studentSchoolLeave),
                        ),
                      ] else if (!busy && error != null) ...[
                        _button(appL10n.authRetry, _load),
                        TextButton(
                          onPressed: _enterCode,
                          child: Text(appL10n.studentSchoolAnother),
                        ),
                      ],
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
