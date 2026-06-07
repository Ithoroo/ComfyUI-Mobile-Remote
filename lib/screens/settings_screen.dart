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
  late TextEditingController _linuxComfyPath;
  late TextEditingController _linuxPythonCmd;
  late TextEditingController _winComfyPath;

  String _selectedRegion = 'https://openapi.tuyaeu.com';
  bool _winCustomPath = false;
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
    _linuxComfyPath   = TextEditingController(text: _settings.linuxComfyPath);
    _linuxPythonCmd   = TextEditingController(text: _settings.linuxPythonCmd);
    _winComfyPath     = TextEditingController(text: _settings.windowsComfyPath);
    _selectedRegion   = _settings.tuyaBaseUrl;
    _winCustomPath    = _settings.windowsCustomPath;
  }

  @override
  void dispose() {
    for (final c in [
      _tuyaClientId, _tuyaClientSecret, _tuyaDeviceId,
      _comfyUrl, _sshHost, _sshPort, _sshUsername, _sshPassword,
      _linuxComfyPath, _linuxPythonCmd, _winComfyPath,
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
    await _settings.setLinuxComfyPath(_linuxComfyPath.text.trim());
    await _settings.setLinuxPythonCmd(_linuxPythonCmd.text.trim());
    await _settings.setWindowsComfyPath(
        _winCustomPath ? _winComfyPath.text.trim() : '');

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
      host:      _sshHost.text.trim(),
      port:      int.tryParse(_sshPort.text) ?? 22,
      username:  _sshUsername.text.trim(),
      password:  _sshPassword.text,
      isWindows: _settings.isWindows,
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
          _SectionHeader('SSH'),
          const SizedBox(height: 8),

          // Server OS selector
          Row(
            children: [
              const Text('Server OS:', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 16),
              ChoiceChip(
                label: const Text('Windows'),
                selected: _settings.isWindows,
                onSelected: (_) async {
                  await _settings.setServerOs('windows');
                  setState(() {});
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Linux'),
                selected: _settings.isLinux,
                onSelected: (_) async {
                  await _settings.setServerOs('linux');
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _hint(_settings.isWindows
              ? 'Enable OpenSSH Server: Settings → Apps → Optional Features'
              : 'Make sure SSH is enabled and ComfyUI is installed at ~/ComfyUI'),
          const SizedBox(height: 8),
          _field(_sshHost, 'SSH Host (Tailscale IP)', keyboard: TextInputType.url),
          _field(_sshPort, 'SSH Port', hint: '22', keyboard: TextInputType.number),
          _field(_sshUsername, _settings.isWindows ? 'Windows Username' : 'Linux Username'),
          TextFormField(
            controller: _sshPassword,
            obscureText: !_sshPasswordVisible,
            decoration: InputDecoration(
              labelText: _settings.isWindows ? 'Windows Password' : 'Linux Password',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(_sshPasswordVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _sshPasswordVisible = !_sshPasswordVisible),
              ),
            ),
          ),
          if (_settings.isWindows) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('ComfyUI Path:', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('Default'),
                  selected: !_winCustomPath,
                  onSelected: (_) => setState(() => _winCustomPath = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: _winCustomPath,
                  onSelected: (_) => setState(() => _winCustomPath = true),
                ),
              ],
            ),
            if (_winCustomPath) ...[
              const SizedBox(height: 8),
              _field(_winComfyPath, 'ComfyUI Path',
                  hint: r'C:\custom\path\ComfyUI.exe'),
            ] else
              _hint(r'Default: %LOCALAPPDATA%\Programs\ComfyUI\ComfyUI.exe'),
          ],
          if (_settings.isLinux) ...[
            const SizedBox(height: 12),
            _field(_linuxComfyPath, 'ComfyUI Path', hint: '~/ComfyUI'),
            _field(_linuxPythonCmd, 'Python Command', hint: 'python'),            const SizedBox(height: 8),
            const Text('GPU:', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Row(children: [
              ChoiceChip(
                label: const Text('NVIDIA'),
                selected: _settings.isNvidia,
                onSelected: (_) async {
                  await _settings.setLinuxGpu('nvidia');
                  setState(() {});
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('AMD (ROCm)'),
                selected: _settings.isAmd,
                onSelected: (_) async {
                  await _settings.setLinuxGpu('amd');
                  setState(() {});
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('CPU'),
                selected: _settings.isCpu,
                onSelected: (_) async {
                  await _settings.setLinuxGpu('cpu');
                  setState(() {});
                },
              ),
            ]),
            if (_settings.isAmd)
              _hint('Uses HSA_OVERRIDE_GFX_VERSION=11.0.0 — change if needed for your GPU'),
          ],
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