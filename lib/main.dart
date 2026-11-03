import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/keys_screen.dart';
import 'screens/tools_screen.dart';

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
      home: const MainNav(),
    );
  }
}

class MainNav extends StatefulWidget {
  const MainNav({super.key});

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  int _index = 0;

  static const _pages = [
    HomeScreen(),
    ToolsScreen(),
    KeysScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home),
            label: 'ပင်မ',
          ),
          NavigationDestination(
            icon: Icon(Icons.construction),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.key),
            label: 'Keys',
          ),
        ],
      ),
    );
  }
}
