import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
import '../services/ssh_service.dart';

class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const SettingsScreen({super.key, required this.prefs});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsService _settings;

  // Controllers hold the text field values
  late TextEditingController _tuyaClientId;
  late TextEditingController _tuyaClientSecret;
  late TextEditingController _tuyaDeviceId;
  late TextEditingController _comfyUrl;
  late TextEditingController _sshHost;
  late TextEditingController _sshPort;
  late TextEditingController _sshUsername;
  late TextEditingController _sshPassword;

  String _selectedRegion = 'https://openapi.tuyaeu.com';
  bool _sshPasswordVisible = false;
  bool _testingSSH = false;

  static const _regions = {
    'Europe':        'https://openapi.tuyaeu.com',
    'United States': 'https://openapi.tuyaus.com',
    'China':         'https://openapi.tuyacn.com',
    'India':         'https://openapi.tuyain.com',
  };

  @override
  void initState() {
    super.initState();
    _settings = SettingsService(widget.prefs);

    _tuyaClientId     = TextEditingController(text: _settings.tuyaClientId);
    _tuyaClientSecret = TextEditingController(text: _settings.tuyaClientSecret);
    _tuyaDeviceId     = TextEditingController(text: _settings.tuyaDeviceId);
    _comfyUrl         = TextEditingController(text: _settings.comfyUrl);
    _sshHost          = TextEditingController(text: _settings.sshHost);
    _sshPort          = TextEditingController(text: _settings.sshPort.toString());
    _sshUsername      = TextEditingController(text: _settings.sshUsername);
    _sshPassword      = TextEditingController(text: _settings.sshPassword);
    _selectedRegion   = _settings.tuyaBaseUrl;
  }

  @override
  void dispose() {
    for (final c in [
      _tuyaClientId, _tuyaClientSecret, _tuyaDeviceId,
      _comfyUrl, _sshHost, _sshPort, _sshUsername, _sshPassword,
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    await _settings.setTuyaClientId(_tuyaClientId.text.trim());
    await _settings.setTuyaClientSecret(_tuyaClientSecret.text.trim());
    await _settings.setTuyaDeviceId(_tuyaDeviceId.text.trim());
    await _settings.setTuyaBaseUrl(_selectedRegion);
    await _settings.setComfyUrl(_comfyUrl.text.trim());
    await _settings.setSshHost(_sshHost.text.trim());
    await _settings.setSshPort(int.tryParse(_sshPort.text) ?? 22);
    await _settings.setSshUsername(_sshUsername.text.trim());
    await _settings.setSshPassword(_sshPassword.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved ✓')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testSSH() async {
    setState(() => _testingSSH = true);
    final ssh = SshService(
      host:     _sshHost.text.trim(),
      port:     int.tryParse(_sshPort.text) ?? 22,
      username: _sshUsername.text.trim(),
      password: _sshPassword.text,
    );
    final ok = await ssh.testConnection();
    if (mounted) {
      setState(() => _testingSSH = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'SSH connection successful ✓' : 'SSH connection failed ✗')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Tuya ──────────────────────────────────────────────────────────
          _SectionHeader('Tuya Smart Plug'),
          _hint('Get these from iot.tuya.com → Cloud → your project'),
          const SizedBox(height: 8),
          _field(_tuyaClientId,     'Client ID'),
          _field(_tuyaClientSecret, 'Client Secret', obscure: true),
          _field(_tuyaDeviceId,     'Device ID'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedRegion,
            decoration: const InputDecoration(
              labelText: 'Region',
              border: OutlineInputBorder(),
            ),
            items: _regions.entries.map((e) =>
              DropdownMenuItem(value: e.value, child: Text(e.key)),
            ).toList(),
            onChanged: (v) => setState(() => _selectedRegion = v!),
          ),
          const SizedBox(height: 24),

          // ── ComfyUI ───────────────────────────────────────────────────────
          _SectionHeader('ComfyUI'),
          _hint('Your PC\'s Tailscale IP + ComfyUI port, e.g. http://100.64.0.1:8188'),
          const SizedBox(height: 8),
          _field(_comfyUrl, 'ComfyUI URL',
              hint: 'http://100.x.x.x:8188',
              keyboard: TextInputType.url),
          const SizedBox(height: 24),

          // ── SSH ───────────────────────────────────────────────────────────
          _SectionHeader('SSH (for shutdown)'),
          _hint('Enable OpenSSH Server on Windows: Settings → Apps → Optional Features'),
          const SizedBox(height: 8),
          _field(_sshHost, 'SSH Host (Tailscale IP)', keyboard: TextInputType.url),
          _field(_sshPort, 'SSH Port',
              hint: '22', keyboard: TextInputType.number),
          _field(_sshUsername, 'Windows Username'),
          TextFormField(
            controller: _sshPassword,
            obscureText: !_sshPasswordVisible,
            decoration: InputDecoration(
              labelText: 'Windows Password',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(_sshPasswordVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _sshPasswordVisible = !_sshPasswordVisible),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _testingSSH ? null : _testSSH,
            icon: _testingSSH
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cable),
            label: Text(_testingSSH ? 'Testing...' : 'Test SSH Connection'),
          ),
          const SizedBox(height: 32),

          // ── Save ──────────────────────────────────────────────────────────
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold)),
  );
}
