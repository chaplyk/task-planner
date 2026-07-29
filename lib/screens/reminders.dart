import 'package:flutter/material.dart';
import '../collections.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
              child: 
                FutureBuilder(
                  future: reminders().get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    return Text(
                      snapshot.data!.docs
                          .map((doc) => 
                            '${doc.data()['summary']} ${doc.data()['triggerType']} (${doc.data()['status']})')
                          .join('\n'),
                    );
                  },
                ),
            ),
    );
  }
}