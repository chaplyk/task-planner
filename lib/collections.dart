import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

DocumentReference<Map<String, dynamic>> userDoc() {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance.collection('users').doc(uid);
}

CollectionReference<Map<String, dynamic>> remindersCollection() {
  return userDoc().collection('reminders');
}

CollectionReference<Map<String, dynamic>> categoriesCollection() {
  return userDoc().collection('categories');
}

CollectionReference<Map<String, dynamic>> locationsCollection() {
  return userDoc().collection('locations');
}
