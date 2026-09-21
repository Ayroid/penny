/// App lock: the phone's own fingerprint, face or screen lock in front of
/// Penny.
///
/// Penny never sees a fingerprint or a PIN. The system prompt answers yes or
/// no, and that is all this file keeps.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'penny.dart';

final _auth = LocalAuthentication();

/// Asks the phone who is holding it. False on a cancel, a failure, or a phone
/// with no screen lock set up — never a throw.
///
/// Replaceable so tests can answer without a device.
Future<bool> Function() askPhone = () async {
  try {
    return await _auth.authenticate(localizedReason: 'Unlock Penny');
  } catch (_) {
    return false;
  }
};

/// Whether the phone has anything to unlock with. A phone without a screen
/// lock cannot lock Penny either, and Settings says so instead of trying.
Future<bool> Function() phoneCanLock = () async {
  try {
    return await _auth.isDeviceSupported();
  } catch (_) {
    return false;
  }
};

/// Whether the person has proved it is them since Penny last locked.
/// Outside any widget, so Settings can unlock on the way to turning the lock
/// on, and the shell can lock again when the app comes back.
final unlocked = ValueNotifier(false);

/// True while the system prompt is up. The prompt pauses the app on some
/// phones, and that pause must not count as leaving.
bool get asking => _asking;
bool _asking = false;

/// Asks, and records the answer in [unlocked].
Future<bool> unlock() async {
  if (_asking) return false;
  _asking = true;
  try {
    final ok = await askPhone();
    if (ok) unlocked.value = true;
    return ok;
  } finally {
    _asking = false;
  }
}

/// How long Penny can be away before it asks again. Long enough to share a
/// backup or pick a file to import without being asked twice; short enough
/// that a phone left on a table is locked by the time someone picks it up.
const lockGrace = Duration(seconds: 30);

bool relockAfter(Duration away) => away >= lockGrace;

const _privacy = MethodChannel('penny/privacy');

/// Keeps the ledger out of the recent-apps switcher while the lock is on — a
/// locked app whose thumbnail shows the balance is not locked. Quietly does
/// nothing where there is no Android side to ask, as in tests.
Future<void> hideInRecents(bool hide) async {
  try {
    await _privacy.invokeMethod('hideInRecents', hide);
  } on MissingPluginException {
    // No platform side.
  }
}

/// Over everything while locked, the app kept alive but unpainted beneath it.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: PennyMessage(
          pose: Penny.rest,
          headline: 'Penny is locked',
          body: 'Your money stays private until you unlock.',
          actionLabel: 'Unlock',
          onAction: unlock,
        ),
      ),
    );
  }
}
