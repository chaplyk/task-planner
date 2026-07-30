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
      body: StreamBuilder(
        stream: reminders().where('status', isEqualTo: 0).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: snapshot.data!.docs
                .map(
                  (doc) => CheckboxListTile(
                    value: false,
                    title: Text(doc.data()['summary']),
                    subtitle: Text(doc.data()['condition'] ?? ''),
                    onChanged: (_) => doc.reference.update({'status': 1}),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}
