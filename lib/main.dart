import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const VideoToolApp());
}

class VideoToolApp extends StatelessWidget {
  const VideoToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ဗီဒီယိုတူးလ်',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
