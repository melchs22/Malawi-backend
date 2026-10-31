import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text('Help & Support'),
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'For assistance, please contact support@smartmobilityroadcare.com or call +256 123 456789.\nThank you for using SRS!',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
