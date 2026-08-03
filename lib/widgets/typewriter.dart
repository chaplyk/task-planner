import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

const examples = [
  'call mom when I leave office',
  'buy dog food next time I am driving',
  'pay bills when I get home',
  'do laundry tomorrow morning',
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
