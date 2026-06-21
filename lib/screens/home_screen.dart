import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/settings_service.dart';
import '../services/tuya_service.dart';
import '../services/ssh_service.dart';
import '../services/network_discovery_service.dart';
import 'comfy_screen.dart';
import 'settings_screen.dart';

/// Four possible PC states
enum PcState { offline, booting, pcOnline, comfyReady }

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const HomeScreen({super.key, required this.prefs});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late SettingsService _settings;
  TuyaService? _tuya;
  SshService? _ssh;

  PcState _pcState   = PcState.offline;
  bool _actionBusy   = false;
  String _statusMsg  = '';
  bool _scanning     = false;
  int _scanProgress  = 0;
  int _scanTotal     = 1;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService(widget.prefs);
    debugPrint('[App] isConfigured: ${_settings.isConfigured}');
    debugPrint('[App] comfyUrl: ${_settings.comfyUrl}');
    _initServices();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollStatus());
    _pollStatus();

    // Auto-discover on startup if enabled
    if (_settings.autoDiscovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanNetwork());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _initServices() {
    debugPrint('[App] isConfigured: ${_settings.isConfigured}');
    debugPrint('[App] clientId: ${_settings.tuyaClientId.isEmpty ? "EMPTY" : "set"}');
    debugPrint('[App] comfyUrl: ${_settings.comfyUrl.isEmpty ? "EMPTY" : _settings.comfyUrl}');
    debugPrint('[App] sshHost: ${_settings.sshHost.isEmpty ? "EMPTY" : "set"}');

    if (!_settings.isConfigured) return;

    if (_settings.isTuyaConfigured) {
      _tuya = TuyaService(
        clientId:     _settings.tuyaClientId,
        clientSecret: _settings.tuyaClientSecret,
        deviceId:     _settings.tuyaDeviceId,
        baseUrl:      _settings.tuyaBaseUrl,
      );
    }

    if (_settings.isSshConfigured) {
      _ssh = SshService(
        host:             _settings.sshHost,
        port:             _settings.sshPort,
        username:         _settings.sshUsername,
        password:         _settings.sshPassword,
        isWindows:        _settings.isWindows,
        linuxComfyPath:   _settings.linuxComfyPath,
        linuxPythonCmd:   _settings.linuxPythonCmd,
        linuxGpu:         _settings.linuxGpu,
        windowsComfyPath: _settings.windowsComfyPath,
        windowsInstallType: _settings.windowsInstallType,
        desktopSourcePath: _settings.desktopSourcePath,
        desktopDataPath: _settings.desktopDataPath,
      );
    } else {
      _ssh = null;
    }
  }

  // ── Status polling ─────────────────────────────────────────────────────────
  // 1. Check Tuya plug → if OFF, PC is offline
  // 2. Check SSH reachable → if not, still booting
  // 3. Check ComfyUI → if running, fully ready

  Future<void> _pollStatus() async {
    debugPrint('[App] _pollStatus called');

    try {
      // Step 1: Tuya plug state (skip if not configured)
      if (_tuya != null) {
        final plugOn = await _tuya!.getPlugState();
        debugPrint('[App] plugOn: $plugOn');
        if (!plugOn) {
          if (mounted) setState(() {
            _pcState  = PcState.offline;
            _statusMsg = '';
          });
          return;
        }
      }

      // No SSH configured — just check if ComfyUI responds directly
      if (_ssh == null) {
        final comfyOk = await _checkComfyDirect();
        if (mounted) setState(() {
          _pcState   = comfyOk ? PcState.comfyReady : PcState.offline;
          _statusMsg = comfyOk ? '' : 'ComfyUI not reachable';
        });
        return;
      }

      // Step 2: SSH reachable = Windows is up
      final sshOk = await _ssh!.isReachable();
      debugPrint('[App] sshOk: $sshOk');
      if (!sshOk) {
        if (mounted) setState(() {
          _pcState   = PcState.booting;
          _statusMsg = 'PC is booting...';
        });
        return;
      }

      // Step 3: Is ComfyUI running?
      final comfyOk = await _ssh!.isComfyRunning(_settings.comfyUrl);
      debugPrint('[App] comfyOk: $comfyOk');
      if (mounted) setState(() {
        _pcState   = comfyOk ? PcState.comfyReady : PcState.pcOnline;
        _statusMsg = comfyOk ? '' : 'PC online — ComfyUI not running';
      });
    } catch (e) {
      debugPrint('[App] pollStatus error: $e');
    }
  }

  Future<bool> _checkComfyDirect() async {
    if (_settings.comfyUrl.isEmpty) return false;
    try {
      final res = await http
          .get(Uri.parse('${_settings.comfyUrl}/system_stats'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _powerOn() async {
    if (_tuya == null) return _showSnack('Configure settings first');
    setState(() { _actionBusy = true; _statusMsg = 'Sending power signal...'; });
    try {
      final ok = await _tuya!.setPlugState(true);
      if (ok) {
        setState(() { _pcState = PcState.booting; _statusMsg = 'PC is booting...'; });
      } else {
        _showSnack('Tuya command failed');
      }
    } catch (e) {
      _showSnack('Tuya error: $e');
    } finally {
      setState(() => _actionBusy = false);
    }
  }

  Future<void> _startComfy() async {
    if (_ssh == null) return _showSnack('SSH not configured');
    setState(() { _actionBusy = true; _statusMsg = 'Starting ComfyUI...'; });
    try {
      final ok = await _ssh!.startComfy();
      if (ok) {
        setState(() => _statusMsg = 'ComfyUI starting, please wait...');
        // Give it 10s to start then poll
        await Future.delayed(const Duration(seconds: 10));
        await _pollStatus();
      } else {
        _showSnack('Failed to start ComfyUI');
      }
    } catch (e) {
      _showSnack('SSH error: $e');
    } finally {
      setState(() => _actionBusy = false);
    }
  }

  Future<void> _viewLogs() async {
    if (_ssh == null) return _showSnack('SSH not configured');
    setState(() => _actionBusy = true);
    final logs = await _ssh!.readLogs();
    setState(() => _actionBusy = false);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ComfyUI Logs'),
        content: SingleChildScrollView(
          child: Text(logs, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _shutdown() async {
    if (_ssh == null) return _showSnack('Configure SSH settings first');
    if (_pcState == PcState.offline) return _showSnack('PC is already off');

    final confirmed = await _confirmDialog(
      'Shutdown PC?',
      'This will shut down your PC immediately.',
    );
    if (!confirmed) return;

    setState(() { _actionBusy = true; _statusMsg = 'Sending shutdown command...'; });
    try {
      await _ssh!.shutdownPC();
      setState(() { _pcState = PcState.offline; _statusMsg = 'Shutdown command sent.'; });
    } catch (e) {
      _showSnack('SSH error: $e');
    } finally {
      setState(() => _actionBusy = false);
    }
  }

  void _openComfy() {
    if (_pcState != PcState.comfyReady) {
      _showSnack('ComfyUI is not running yet');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ComfyScreen(url: _settings.comfyUrl)),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(prefs: widget.prefs)),
    );
    _initServices();
    setState(() {});
    _pollStatus();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _resetPc() async {
    final confirmed = await _confirmDialog(
      'Reset PC',
      'This will cut power and restart the PC. Use only if frozen. Continue?',
    );
    if (!confirmed) return;
    setState(() { _actionBusy = true; _statusMsg = 'Cutting power...'; });
    try {
      await _tuya!.setPlugState(false);
      setState(() => _statusMsg = 'Waiting 10 seconds...');
      await Future.delayed(const Duration(seconds: 10));
      setState(() => _statusMsg = 'Restoring power...');
      await _tuya!.setPlugState(true);
      setState(() => _statusMsg = 'PC is booting...');
      _pollStatus();
    } catch (e) {
      _showSnack('Reset failed: $e');
    } finally {
      setState(() => _actionBusy = false);
    }
  }

  Future<void> _scanNetwork() async {
    setState(() { _scanning = true; _scanProgress = 0; _scanTotal = 1; });
    final found = await NetworkDiscoveryService.scan(
      fastMode: _settings.scanMode == 'fast',
      onProgress: (p, t) {
        if (mounted) setState(() { _scanProgress = p; _scanTotal = t; });
      },
    );
    if (!mounted) return;
    setState(() => _scanning = false);

    if (found.isEmpty) {
      _showSnack('No ComfyUI instances found on local network');
      return;
    }

    if (found.length == 1) {
      // Auto-connect if only one found
      await _settings.setComfyUrl(found.first.url);
      await _maybeSetSshHost(found.first);
      _reinitServices();
      _showSnack('Connected to ${found.first.url}'
          '${found.first.hasSsh ? " (SSH detected)" : ""}');
      return;
    }

    // Show picker if multiple found
    final picked = await showDialog<ComfyInstance>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select ComfyUI Instance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: found.map((instance) => ListTile(
            leading: const Icon(Icons.computer),
            title: Text(instance.ip),
            subtitle: Text('Port ${instance.port}'
                '${instance.hasSsh ? " • SSH available" : ""}'),
            onTap: () => Navigator.pop(ctx, instance),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (picked != null) {
      await _settings.setComfyUrl(picked.url);
      await _maybeSetSshHost(picked);
      _reinitServices();
      _showSnack('Connected to ${picked.url}'
          '${picked.hasSsh ? " (SSH detected)" : ""}');
    }
  }

  /// If SSH was detected and enabled and host field is empty, auto-fill it
  Future<void> _maybeSetSshHost(ComfyInstance instance) async {
    if (instance.hasSsh && _settings.sshEnabled && _settings.sshHost.isEmpty) {
      await _settings.setSshHost(instance.ip);
      debugPrint('[App] auto-filled SSH host: ${instance.ip}');
    }
  }

  void _reinitServices() {
    _pollTimer?.cancel();
    _initServices();
    _pollStatus();
  }

  Future<bool> _confirmDialog(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(title.split(' ')[0], style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pcUp = _pcState == PcState.pcOnline || _pcState == PcState.comfyReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ComfyUI Remote'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _actionBusy ? null : _pollStatus,
            tooltip: 'Refresh status',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Status card ────────────────────────────────────────────────
            _StatusCard(state: _pcState),
            const SizedBox(height: 8),
            if (_statusMsg.isNotEmpty)
              Text(_statusMsg, textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 32),

            // ── Network scan (only when auto-discovery enabled) ───────────
            if (_settings.autoDiscovery) ...[
              if (_scanning) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _scanTotal > 0 ? _scanProgress / _scanTotal : null,
                ),
                const SizedBox(height: 4),
                Text('Scanning network... $_scanProgress/$_scanTotal',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _actionBusy ? null : _scanNetwork,
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('Scan for ComfyUI'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],

            // ── Power On (only if Tuya configured) ────────────────────────
            if (_settings.isTuyaConfigured) ...[
              FilledButton.icon(
                onPressed: (_actionBusy || _pcState != PcState.offline) ? null : _powerOn,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Power On'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── SSH detected but needs credentials ─────────────────────────
            if (_settings.sshEnabled && !_settings.isSshConfigured && _settings.sshHost.isNotEmpty) ...[
              Card(
                color: Colors.blue.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'SSH detected at ${_settings.sshHost}. Add username & password in settings to enable PC control.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: _openSettings,
                        child: const Text('Setup'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Start ComfyUI (only if SSH configured) ────────────────────
            if (_settings.isSshConfigured) ...[
              FilledButton.icon(
                onPressed: (_actionBusy || _pcState != PcState.pcOnline) ? null : _startComfy,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start ComfyUI'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Open ComfyUI (always available) ───────────────────────────
            FilledButton.icon(
              onPressed: (_pcState == PcState.comfyReady) ? _openComfy : null,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open ComfyUI'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),

            // ── View Logs / Shutdown (only if SSH configured) ─────────────
            if (_settings.isSshConfigured) ...[
              OutlinedButton.icon(
                onPressed: _actionBusy ? null : _viewLogs,
                icon: const Icon(Icons.article_outlined),
                label: const Text('View ComfyUI Logs'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: (_actionBusy || !pcUp) ? null : _shutdown,
                icon: const Icon(Icons.power_off, color: Colors.red),
                label: const Text('Shutdown PC', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Reset (hard power cycle, only if Tuya configured) ─────────
            if (_settings.isTuyaConfigured) ...[
              OutlinedButton.icon(
                onPressed: _actionBusy ? null : _resetPc,
                icon: const Icon(Icons.restart_alt, color: Colors.orange),
                label: const Text('Reset PC (Hard)', style: TextStyle(color: Colors.orange)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Not configured warning ─────────────────────────────────────
            if (!_settings.isConfigured)
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.warning, color: cs.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'App not configured. Tap ⚙ to enter your ComfyUI URL and SSH settings. Tuya smart plug is optional.',
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Status card widget ─────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final PcState state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, sublabel, color, icon) = switch (state) {
      PcState.comfyReady => ('Ready',   'ComfyUI running',    Colors.green,       Icons.check_circle),
      PcState.pcOnline   => ('PC Online','ComfyUI not running',Colors.orange,      Icons.computer),
      PcState.booting    => ('Booting', 'Please wait...',     Colors.amber,        Icons.hourglass_top),
      PcState.offline    => ('Offline', 'PC is powered off',  Colors.red,          Icons.power_off),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                Text(sublabel,
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}