import 'package:flutter/material.dart';

void main() {
  runApp(const SizeDebugApp());
}

class SizeDebugApp extends StatelessWidget {
  const SizeDebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SizeDebugScreen(),
    );
  }
}

class SizeDebugScreen extends StatelessWidget {
  const SizeDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.red,
      body: Center(
        child: Text(
          '${size.width.toInt()} x ${size.height.toInt()}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
