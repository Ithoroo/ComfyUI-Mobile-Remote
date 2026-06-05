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

  // ── Helpers ───────────────────────────────────────────────────────────────
  /// True when the minimum required fields are filled in.
  bool get isConfigured =>
      tuyaClientId.isNotEmpty &&
      tuyaClientSecret.isNotEmpty &&
      tuyaDeviceId.isNotEmpty &&
      comfyUrl.isNotEmpty &&
      sshHost.isNotEmpty &&
      sshUsername.isNotEmpty;
}
