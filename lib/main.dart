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
  int _generateKey = 0; // increment to force GenerateScreen to reload prefs
  late SettingsService _settings;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService(widget.prefs);
  }

  Future<void> _onLoadSettings(Map<String, dynamic> settings) async {
    await GenerationPrefs.save(settings);
    setState(() {
      _tab = 1; // switch to Generate tab
      _generateKey++; // force GenerateScreen to reload prefs
    });
  }

  void _onTabChanged(int index) {
    setState(() {
      _tab = index;
      if (index == 2) _galleryKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final comfyUrl = _settings.comfyUrl;

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
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
        ],
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