import 'dart:convert';
import 'dart:io';

/// Saves and loads generation settings to a JSON file on the device.
/// Stored at /storage/emulated/0/Download/ComfyUI/settings.json
class GenerationPrefs {
  static const _path = '/storage/emulated/0/Download/ComfyUI/settings.json';

  /// In-memory handoff for settings loaded from an image — survives the
  /// widget rebuild timing that a file round-trip or constructor arg can miss.
  static Map<String, dynamic>? pending;

  static Future<Map<String, dynamic>> load() async {
    try {
      final file = File(_path);
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      try { await File(_path).delete(); } catch (_) {}
      return {};
    }
  }

  static Future<void> save(Map<String, dynamic> prefs) async {
    try {
      final dir = Directory('/storage/emulated/0/Download/ComfyUI');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(_path);
      await file.writeAsString(jsonEncode(prefs));
    } catch (e) {
      // Fail silently — don't crash if storage isn't available
    }
  }
}