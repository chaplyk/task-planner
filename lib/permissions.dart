import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

Future<void> requestBackgroundLocationPermission(BuildContext context) async {
  // if background location permission is already granted, do nothing
  if (await Geolocator.checkPermission() == LocationPermission.always) return;

  // else request background location permission
  await Geolocator.requestPermission();

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Background location'),
      content: const Text(
        'To send location-based reminders, the app requires background location access. \n'
        'Please select "Allow all the time" in Permissions -> Location settings.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Geolocator.openAppSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
}
