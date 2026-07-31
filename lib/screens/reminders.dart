import 'package:flutter/material.dart';
import '../collections.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _checkedIds = <String>{};

  void _setChecked(String docId, dynamic docRef, bool checked) {
    setState(() => checked ? _checkedIds.add(docId) : _checkedIds.remove(docId));
    if (!checked) return;
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (_checkedIds.contains(docId)) docRef.update({'status': 1});
    });
  }

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
                  (doc) {
                    final checked = _checkedIds.contains(doc.id);
                    return ListTile(
                      leading: Checkbox(
                        value: checked,
                        onChanged: (value) => _setChecked(doc.id, doc.reference, value ?? false),
                      ),
                      title: Text(doc.data()['summary']),
                      subtitle: Text(doc.data()['condition'] ?? ''),
                      trailing: Chip(label: Text(doc.data()['category'] ?? '')),
                    );
                  },
                )
                .toList(),
          );
        },
      ),
    );
  }
}
