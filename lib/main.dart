import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/generate_screen.dart';
import 'screens/gallery_screen.dart';
import 'services/settings_service.dart';
import 'services/generation_prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ComfyRemoteApp(prefs: prefs));
}

class ComfyRemoteApp extends StatelessWidget {
  final SharedPreferences prefs;
  const ComfyRemoteApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ComfyUI Remote',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: MainShell(prefs: prefs),
    );
  }
}

class MainShell extends StatefulWidget {
  final SharedPreferences prefs;
  const MainShell({super.key, required this.prefs});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  int _galleryKey = 0;
  int _generateKey = 0;
  late SettingsService _settings;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService(widget.prefs);
  }

  Future<void> _onLoadSettings(Map<String, dynamic> settings) async {
    await GenerationPrefs.save(settings);
    setState(() {
      _tab = 1;
      _generateKey++;
    });
  }

  void _onTabChanged(int index) {
    setState(() {
      _tab = index;
      if (index == 2) _galleryKey++;
    });
  }

  // iPad: screen width >= 600 uses side rail instead of bottom nav
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  @override
  Widget build(BuildContext context) {
    final comfyUrl = _settings.comfyUrl;
    final isTablet = _isTablet(context);

    final screens = [
      HomeScreen(prefs: widget.prefs),
      comfyUrl.isNotEmpty
          ? GenerateScreen(key: ValueKey(_generateKey), comfyUrl: comfyUrl)
          : const _NotConfigured(),
      comfyUrl.isNotEmpty
          ? GalleryScreen(
              key: ValueKey(_galleryKey),
              comfyUrl: comfyUrl,
              onLoadSettings: _onLoadSettings,
            )
          : const _NotConfigured(),
    ];

    if (isTablet) {
      return Scaffold(
        body: Row(
          children: [
            // ── Side navigation rail ─────────────────────────────────────
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: _onTabChanged,
              labelType: NavigationRailLabelType.all,
              minWidth: 88,
              backgroundColor: Theme.of(context).colorScheme.surface,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: Text('Generate'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.photo_library_outlined),
                  selectedIcon: Icon(Icons.photo_library),
                  label: Text('Gallery'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            // ── Main content ─────────────────────────────────────────────
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: screens,
              ),
            ),
          ],
        ),
      );
    }

    // ── Phone layout — bottom navigation ──────────────────────────────────
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _onTabChanged,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Generate',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Gallery',
          ),
        ],
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Configure ComfyUI URL in Settings first'),
  );
}