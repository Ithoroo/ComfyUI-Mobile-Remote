import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads and writes metadata in PNG files — compatible with ComfyUI format.
class PngMetadata {

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Embed a prompt JSON map into PNG bytes as a tEXt chunk.
  /// Returns new PNG bytes with the metadata injected after the IHDR chunk.
  static Uint8List embedPrompt(Uint8List pngBytes, Map<String, dynamic> prompt) {
    try {
      final promptJson = jsonEncode(prompt);
      final chunk = _buildTextChunk('prompt', promptJson);

      // Insert after PNG signature (8 bytes) + IHDR chunk (4+4+13+4 = 25 bytes)
      const insertAt = 8 + 25;
      if (pngBytes.length < insertAt) return pngBytes;

      final result = BytesBuilder();
      result.add(pngBytes.sublist(0, insertAt));
      result.add(chunk);
      result.add(pngBytes.sublist(insertAt));
      return result.toBytes();
    } catch (_) {
      return pngBytes; // return original if anything fails
    }
  }

  /// Build a PNG tEXt chunk: length + 'tEXt' + keyword + \0 + text + CRC
  static Uint8List _buildTextChunk(String keyword, String text) {
    final keyBytes  = latin1.encode(keyword);
    final textBytes = latin1.encode(text);
    final data      = Uint8List(keyBytes.length + 1 + textBytes.length);
    data.setAll(0, keyBytes);
    data[keyBytes.length] = 0; // null separator
    data.setAll(keyBytes.length + 1, textBytes);

    final chunk = BytesBuilder();
    chunk.add(_uint32Bytes(data.length));   // length
    chunk.add(latin1.encode('tEXt'));       // type
    chunk.add(data);                        // data
    chunk.add(_uint32Bytes(_crc32(        // CRC of type + data
      [...latin1.encode('tEXt'), ...data]
    )));
    return chunk.toBytes();
  }

  static Uint8List _uint32Bytes(int v) => Uint8List(4)
    ..[0] = (v >> 24) & 0xff
    ..[1] = (v >> 16) & 0xff
    ..[2] = (v >> 8)  & 0xff
    ..[3] =  v        & 0xff;

  // CRC-32 table-based implementation
  static final List<int> _crcTable = List.generate(256, (n) {
    int c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(List<int> data) {
    var crc = 0xffffffff;
    for (final b in data) {
      crc = _crcTable[(crc ^ b) & 0xff] ^ (crc >> 8);
    }
    return crc ^ 0xffffffff;
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Returns parsed prompt JSON, or null if not found.
  static Future<Map<String, dynamic>?> read(File file) async {
    try {
      final bytes = await file.readAsBytes();
      for (final key in ['prompt', 'workflow']) {
        final text = _extractChunk(bytes, key);
        if (text != null && text.isNotEmpty) {
          try {
            return jsonDecode(text) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _extractChunk(Uint8List bytes, String keyword) {
    int offset = 8;
    while (offset < bytes.length - 12) {
      if (offset + 8 > bytes.length) break;
      final length = _uint32(bytes, offset); offset += 4;
      if (offset + 4 > bytes.length) break;
      final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      offset += 4;
      if (offset + length > bytes.length) break;
      final data = bytes.sublist(offset, offset + length);
      offset += length + 4;

      if (type == 'tEXt') {
        final r = _parseTExt(data, keyword);
        if (r != null) return r;
      } else if (type == 'zTXt') {
        final r = _parseZTxt(data, keyword);
        if (r != null) return r;
      } else if (type == 'iTXt') {
        final r = _parseITxt(data, keyword);
        if (r != null) return r;
      }
      if (type == 'IEND') break;
    }
    return null;
  }

  static String? _parseTExt(Uint8List data, String keyword) {
    final nullIdx = data.indexOf(0);
    if (nullIdx == -1) return null;
    if (latin1.decode(data.sublist(0, nullIdx)) != keyword) return null;
    return latin1.decode(data.sublist(nullIdx + 1));
  }

  static String? _parseZTxt(Uint8List data, String keyword) {
    final nullIdx = data.indexOf(0);
    if (nullIdx == -1 || nullIdx + 2 >= data.length) return null;
    if (latin1.decode(data.sublist(0, nullIdx)) != keyword) return null;
    try {
      final decompressed = ZLibDecoder().convert(data.sublist(nullIdx + 2));
      return utf8.decode(decompressed, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static String? _parseITxt(Uint8List data, String keyword) {
    final nullIdx = data.indexOf(0);
    if (nullIdx == -1) return null;
    if (utf8.decode(data.sublist(0, nullIdx), allowMalformed: true) != keyword) return null;
    int pos = nullIdx + 1;
    if (pos >= data.length) return null;
    final compressionFlag = data[pos++];
    if (pos >= data.length) return null;
    pos++; // compression method
    while (pos < data.length && data[pos] != 0) { pos++; }
    pos++;
    while (pos < data.length && data[pos] != 0) { pos++; }
    pos++;
    if (pos >= data.length) return null;
    final textBytes = data.sublist(pos);
    if (compressionFlag == 1) {
      try {
        return utf8.decode(ZLibDecoder().convert(textBytes), allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    return utf8.decode(textBytes, allowMalformed: true);
  }

  static int _uint32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// Parse ComfyUI API prompt JSON into generation settings.
  /// Uses KSampler node connections to correctly identify positive vs negative.
  static Map<String, dynamic> parsePrompt(Map<String, dynamic> prompt) {
    final settings = <String, dynamic>{};
    final loras = <Map<String, dynamic>>[];

    // First pass: find KSampler, checkpoint, LoRAs, resolution
    String? posNodeId;
    String? negNodeId;

    for (final entry in prompt.entries) {
      final node = entry.value;
      if (node is! Map) continue;
      final classType = node['class_type'] as String? ?? '';
      final inputs = node['inputs'] as Map<String, dynamic>? ?? {};

      if (classType == 'KSampler') {
        final pos = inputs['positive'];
        final neg = inputs['negative'];
        if (pos is List && pos.isNotEmpty) posNodeId = pos[0].toString();
        if (neg is List && neg.isNotEmpty) negNodeId = neg[0].toString();
        settings['steps']     = inputs['steps'];
        settings['cfg']       = inputs['cfg'];
        settings['sampler']   = inputs['sampler_name'];
        settings['scheduler'] = inputs['scheduler'];
        settings['denoise']   = inputs['denoise'];
        final seed = inputs['seed'];
        if (seed != null) {
          settings['seed']       = seed;
          settings['randomSeed'] = false;
        }
      } else if (classType == 'EmptyLatentImage') {
        settings['width']  = inputs['width'];
        settings['height'] = inputs['height'];
      } else if (classType == 'CheckpointLoaderSimple') {
        settings['checkpoint'] = inputs['ckpt_name'];
      } else if (classType == 'LoraLoader') {
        final loraName = inputs['lora_name'];
        if (loraName is String && loraName.isNotEmpty) {
          loras.add({
            'name':     loraName,
            'strength': inputs['strength_model'],
          });
        }
      }
    }

    // Second pass: assign prompts by node ID from KSampler connections
    for (final entry in prompt.entries) {
      final node = entry.value;
      if (node is! Map) continue;
      if (node['class_type'] != 'CLIPTextEncode') continue;
      final inputs = node['inputs'] as Map<String, dynamic>? ?? {};
      final text = inputs['text'];
      if (text is! String || text.isEmpty) continue;

      if (entry.key == posNodeId) {
        settings['positive'] = text;
      } else if (entry.key == negNodeId) {
        settings['negative'] = text;
      }
    }

    for (var i = 0; i < loras.length && i < 4; i++) {
      settings['lora${i + 1}']  = loras[i]['name'];
      settings['lora${i + 1}s'] = loras[i]['strength'];
    }

    return settings;
  }
}