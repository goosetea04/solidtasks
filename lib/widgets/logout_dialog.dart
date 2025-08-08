import 'package:flutter/material.dart';

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
          onPressed: () => Navigator.of(context).pop(true),
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

// Helper function to show the logout dialog
Future<bool?> showLogoutDialog(BuildContext context, {bool useBuiltInPopup = false}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => LogoutDialog(useBuiltInPopup: useBuiltInPopup),
  );
}