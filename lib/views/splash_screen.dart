import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/feed_provider.dart';

/// Shows the studio logo for [duration], then fades into [child].
///
/// The logo is an opaque image on white, so the splash is always white (also in
/// dark mode) and matches the plain white native launch screens: the hand-off
/// from the OS launch screen to this one is invisible.
class SplashGate extends ConsumerStatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 1),
  });

  final Widget child;

  /// How long the logo stays on screen once it is drawn.
  final Duration duration;

  static const logoAsset = 'assets/icon/splash_icon_512x512.png';

  @override
  ConsumerState<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends ConsumerState<SplashGate> {
  static const _logo = AssetImage(SplashGate.logoAsset);

  bool _logoReady = false;
  bool _done = false;
  bool _started = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _start();
  }

  Future<void> _start() async {
    // Start reading the feed now, so it is (nearly) ready when the splash ends.
    ref.read(feedProvider);

    // Decode the logo first and count the second from when it is visible.
    try {
      await precacheImage(_logo, context);
    } catch (_) {
      // A missing logo must never block the app: show it as soon as possible.
    }
    if (!mounted) return;
    setState(() => _logoReady = true);
    _timer = Timer(widget.duration, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _done
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : _Splash(key: const ValueKey('splash'), showLogo: _logoReady),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key, required this.showLogo});

  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide * 0.7;
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: showLogo
            ? Semantics(
                label: 'XP Group Game Studio',
                image: true,
                child: Image(
                  image: const AssetImage(SplashGate.logoAsset),
                  width: side.clamp(0, 360),
                  height: side.clamp(0, 360),
                  fit: BoxFit.contain,
                ),
              )
            : null,
      ),
    );
  }
}
