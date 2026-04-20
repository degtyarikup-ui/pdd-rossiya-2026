import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseAvailableProvider = Provider<bool>((ref) => true);

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

class GuestModeController extends StateNotifier<bool> {
  GuestModeController(this._ref)
    : super(_ref.read(progressDataSourceProvider).getGuestMode());

  final Ref _ref;

  Future<void> enterGuestMode() async {
    state = true;
    await _ref.read(progressDataSourceProvider).setGuestMode(true);
  }

  Future<void> exitGuestMode() async {
    state = false;
    await _ref.read(progressDataSourceProvider).setGuestMode(false);
  }
}

final guestModeProvider = StateNotifierProvider<GuestModeController, bool>((
  ref,
) {
  return GuestModeController(ref);
});

final authStateProvider = StreamProvider<User?>((ref) {
  if (!ref.watch(supabaseAvailableProvider)) {
    return Stream<User?>.value(null);
  }
  return Supabase.instance.client.auth.onAuthStateChange.map(
    (event) => event.session?.user,
  );
});

final currentUserProvider = Provider<User?>((ref) {
  if (!ref.watch(supabaseAvailableProvider)) {
    return null;
  }
  final authState = ref.watch(authStateProvider);
  return authState.asData?.value ?? Supabase.instance.client.auth.currentUser;
});

final isAuthorizedProvider = Provider<bool>((ref) {
  final isGuestMode = ref.watch(guestModeProvider);
  final currentUser = ref.watch(currentUserProvider);
  return !isGuestMode && currentUser != null;
});

