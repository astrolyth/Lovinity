import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../theme/theme.dart';
import '../theme/theme_provider.dart';
import '../widgets/lov_kit.dart';

const _key = 'app_lock';

/// "Lock with Face ID": a device setting, so it survives sign-out.
final appLockProvider = NotifierProvider<AppLock, bool>(AppLock.new);

class AppLock extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider)?.getBool(_key) ?? false;

  /// Turning the lock on or off asks for Face ID / the device passcode
  /// first, so someone holding an unlocked phone can't change it.
  Future<bool> set(bool on) async {
    if (!await unlockWithBiometrics('Confirm to change the app lock')) {
      return false;
    }
    state = on;
    await ref.read(sharedPreferencesProvider)?.setBool(_key, on);
    return true;
  }
}

/// Face ID / fingerprint, falling back to the device passcode.
Future<bool> unlockWithBiometrics(String reason) async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) return false;
    return await auth.authenticate(
      localizedReason: reason,
      persistAcrossBackgrounding: true,
    );
  } on PlatformException {
    return false;
  } on LocalAuthException {
    return false;
  }
}

/// Covers the app whenever it comes back from the background while the lock
/// is on, until Face ID succeeds.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  late bool _locked = ref.read(appLockProvider);
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Face ID sheet itself makes the app inactive; only a real trip to
    // the background re-locks.
    if (state == AppLifecycleState.hidden && ref.read(appLockProvider)) {
      setState(() => _locked = true);
    } else if (state == AppLifecycleState.resumed && _locked) {
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final ok = await unlockWithBiometrics('Unlock Lovinity');
    _prompting = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: ColoredBox(
              color: p.bg,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 56, color: p.accent),
                      const SizedBox(height: 18),
                      Text(
                        'Lovinity is locked',
                        style: lovDisplay(context, size: 24),
                      ),
                      const SizedBox(height: 28),
                      LovPrimaryButton(
                        label: 'Unlock',
                        icon: Icons.face_rounded,
                        onPressed: _unlock,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
