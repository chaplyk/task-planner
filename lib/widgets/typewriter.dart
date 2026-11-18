import 'package:material_ui/material_ui.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

/// Shown after "Remind me to …": the Home suggestions and the onboarding typewriter.
const examples = [
  'call mom tomorrow',
  'buy milk when I am in grocery store',
  'pay bills when I get home',
  'fuel up the car next time I am driving',
  'water plants every sunday morning',
];

class Typewriter extends StatelessWidget {
  const Typewriter({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 18.0,
          fontFamily: 'Agne',
          color: Theme.of(context).colorScheme.primary,
        ),
        child: AnimatedTextKit(
          repeatForever: true,
          pause: const Duration(milliseconds: 1000),
          animatedTexts: examples
              .map((e) => TypewriterAnimatedText(e, speed: const Duration(milliseconds: 150)))
              .toList(),
        ),
      ),
    );
  }
}
