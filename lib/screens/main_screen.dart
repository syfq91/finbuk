import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/floating_mini_player.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isOffline = false;
  bool _isCheckingConnection = false;
  Timer? _connectivityTimer;

  final List<Widget> _screens = [
    const HomeScreen(),
    const LibraryScreen(),
    const DownloadsScreen(),
  ];

  final List<String> _titles = ['Home', 'Library', 'Downloads'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConnectionStatus();
    });
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectionStatus(),
    );
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectionStatus() async {
    if (_isCheckingConnection || !mounted) return;
    _isCheckingConnection = true;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final serverUrl = auth.serverUrl;
      if (serverUrl == null) {
        if (mounted) setState(() => _isOffline = false);
        return;
      }
      final isConnected = await _checkConnection(serverUrl);
      if (mounted) {
        setState(() => _isOffline = !isConnected);
      }
    } finally {
      _isCheckingConnection = false;
    }
  }

  Widget? _buildOfflineBanner() {
    if (!_isOffline) return null;
    return Container(
      color: Colors.orange.shade800,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: const Text(
        'Offline Mode - Using Cached Data',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final token = auth.token;
    final serverUrl = auth.serverUrl;
    final userId = auth.userId;
    final profileImageUrl =
        (serverUrl != null && userId != null && token != null)
        ? '$serverUrl/Users/$userId/Images/Primary'
        : null;

    final appBar = AppBar(
      title: Text(_titles[_selectedIndex]),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {},
          tooltip: 'Search',
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const SettingsScreen(),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: profileImageUrl != null && token != null
                  ? NetworkImage(
                      profileImageUrl,
                      headers: {'X-Emby-Token': token},
                    )
                  : null,
              child: profileImageUrl == null
                  ? Text(
                      (auth.username ?? 'U')[0].toUpperCase(),
                      style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          return Scaffold(
            appBar: appBar,
            bottomSheet: _buildOfflineBanner(),
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.library_books_outlined),
                      selectedIcon: Icon(Icons.library_books),
                      label: Text('Library'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download),
                      label: Text('Downloads'),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _screens[_selectedIndex]),
                      const FloatingMiniPlayer(),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          return Scaffold(
            appBar: appBar,
            bottomSheet: _buildOfflineBanner(),
            body: Column(
              children: [
                Expanded(child: _screens[_selectedIndex]),
                const FloatingMiniPlayer(),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.download_outlined),
                  selectedIcon: Icon(Icons.download),
                  label: 'Downloads',
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Future<bool> _checkConnection(String url) async {
    try {
      final uri = Uri.parse(url);
      final result = await InternetAddress.lookup(
        uri.host,
      ).timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
