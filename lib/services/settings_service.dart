import 'package:shared_preferences/shared_preferences.dart';

/// Wraps SharedPreferences so the rest of the app never touches raw keys.
class SettingsService {
  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  // ── Tuya ──────────────────────────────────────────────────────────────────
  String get tuyaClientId     => _prefs.getString('tuya_client_id')     ?? '';
  String get tuyaClientSecret => _prefs.getString('tuya_client_secret') ?? '';
  String get tuyaDeviceId     => _prefs.getString('tuya_device_id')     ?? '';
  // Region base URL — default EU
  String get tuyaBaseUrl      => _prefs.getString('tuya_base_url')      ?? 'https://openapi.tuyaeu.com';

  Future<void> setTuyaClientId(String v)     => _prefs.setString('tuya_client_id', v);
  Future<void> setTuyaClientSecret(String v) => _prefs.setString('tuya_client_secret', v);
  Future<void> setTuyaDeviceId(String v)     => _prefs.setString('tuya_device_id', v);
  Future<void> setTuyaBaseUrl(String v)      => _prefs.setString('tuya_base_url', v);

  // ── ComfyUI ───────────────────────────────────────────────────────────────
  // Tailscale IP of your PC, e.g. http://100.64.0.1:8188
  String get comfyUrl => _prefs.getString('comfy_url') ?? '';

  Future<void> setComfyUrl(String v) => _prefs.setString('comfy_url', v);

  // ── SSH ───────────────────────────────────────────────────────────────────
  // Usually same Tailscale IP as ComfyUI but without port
  String get sshHost     => _prefs.getString('ssh_host')     ?? '';
  int    get sshPort     => _prefs.getInt('ssh_port')        ?? 22;
  String get sshUsername => _prefs.getString('ssh_username') ?? '';
  String get sshPassword => _prefs.getString('ssh_password') ?? '';

  Future<void> setSshHost(String v)     => _prefs.setString('ssh_host', v);
  Future<void> setSshPort(int v)        => _prefs.setInt('ssh_port', v);
  Future<void> setSshUsername(String v) => _prefs.setString('ssh_username', v);
  Future<void> setSshPassword(String v) => _prefs.setString('ssh_password', v);

  // ── Server OS ─────────────────────────────────────────────────────────────
  String get serverOs => _prefs.getString('server_os') ?? 'windows';
  Future<void> setServerOs(String v) => _prefs.setString('server_os', v);
  bool get isWindows => serverOs == 'windows';
  bool get isLinux   => serverOs == 'linux';

  // ── Discovery ─────────────────────────────────────────────────────────────
  bool get autoDiscovery => _prefs.getBool('auto_discovery') ?? true;
  Future<void> setAutoDiscovery(bool v) => _prefs.setBool('auto_discovery', v);

  // 'fast' = detected subnet only, 'thorough' = all common subnets
  String get scanMode => _prefs.getString('scan_mode') ?? 'fast';
  Future<void> setScanMode(String v) => _prefs.setString('scan_mode', v);
  String get windowsComfyPath    => _prefs.getString('windows_comfy_path') ?? '';
  bool   get windowsCustomPath   => windowsComfyPath.isNotEmpty;
  Future<void> setWindowsComfyPath(String v) => _prefs.setString('windows_comfy_path', v);
  String get linuxComfyPath  => _prefs.getString('linux_comfy_path')  ?? '~/ComfyUI';
  String get linuxPythonCmd  => _prefs.getString('linux_python_cmd')  ?? 'python';
  String get linuxGpu        => _prefs.getString('linux_gpu')         ?? 'nvidia';
  Future<void> setLinuxComfyPath(String v) => _prefs.setString('linux_comfy_path', v);
  Future<void> setLinuxPythonCmd(String v) => _prefs.setString('linux_python_cmd', v);
  Future<void> setLinuxGpu(String v)       => _prefs.setString('linux_gpu', v);
  bool get isNvidia => linuxGpu == 'nvidia';
  bool get isAmd    => linuxGpu == 'amd';
  bool get isCpu    => linuxGpu == 'cpu';
  /// True when the minimum required fields are filled in.
  bool get isConfigured =>
      (comfyUrl.isNotEmpty || autoDiscovery);

  bool get isSshConfigured =>
      sshHost.isNotEmpty && sshUsername.isNotEmpty;

  bool get isTuyaConfigured =>
      tuyaClientId.isNotEmpty &&
      tuyaClientSecret.isNotEmpty &&
      tuyaDeviceId.isNotEmpty;
}