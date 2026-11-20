import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'onboarding_demo.dart';

/// One story per kind of reminder, in the order they play: the scene, and the end of the
/// sentence "Say it once. NagadAI reminds you …".
const tourTypes = [
  (DemoScene.time, 'at the right time.', 'A moment, a date, or a whole afternoon.'),
  (DemoScene.place, 'at the right store.', 'Any grocery store or pharmacy you walk into. No address needed.'),
  (DemoScene.home, 'when you arrive.', 'Home, work, the gym: any place you save.'),
  (DemoScene.leave, 'when you leave.', 'Wherever you are now. It pins the spot and nudges you as you walk away.'),
  (DemoScene.drive, 'when you get moving.', 'As soon as you start driving, cycling or running.'),
  (DemoScene.routine, 'on a routine.', 'Chores and habits that come back, nudged when they’re due.'),
];

/// When each recap notification "arrived", to read like a real day of them.
const _recapTimes = {
  DemoScene.time: '6:00 PM',
  DemoScene.place: '10:14 AM',
  DemoScene.home: '7:32 PM',
  DemoScene.leave: '5:48 PM',
  DemoScene.drive: '8:05 AM',
  DemoScene.routine: 'Sun',
};

/// Story-style tour before sign-in: each kind of reminder plays as one short scene and moves
/// on by itself, with a progress bar per story. Tap or swipe to go faster, hold to pause.
/// It ends on a sign-in page that recaps every notification just shown, above [signInActions].
class OnboardingTour extends StatefulWidget {
  const OnboardingTour({super.key, required this.signInActions, this.onPage, this.onSkip});

  /// The sign-in buttons.
  final Widget signInActions;

  /// Called with each page shown: a story's index, or [tourTypes.length] for sign-in.
  final ValueChanged<int>? onPage;

  /// Called with the story Skip was tapped on.
  final ValueChanged<int>? onSkip;

  @override
  State<OnboardingTour> createState() => _OnboardingTourState();
}

class _OnboardingTourState extends State<OnboardingTour> with SingleTickerProviderStateMixin {
  /// One run of a scene; when it ends, the next story starts.
  late final _story = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && !_reduceMotion) _go(_index + 1);
    });

  int _index = 0;

  bool get _onSignIn => _index == tourTypes.length;
  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Without animations nothing plays by itself: each scene shows its end, Next moves on.
    if (_reduceMotion) {
      _story.value = 1;
    } else if (!_story.isAnimating && !_onSignIn && _story.value == 0) {
      _story.forward();
    }
  }

  @override
  void dispose() {
    _story.dispose();
    super.dispose();
  }

  void _go(int index) {
    final target = index.clamp(0, tourTypes.length);
    if (target == _index && target != 0) return;
    setState(() => _index = target);
    widget.onPage?.call(target);
    if (_onSignIn) {
      _story.stop();
    } else if (_reduceMotion) {
      _story.value = 1;
    } else {
      _story.forward(from: 0);
    }
  }

  void _step(int by) {
    HapticFeedback.selectionClick();
    _go(_index + by);
  }

  void _skip() {
    widget.onSkip?.call(_index);
    _go(tourTypes.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // Back steps through the stories before it leaves the app.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _step(-1);
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
            ),
            child: _onSignIn
                ? _SignInPage(key: const ValueKey('sign-in'), actions: widget.signInActions, onReplay: () => _go(0))
                : _stories(context),
          ),
        ),
      ),
    );
  }

  Widget _stories(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (scene, title, body) = tourTypes[_index];
    return Column(
      key: const ValueKey('stories'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 8, 0),
          child: Row(
            children: [
              Expanded(child: _Progress(story: _story, index: _index)),
              const SizedBox(width: 8),
              TextButton(onPressed: _skip, child: const Text('Skip')),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Like stories: tap the left third to go back, anywhere else to go on.
            onTapUp: (details) {
              final width = context.size?.width ?? 1;
              _step(details.localPosition.dx < width / 3 ? -1 : 1);
            },
            onLongPressStart: (_) => _story.stop(),
            onLongPressEnd: (_) {
              if (!_reduceMotion) _story.forward();
            },
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() > 200) _step(v < 0 ? 1 : -1);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    'Say it once. NagadAI reminds you',
                    style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  _Swap(
                    child: Column(
                      key: ValueKey(_index),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.headlineLarge),
                        const SizedBox(height: 8),
                        // Room for two lines, so the scene doesn't jump between stories.
                        SizedBox(
                          height: 48,
                          child: Text(
                            body,
                            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Center(
                        child: OnboardingDemo(
                          key: ValueKey(scene),
                          scene: scene,
                          animation: _story,
                          // The speech bubble above it takes 84.
                          stageHeight: (box.maxHeight - 100).clamp(150.0, 300.0),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _step(1),
          // As tall as the button this replaced, so the scene keeps its place.
          child: SizedBox(
            height: 76,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Swipe to continue',
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 2),
                // A small nudge in the direction to swipe.
                AnimatedBuilder(
                  animation: _story,
                  builder: (context, child) =>
                      Transform.translate(offset: Offset(3 * sin(_story.value * 2 * pi * 4).abs(), 0), child: child),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades and lifts a story's text in as the last one fades out.
class _Swap extends StatelessWidget {
  const _Swap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A bar per story: done ones full, the current one filling as its scene plays.
class _Progress extends StatelessWidget {
  const _Progress({required this.story, required this.index});

  final Animation<double> story;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: story,
      builder: (context, _) => Row(
        children: [
          for (var i = 0; i < tourTypes.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: i < index ? 1 : (i == index ? story.value : 0),
                  minHeight: 4,
                  color: scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignInPage extends StatelessWidget {
  const _SignInPage({super.key, required this.actions, required this.onReplay});

  final Widget actions;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: TextButton.icon(
            onPressed: onReplay,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Watch again'),
          ),
        ),
        const Expanded(child: _Recap()),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Say it once.\nForget about it.', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 10),
              Text(
                'Your reminders, at the right time, place or moment. Sign in so they stay with you, '
                'even on your next phone.',
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              actions,
            ],
          ),
        ),
      ],
    );
  }
}

/// Every notification from the stories, landing one after another like a day's worth on a
/// lock screen, fading out where they run out of room.
class _Recap extends StatefulWidget {
  const _Recap();

  @override
  State<_Recap> createState() => _RecapState();
}

class _RecapState extends State<_Recap> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (_controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const n = 6;
    return ShaderMask(
      // Fade the bottom of the stack into the page.
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.6, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Column(
                children: [
                  for (var i = 0; i < n; i++)
                    _landing(i, n, tourTypes[i].$1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _landing(int i, int n, DemoScene scene) {
    final start = i / n * 0.6;
    final t = Curves.easeOutCubic.transform(((_controller.value - start) / 0.4).clamp(0.0, 1.0));
    final (emoji, title, body) = demoNotifications[scene]!;
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * -24),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DemoNotificationCard(emoji: emoji, title: title, body: body, time: _recapTimes[scene]!, elevation: 1),
        ),
      ),
    );
  }
}
