import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

/// The onboarding demo: short scenes, one per kind of trigger, each ending with the
/// reminder's notification sliding in: walking up to a grocery store, getting into a car
/// and driving off, pinning where you stand and walking away, a weekly routine running out, walking up
/// to home, and a clock ticking to 6 PM. Given a [scene] and an [animation] that runs
/// 0..1, it plays just that scene, driven from outside.
class OnboardingDemo extends StatefulWidget {
  const OnboardingDemo({super.key, this.scene, this.animation, this.stageHeight = 210})
    : assert((scene == null) == (animation == null), 'A scene comes with the animation that drives it');

  /// The one scene to show; null plays them all in turn.
  final DemoScene? scene;

  /// Drives [scene] through one run.
  final Animation<double>? animation;

  final double stageHeight;

  @override
  State<OnboardingDemo> createState() => _OnboardingDemoState();
}

/// In the order they play.
enum DemoScene { place, drive, leave, routine, home, time }

const _said = {
  DemoScene.place: 'Buy milk when I’m at a grocery store',
  DemoScene.leave: 'Grab my umbrella when I leave here',
  DemoScene.drive: 'Fuel up the car next time I drive',
  DemoScene.routine: 'Water the plants every week',
  DemoScene.home: 'Pay bills when I get home',
  DemoScene.time: 'Call mom at 6 PM',
};

/// The notification each scene ends with: emoji, title, body.
const demoNotifications = {
  DemoScene.place: ('🥛', 'Buy milk', 'You’re at FreshMart'),
  DemoScene.leave: ('☂️', 'Grab your umbrella', 'You just left'),
  DemoScene.drive: ('⛽', 'Fuel up the car', 'You started driving'),
  DemoScene.routine: ('🪴', 'Water the plants', 'Time for this week’s watering'),
  DemoScene.home: ('💳', 'Pay bills', 'You’re home'),
  DemoScene.time: ('📞', 'Call mom', 'It’s 6:00 PM'),
};

/// When the notification starts sliding in, as a fraction of a scene.
const _notifyAt = 0.7;

/// 0..1 progress of [t] between [from] and [to].
double _seg(double t, double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

class _OnboardingDemoState extends State<OnboardingDemo> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.scene != null) return;
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      setState(() => _index = (_index + 1) % DemoScene.values.length);
      _controller.forward(from: 0);
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene ?? DemoScene.values[_index];
    final animation = widget.animation ?? _controller;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final raw = animation.value;
        // Without animations: each scene's end state, notification shown.
        final t = reduceMotion ? 0.95 : raw;
        // Fade in at the start of a scene and out at its end.
        final opacity = reduceMotion ? 1.0 : min(_seg(raw, 0, 0.06), 1 - _seg(raw, 0.94, 1));
        // The stage's card stays put; what's in it fades.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room for two lines, so a longer sentence doesn't push the scene down.
            SizedBox(
              height: 72,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Opacity(opacity: opacity, child: _SpeechBubble(text: _said[scene]!)),
              ),
            ),
            const SizedBox(height: 12),
            _Stage(scene: scene, t: t, opacity: opacity, height: widget.stageHeight),
          ],
        );
      },
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 18, color: scheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '“$text”',
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The scene's picture, its caption, and the notification over the top.
class _Stage extends StatelessWidget {
  const _Stage({required this.scene, required this.t, required this.opacity, required this.height});

  final DemoScene scene;
  final double t;
  final double opacity;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(28)),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          return Opacity(
            opacity: opacity,
            child: Stack(
              children: [
                ...switch (scene) {
                  DemoScene.place => _placeScene(context, size, 'FreshMart', Icons.storefront_rounded),
                  DemoScene.home => _placeScene(context, size, 'Home', Icons.home_rounded),
                  DemoScene.leave => _leaveScene(context, size),
                  DemoScene.drive => _driveScene(context, size),
                  DemoScene.routine => _routineScene(context, size),
                  DemoScene.time => _timeScene(context, size),
                },
                _NotificationBanner(scene: scene, t: t),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _caption(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Positioned(
      left: 16,
      bottom: 12,
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  // ---------------------------------------------------------------- 6 PM

  List<Widget> _timeScene(BuildContext context, Size size) {
    final scheme = Theme.of(context).colorScheme;
    // 5:00 -> 6:00 in twelve five-minute ticks, each one snapping into place.
    final run = _seg(t, 0.08, 0.62) * 12;
    final step = run.floor();
    final frac = run - step;
    final snap = frac < 0.35 ? Curves.easeOutBack.transform(frac / 0.35) : 1.0;
    final minutes = min(60.0, (step + snap) * 5);
    final minuteAngle = minutes / 60 * 2 * pi;
    final hourAngle = (5 + minutes / 60) / 12 * 2 * pi;
    // It rings at 6.
    final ring = _seg(t, 0.62, _notifyAt + 0.04);
    final shake = ring > 0 && ring < 1 ? sin(ring * pi * 10) * 0.12 * (1 - ring) : 0.0;
    final shown = min(60, step * 5);
    final label = shown >= 60 ? '6:00 PM' : '5:${shown.toString().padLeft(2, '0')} PM';

    const dial = 112.0;
    return [
      Positioned(
        left: (size.width - dial) / 2,
        top: (size.height - dial) / 2 + 6,
        child: Transform.rotate(
          angle: shake,
          child: SizedBox(
            width: dial,
            height: dial,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 4),
                  ),
                ),
                for (var i = 0; i < 12; i++)
                  Transform.rotate(
                    angle: i / 12 * 2 * pi,
                    child: Align(
                      alignment: const Alignment(0, -0.82),
                      child: Container(width: 3, height: i % 3 == 0 ? 10 : 6, color: scheme.outline),
                    ),
                  ),
                _Hand(angle: hourAngle, length: 28, width: 5, color: scheme.onSurface),
                _Hand(angle: minuteAngle, length: 40, width: 3, color: scheme.primary),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
              ],
            ),
          ),
        ),
      ),
      _caption(context, label),
    ];
  }

  // ---------------------------------------------------------------- grocery store

  /// Walking up to a place (a store of the kind asked for, or a saved place) named [name].
  List<Widget> _placeScene(BuildContext context, Size size, String name, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final store = Offset(size.width * 0.74, size.height * 0.6);
    const zone = 52.0;
    final walk = Curves.easeInOut.transform(_seg(t, 0.08, 0.66));
    final start = Offset(28, size.height * 0.6);
    final end = Offset(store.dx - 34, store.dy); // inside the zone, just short of the door
    final person = Offset.lerp(start, end, walk)!;
    final bob = walk > 0 && walk < 1 ? sin(t * 70).abs() * 3 : 0.0;
    final inside = (person - store).distance < zone;
    // The zone lights up and pulses once the person is inside it.
    final pulse = inside ? 1 + 0.1 * sin(_seg(t, 0.6, 1) * pi * 4) : 1.0;
    final meters = ((1 - walk) * 450 + 10).round();

    return [
      _street(scheme, store.dy + 24),
      _zone(scheme, store, zone * pulse, lit: inside),
      _placeIcon(scheme, store, icon),
      _walker(scheme, person, bob),
      _caption(context, inside ? 'Arrived at $name' : '$name · $meters m away'),
    ];
  }

  // ---------------------------------------------------------------- leaving here

  /// "When I leave here": the phone finds where it is, pins that spot, draws a zone around
  /// it, and the reminder fires once the person walks out of it.
  List<Widget> _leaveScene(BuildContext context, Size size) {
    final scheme = Theme.of(context).colorScheme;
    final spot = Offset(size.width * 0.28, size.height * 0.6);
    const zone = 52.0;
    // Finding the position: two location pings ripple out.
    final ping = _seg(t, 0.02, 0.2);
    // The pin drops onto the spot, then the zone grows around it.
    final drop = Curves.bounceOut.transform(_seg(t, 0.16, 0.3));
    final grow = Curves.easeOutBack.transform(_seg(t, 0.28, 0.42));
    final walk = Curves.easeInOut.transform(_seg(t, 0.44, 0.74));
    final person = Offset.lerp(Offset(spot.dx + 22, spot.dy), Offset(size.width - 34, spot.dy), walk)!;
    final bob = walk > 0 && walk < 1 ? sin(t * 70).abs() * 3 : 0.0;
    final away = (person - spot).distance;
    final inside = away < zone;
    // Flashes as the person crosses its edge.
    final flash = grow < 1 ? 0.0 : (1 - (away - zone).abs() / 24).clamp(0.0, 1.0);

    final caption = t < 0.16
        ? 'Finding where you are…'
        : t < 0.28
        ? 'Pinned this spot'
        : walk == 0
        ? 'Zone set around you'
        : inside
        ? 'Walking away'
        : 'Left the zone';

    return [
      _street(scheme, spot.dy + 24),
      for (final delay in [0.0, 0.4])
        if (ping > delay && ping < 1) _ping(scheme, spot, ((ping - delay) / 0.6).clamp(0.0, 1.0)),
      if (grow > 0) _zone(scheme, spot, zone * grow * (1 + 0.12 * flash), lit: inside || flash > 0),
      if (drop > 0)
        Positioned(
          left: spot.dx - 18,
          top: spot.dy - 36 - (1 - drop) * 70,
          child: Opacity(
            opacity: _seg(t, 0.16, 0.2),
            child: Icon(Icons.location_on_rounded, size: 36, color: scheme.primary),
          ),
        ),
      _walker(scheme, person, bob),
      _caption(context, caption),
    ];
  }

  /// A ring spreading out from [center] and fading, like a location fix being taken.
  Widget _ping(ColorScheme scheme, Offset center, double p) {
    final radius = 8 + p * 60;
    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary.withValues(alpha: 0.6 * (1 - p)), width: 2),
        ),
      ),
    );
  }

  Widget _street(ColorScheme scheme, double top) => Positioned(
        left: 0,
        right: 0,
        top: top,
        child: Container(height: 2, color: scheme.outlineVariant),
      );

  /// The circle around a place, like a geofence; [lit] while the person is inside.
  Widget _zone(ColorScheme scheme, Offset center, double radius, {required bool lit}) => Positioned(
        left: center.dx - radius,
        top: center.dy - radius,
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary.withValues(alpha: lit ? 0.22 : 0.08),
            border: Border.all(color: scheme.primary.withValues(alpha: lit ? 0.9 : 0.35), width: 2),
          ),
        ),
      );

  Widget _placeIcon(ColorScheme scheme, Offset center, IconData icon) => Positioned(
        left: center.dx - 22,
        top: center.dy - 22,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
          child: Icon(icon, color: scheme.onPrimary, size: 24),
        ),
      );

  Widget _walker(ColorScheme scheme, Offset feet, double bob) => Positioned(
        left: feet.dx - 18,
        top: feet.dy - 40 - bob,
        child: Icon(Icons.directions_walk_rounded, size: 36, color: scheme.onSurface),
      );

  // ---------------------------------------------------------------- weekly routine

  List<Widget> _routineScene(BuildContext context, Size size) {
    final scheme = Theme.of(context).colorScheme;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // Like a routine card: the ring is the share of the week left, emptying day by day.
    final week = _seg(t, 0.08, 0.64);
    final day = min(6, (week * 7).floor());
    final due = week >= 1;
    const ring = 112.0;
    return [
      Positioned(
        left: (size.width - ring) / 2,
        top: (size.height - ring) / 2 + 6,
        child: SizedBox(
          width: ring,
          height: ring,
          child: CustomPaint(
            painter: _RingPainter(
              share: 1 - week,
              track: scheme.surfaceContainerHighest,
              arc: due ? scheme.error : scheme.primary,
            ),
            child: Center(
              child: Transform.scale(
                // A little nudge when it's due.
                scale: 1 + 0.15 * sin(_seg(t, 0.64, _notifyAt) * pi),
                child: Icon(Icons.yard_rounded, size: 48, color: due ? scheme.error : scheme.primary),
              ),
            ),
          ),
        ),
      ),
      _caption(context, due ? 'Sunday · due' : days[day]),
    ];
  }

  // ---------------------------------------------------------------- driving

  List<Widget> _driveScene(BuildContext context, Size size) {
    final scheme = Theme.of(context).colorScheme;
    final roadTop = size.height - 72;
    final carX = size.width * 0.36;
    // Walk to the car, get in, then drive: the world scrolls past the car.
    final walk = Curves.easeInOut.transform(_seg(t, 0.06, 0.28));
    final getIn = _seg(t, 0.28, 0.36);
    final drive = Curves.easeIn.transform(_seg(t, 0.36, 1));
    final distance = drive * size.width * 2.2;
    final rumble = drive > 0 ? sin(t * 90) * 1.2 : 0.0;
    final personX = lerpDouble(10, carX + 6, walk)!;

    return [
      // Trees going by.
      for (var i = 0; i < 3; i++)
        Positioned(
          left: (i * (size.width + 60) / 3 + size.width * 0.15 - distance) % (size.width + 60) - 30,
          top: roadTop - 46,
          child: Icon(Icons.park_rounded, size: 34, color: scheme.tertiary.withValues(alpha: 0.6)),
        ),
      // The road, with lane dashes moving.
      Positioned(
        left: 0,
        right: 0,
        top: roadTop,
        child: Container(
          height: 44,
          color: scheme.surfaceContainerHighest,
          child: CustomPaint(painter: _LanePainter(offset: distance, color: scheme.outline)),
        ),
      ),
      Positioned(
        left: carX,
        top: roadTop - 34 + rumble,
        child: Transform.scale(
          scale: 1 + 0.06 * sin(getIn * pi), // a little bounce as the door shuts
          child: Icon(Icons.directions_car_filled_rounded, size: 60, color: scheme.primary),
        ),
      ),
      if (getIn < 1)
        Positioned(
          left: personX,
          top: roadTop - 40 - (walk > 0 && walk < 1 ? sin(t * 70).abs() * 3 : 0),
          child: Opacity(
            opacity: 1 - getIn,
            child: Icon(Icons.directions_walk_rounded, size: 36, color: scheme.onSurface),
          ),
        ),
      _caption(context, drive > 0 ? 'Driving' : 'Getting into the car'),
    ];
  }
}

class _Hand extends StatelessWidget {
  const _Hand({required this.angle, required this.length, required this.width, required this.color});

  final double angle;
  final double length;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Transform.translate(
        offset: Offset(0, -length / 2),
        child: Container(
          width: width,
          height: length,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(width)),
        ),
      ),
    );
  }
}

class _LanePainter extends CustomPainter {
  _LanePainter({required this.offset, required this.color});

  final double offset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 22.0, gap = 18.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    for (var x = -(offset % (dash + gap)); x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) => old.offset != offset || old.color != color;
}

/// A phone notification sliding down over the scene.
class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({required this.scene, required this.t});

  final DemoScene scene;
  final double t;

  @override
  Widget build(BuildContext context) {
    final shown = Curves.easeOutBack.transform(_seg(t, _notifyAt, _notifyAt + 0.1));
    if (shown == 0) return const SizedBox.shrink();
    final (emoji, title, body) = demoNotifications[scene]!;
    return Positioned(
      left: 12,
      right: 12,
      top: lerpDouble(-80, 12, shown),
      child: DemoNotificationCard(emoji: emoji, title: title, body: body),
    );
  }
}

/// A phone notification from the app, as the demo draws it.
class DemoNotificationCard extends StatelessWidget {
  const DemoNotificationCard({super.key, required this.emoji, required this.title, required this.body, this.time = 'now', this.elevation = 6});

  final String emoji;
  final String title;
  final String body;
  final String time;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      elevation: elevation,
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NagadAI · $time', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(body, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The routine card's ring, simplified: the share of the cycle left, in the alert colour
/// and full once it's due.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.share, required this.track, required this.arc});

  final double share;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.09;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    Paint paint(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawArc(rect, 0, 2 * pi, false, paint(track));
    final sweep = share <= 0 ? 2 * pi : 2 * pi * share;
    canvas.drawArc(rect, -pi / 2, sweep, false, paint(arc));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.share != share || old.track != track || old.arc != arc;
}
