import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _getThemeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final profileImageUrl = auth.isAuthenticated
        ? '${auth.serverUrl}/Users/${auth.userId}/Images/Primary'
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 24),
                // Profile Section
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        backgroundImage:
                            profileImageUrl != null && auth.token != null
                            ? CachedNetworkImageProvider(
                                profileImageUrl,
                                headers: {'X-Emby-Token': auth.token!},
                              )
                            : null,
                        child: profileImageUrl == null
                            ? Text(
                                (auth.username ?? 'U')[0].toUpperCase(),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 40,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        auth.username ?? 'User',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                // Settings Options
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  subtitle: Text(_getThemeName(themeProvider.themeMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Choose Appearance'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: const Text('System Default'),
                              trailing: Icon(
                                themeProvider.themeMode == ThemeMode.system
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                              ),
                              onTap: () {
                                themeProvider.setThemeMode(ThemeMode.system);
                                Navigator.of(context).pop();
                              },
                            ),
                            ListTile(
                              title: const Text('Light Mode'),
                              trailing: Icon(
                                themeProvider.themeMode == ThemeMode.light
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                              ),
                              onTap: () {
                                themeProvider.setThemeMode(ThemeMode.light);
                                Navigator.of(context).pop();
                              },
                            ),
                            ListTile(
                              title: const Text('Dark Mode'),
                              trailing: Icon(
                                themeProvider.themeMode == ThemeMode.dark
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                              ),
                              onTap: () {
                                themeProvider.setThemeMode(ThemeMode.dark);
                                Navigator.of(context).pop();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Privacy & Security'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Placeholder
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & Support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Placeholder
                  },
                ),
                const SizedBox(height: 24),
                // Logout Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      auth.logout();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Server Info at the bottom
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Text(
                  'Server Information',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  auth.serverUrl ?? 'Unknown Server',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Finbuk v1.0.0',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
