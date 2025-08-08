import 'package:flutter/material.dart';
import '../services/pod_service.dart';

class LogoutDialog extends StatelessWidget {
  final bool useBuiltInPopup;
  
  const LogoutDialog({
    Key? key,
    this.useBuiltInPopup = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Logout'),
      content: const Text(
        'Are you sure you want to logout?\n\nThis will clear your session and you\'ll need to login again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            // Close the dialog first
            Navigator.of(context).pop(true);
            
            try {
              if (useBuiltInPopup) {
                // Use the built-in popup logout
                await PodService.logoutWithPopup(context);
              } else {
                // Use the custom logout with navigation
                await PodService.logout(context);
              }
            } catch (e) {
              // Show error if logout fails
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Logout failed: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Logout'),
        ),
      ],
    );
  }
}

// Helper function to show the logout dialog and handle the logout process
Future<void> showLogoutDialog(BuildContext context, {bool useBuiltInPopup = false}) async {
  final bool? shouldLogout = await showDialog<bool>(
    context: context,
    builder: (context) => LogoutDialog(useBuiltInPopup: useBuiltInPopup),
  );
  
  // The dialog now handles the logout process internally
  // No need to return a value since navigation is handled in the dialog
}