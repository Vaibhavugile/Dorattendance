import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// PermissionService
/// - requestForegroundLocation(): asks for FINE/COARSE location (foreground)
/// - requestBackgroundLocationWithRationale(context): shows a rationale dialog and then requests background permission.
/// - isBackgroundPermissionGranted(): true when permission to access location in background is given.
class PermissionService {
  /// Request foreground (precise) location permissions.
  /// Returns null on success, otherwise returns a human-friendly error string.
  static Future<String?> requestForegroundLocation() async {
    // On iOS this will request locationWhenInUse if configured; on Android this requests fine/coarse.
    final statusFine = await Permission.locationWhenInUse.status;
    if (statusFine.isGranted) return null;

    final result = await Permission.locationWhenInUse.request();
    if (result.isGranted) return null;

    if (result.isPermanentlyDenied) {
      return 'Location permission permanently denied. Please enable it in app settings.';
    }
    return 'Location permission denied.';
  }

  /// Request background location on Android 10+ (and iOS "always" if you want).
  /// Shows a rationale dialog first (call from UI thread). Returns null on success or a message on failure.
  static Future<String?> requestBackgroundLocationWithRationale(BuildContext context) async {
    // Background location is only relevant on Android; on iOS it's a different flow (Info.plist).
    if (!Platform.isAndroid) {
      // For iOS you might request locationAlways via Permission.locationAlways when needed.
      final iosStatus = await Permission.locationAlways.status;
      if (iosStatus.isGranted) return null;
      final iosReq = await Permission.locationAlways.request();
      if (iosReq.isGranted) return null;
      if (iosReq.isPermanentlyDenied) return 'Background location permanently denied. Please enable it in system settings.';
      return 'Background location permission denied.';
    }

    // Android: must already have foreground permission before requesting background.
    final fg = await Permission.locationWhenInUse.status;
    if (!fg.isGranted) {
      final fgErr = await requestForegroundLocation();
      if (fgErr != null) return fgErr;
    }

    // On Android 11+ a second request is required for background location.
    // Show in-app rationale so user understands why it's needed (Play Store policy).
    final doRequest = await showDialog<bool>(
      context: context,
      builder: (_) => RequestBackgroundLocationDialog(),
    );

    if (doRequest != true) {
      return 'User declined to grant background location.';
    }

    // Now request the background permission
    final status = await Permission.locationAlways.request();

    if (status.isGranted) return null;
    if (status.isPermanentlyDenied) return 'Background location permanently denied. Please enable it in app settings.';
    return 'Background location permission denied.';
  }

  /// Quick check
  static Future<bool> isBackgroundPermissionGranted() async {
    if (!Platform.isAndroid) {
      final status = await Permission.locationAlways.status;
      return status.isGranted;
    }
    final status = await Permission.locationAlways.status;
    return status.isGranted;
  }
}

/// Simple rationale dialog explaining why background location is needed.
/// Show this before requesting Permission.locationAlways on Android 11+.
class RequestBackgroundLocationDialog extends StatelessWidget {
  const RequestBackgroundLocationDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Allow background location?'),
      content: const Text(
        'To automatically allow check-ins/check-outs when you are near the shop even if the app is minimized, '
        'we need permission to access your location in the background. '
        'We only use this to verify you are at your assigned branch when performing attendance actions.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Allow')),
      ],
    );
  }
}
