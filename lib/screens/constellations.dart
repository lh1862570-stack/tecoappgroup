import 'package:flutter/material.dart';

class ConstellationsPage extends StatelessWidget {
  const ConstellationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Column(
        children: [
          Text('Constelaciones'),
        ],
      )),
    );
  }
}
