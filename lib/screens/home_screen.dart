import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/settings_service.dart';
import '../services/tuya_service.dart';
import '../services/ssh_service.dart';
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

    _tuya = TuyaService(
      clientId:     _settings.tuyaClientId,
      clientSecret: _settings.tuyaClientSecret,
      deviceId:     _settings.tuyaDeviceId,
      baseUrl:      _settings.tuyaBaseUrl,
    );

    _ssh = SshService(
      host:     _settings.sshHost,
      port:     _settings.sshPort,
      username: _settings.sshUsername,
      password: _settings.sshPassword,
    );
  }

  // ── Status polling ─────────────────────────────────────────────────────────
  // 1. Check Tuya plug → if OFF, PC is offline
  // 2. Check SSH reachable → if not, still booting
  // 3. Check ComfyUI → if running, fully ready

  Future<void> _pollStatus() async {
    if (_ssh == null || _tuya == null) return;
    debugPrint('[App] _pollStatus called');

    try {
      // Step 1: Tuya plug state
      final plugOn = await _tuya!.getPlugState();
      debugPrint('[App] plugOn: $plugOn');
      if (!plugOn) {
        if (mounted) setState(() {
          _pcState  = PcState.offline;
          _statusMsg = '';
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

            // ── Power On ───────────────────────────────────────────────────
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

            // ── Start ComfyUI ──────────────────────────────────────────────
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

            // ── Open ComfyUI ───────────────────────────────────────────────
            FilledButton.icon(
              onPressed: (_pcState == PcState.comfyReady) ? _openComfy : null,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open ComfyUI'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),

            // ── View Logs ──────────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: _actionBusy ? null : _viewLogs,
              icon: const Icon(Icons.article_outlined),
              label: const Text('View ComfyUI Logs'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),

            // ── Shutdown ───────────────────────────────────────────────────
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

            // ── Reset (hard power cycle) ───────────────────────────────────
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
                        'App not configured. Tap ⚙ to enter your Tuya, ComfyUI and SSH settings.',
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