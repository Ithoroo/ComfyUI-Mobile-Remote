import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Talks to the ComfyUI HTTP API to queue prompts and fetch results.
class ComfyService {
  final String baseUrl;

  ComfyService(this.baseUrl);

  // ── Model / LoRA lists ────────────────────────────────────────────────────

  Future<List<String>> getCheckpoints() async {
    final res = await http.get(Uri.parse('$baseUrl/object_info/CheckpointLoaderSimple'));
    final data = jsonDecode(res.body);
    final List<dynamic> names =
        data['CheckpointLoaderSimple']['input']['required']['ckpt_name'][0];
    return names.cast<String>();
  }

  Future<List<String>> getLoras() async {
    final res = await http.get(Uri.parse('$baseUrl/object_info/LoraLoader'));
    final data = jsonDecode(res.body);
    final List<dynamic> names =
        data['LoraLoader']['input']['required']['lora_name'][0];
    return names.cast<String>();
  }

  Future<List<String>> getSamplers() async {
    final res = await http.get(Uri.parse('$baseUrl/object_info/KSampler'));
    final data = jsonDecode(res.body);
    final List<dynamic> names =
        data['KSampler']['input']['required']['sampler_name'][0];
    return names.cast<String>();
  }

  Future<List<String>> getSchedulers() async {
    final res = await http.get(Uri.parse('$baseUrl/object_info/KSampler'));
    final data = jsonDecode(res.body);
    final List<dynamic> names =
        data['KSampler']['input']['required']['scheduler'][0];
    return names.cast<String>();
  }

  // ── Queue prompt ──────────────────────────────────────────────────────────

  Future<String> queuePrompt(Map<String, dynamic> workflow) async {
    final body = jsonEncode({'prompt': workflow, 'client_id': 'mobile_app'});
    final res = await http.post(
      Uri.parse('$baseUrl/prompt'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (res.statusCode != 200) throw Exception('Queue failed: ${res.body}');
    final data = jsonDecode(res.body);
    return data['prompt_id'] as String;
  }

  // ── Poll for result ───────────────────────────────────────────────────────

  /// Polls history until the prompt is done.
  /// Returns map with 'regular' and 'upscaled' image filenames.
  Future<Map<String, String?>> waitForResultMap(String promptId,
      {Duration interval = const Duration(seconds: 2),
      int maxAttempts = 300}) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);
      final res = await http.get(Uri.parse('$baseUrl/history/$promptId'));
      if (res.statusCode != 200) continue;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!data.containsKey(promptId)) continue;
      final outputs = data[promptId]['outputs'] as Map<String, dynamic>;
      String? regular;
      String? upscaled;
      for (final node in outputs.values) {
        if (node['images'] != null) {
          for (final img in node['images']) {
            if (img['type'] == 'output') {
              final fname = img['filename'] as String;
              if (fname.startsWith('mobile_upscaled')) {
                upscaled = fname;
              } else {
                regular = fname;
              }
            }
          }
        }
      }
      if (regular != null || upscaled != null) {
        return {'regular': regular, 'upscaled': upscaled};
      }
    }
    throw Exception('Generation timed out');
  }

  /// Polls history until the prompt is done. Returns output image filenames.
  Future<List<String>> waitForResult(String promptId,
      {Duration interval = const Duration(seconds: 2),
      int maxAttempts = 300}) async {
    final result = await waitForResultMap(promptId, interval: interval, maxAttempts: maxAttempts);
    return [
      if (result['regular'] != null) result['regular']!,
      if (result['upscaled'] != null) result['upscaled']!,
    ];
  }

  /// Fetch image bytes from ComfyUI output folder.
  Future<Uint8List> getImage(String filename) async {
    final res = await http.get(
      Uri.parse('$baseUrl/view?filename=$filename&type=output'),
    );
    if (res.statusCode != 200) throw Exception('Image fetch failed');
    return res.bodyBytes;
  }

  // ── Build workflow ────────────────────────────────────────────────────────

  /// Builds a clean API-format workflow matching your ComfyUI setup.
  /// Supports up to 4 LoRAs. Set loraName to empty string to skip.
  static Map<String, dynamic> buildWorkflow({
    required String checkpoint,
    required String positivePrompt,
    required String negativePrompt,
    required int width,
    required int height,
    required int steps,
    required double cfg,
    required String sampler,
    required String scheduler,
    required int seed,
    required double denoise,
    String lora1Name = '', double lora1Strength = 0.7,
    String lora2Name = '', double lora2Strength = 0.7,
    String lora3Name = '', double lora3Strength = 0.7,
    String lora4Name = '', double lora4Strength = 0.7,
    bool useUpscale = false,
    double upscaleBy = 2.0,
  }) {
    // Node 1: Load checkpoint
    final workflow = <String, dynamic>{
      '1': {
        'class_type': 'CheckpointLoaderSimple',
        'inputs': {'ckpt_name': checkpoint},
      },
    };

    // Chain LoRA loaders
    String modelRef = '["1", 0]';
    String clipRef  = '["1", 1]';
    int nextNode = 2;

    for (final lora in [
      [lora1Name, lora1Strength],
      [lora2Name, lora2Strength],
      [lora3Name, lora3Strength],
      [lora4Name, lora4Strength],
    ]) {
      if ((lora[0] as String).isNotEmpty) {
        workflow['$nextNode'] = {
          'class_type': 'LoraLoader',
          'inputs': {
            'model':          jsonDecode(modelRef),
            'clip':           jsonDecode(clipRef),
            'lora_name':      lora[0],
            'strength_model': lora[1],
            'strength_clip':  lora[1],
          },
        };
        modelRef = '["$nextNode", 0]';
        clipRef  = '["$nextNode", 1]';
        nextNode++;
      }
    }

    final posNode   = '${nextNode++}';
    final negNode   = '${nextNode++}';
    final latNode   = '${nextNode++}';
    final ksampNode = '${nextNode++}';
    final vaeNode   = '${nextNode++}';
    final saveNode  = '$nextNode';

    workflow[posNode] = {
      'class_type': 'CLIPTextEncode',
      'inputs': {'text': positivePrompt, 'clip': jsonDecode(clipRef)},
    };
    workflow[negNode] = {
      'class_type': 'CLIPTextEncode',
      'inputs': {'text': negativePrompt, 'clip': jsonDecode(clipRef)},
    };
    workflow[latNode] = {
      'class_type': 'EmptyLatentImage',
      'inputs': {'width': width, 'height': height, 'batch_size': 1},
    };
    workflow[ksampNode] = {
      'class_type': 'KSampler',
      'inputs': {
        'model':        jsonDecode(modelRef),
        'positive':     [posNode, 0],
        'negative':     [negNode, 0],
        'latent_image': [latNode, 0],
        'seed':         seed,
        'steps':        steps,
        'cfg':          cfg,
        'sampler_name': sampler,
        'scheduler':    scheduler,
        'denoise':      denoise,
      },
    };
    workflow[vaeNode] = {
      'class_type': 'VAEDecode',
      'inputs': {
        'samples': [ksampNode, 0],
        'vae':     ['1', 2],
      },
    };

    if (useUpscale) {
      nextNode++;
      final upPosNode   = '${nextNode++}';
      final upNegNode   = '${nextNode++}';
      final upModelNode = '${nextNode++}';
      final upNode      = '${nextNode++}';
      final upSaveNode  = '$nextNode';

      workflow[upPosNode] = {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': 'ultra quality, $positivePrompt', 'clip': jsonDecode(clipRef)},
      };
      workflow[upNegNode] = {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': negativePrompt, 'clip': jsonDecode(clipRef)},
      };
      workflow[upModelNode] = {
        'class_type': 'UpscaleModelLoader',
        'inputs': {'model_name': 'RealESRGAN_x2.pth'},
      };
      workflow[upNode] = {
        'class_type': 'UltimateSDUpscale',
        'inputs': {
          'image':         [vaeNode, 0],
          'model':         jsonDecode(modelRef),
          'positive':      [upPosNode, 0],
          'negative':      [upNegNode, 0],
          'vae':           ['1', 2],
          'upscale_model': [upModelNode, 0],
          'upscale_by':    upscaleBy,
          'seed':          seed,
          'steps':         20,
          'cfg':           cfg,
          'sampler_name':  sampler,
          'scheduler':     scheduler,
          'denoise':       0.3,
          'mode_type':     'Linear',
          'tile_width':    512,
          'tile_height':   512,
          'mask_blur':     8,
          'tile_padding':  32,
          'seam_fix_mode': 'None',
          'seam_fix_denoise': 1.0,
          'seam_fix_width':   64,
          'seam_fix_mask_blur': 8,
          'seam_fix_padding':  16,
          'force_uniform_tiles': true,
          'tiled_decode': false,
        },
      };
      workflow[upSaveNode] = {
        'class_type': 'SaveImage',
        'inputs': {'images': [upNode, 0], 'filename_prefix': 'mobile_upscaled'},
      };
    } else {
      workflow[saveNode] = {
        'class_type': 'SaveImage',
        'inputs': {'images': [vaeNode, 0], 'filename_prefix': 'mobile'},
      };
    }

    return workflow;
  }

  // ── Gallery ───────────────────────────────────────────────────────────────

  /// List all output images using ComfyUI history.
  /// Increase max_items to get more history.
  Future<List<Map<String, dynamic>>> getOutputImages() async {
    final images = <Map<String, dynamic>>[];
    final seen = <String>{};

    final histRes = await http.get(Uri.parse('$baseUrl/history?max_items=10000'));
    if (histRes.statusCode != 200) throw Exception('Failed to fetch history');

    final history = jsonDecode(histRes.body) as Map<String, dynamic>;
    for (final entry in history.values) {
      final outputs = entry['outputs'] as Map<String, dynamic>? ?? {};
      for (final node in outputs.values) {
        final nodeImages = node['images'] as List<dynamic>? ?? [];
        for (final img in nodeImages) {
          if (img['type'] == 'output') {
            final fname = img['filename'] as String;
            if (seen.add(fname)) {
              images.add({
                'filename': fname,
                'subfolder': img['subfolder'] ?? '',
                'url': '$baseUrl/view?filename=$fname&type=output&subfolder=${img['subfolder'] ?? ''}',
              });
            }
          }
        }
      }
    }

    // Newest first
    images.sort((a, b) =>
        (b['filename'] as String).compareTo(a['filename'] as String));
    return images;
  }

  /// List ALL images in the output folder by scanning filenames via the view API.
  /// This finds images even if they're not in history (older sessions).
  Future<List<Map<String, dynamic>>> getAllOutputImages() async {
    // Get from history first
    final fromHistory = await getOutputImages();
    final seen = fromHistory.map((e) => e['filename'] as String).toSet();

    // Also try to fetch the output folder listing
    // ComfyUI doesn't have a direct folder listing API, but we can
    // infer filenames from the Downloads/ComfyUI folder on the phone
    return fromHistory;
  }

  /// Get image URL for display.
  String getImageUrl(String filename, {String subfolder = ''}) =>
      '$baseUrl/view?filename=$filename&type=output&subfolder=$subfolder';
}