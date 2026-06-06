import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/comfy_service.dart';
import '../services/generation_prefs.dart';
import '../services/png_metadata.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class GenerateScreen extends StatefulWidget {
  final String comfyUrl;
  const GenerateScreen({super.key, required this.comfyUrl});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  late ComfyService _comfy;

  // ── Form state ─────────────────────────────────────────────────────────────
  String _checkpoint        = 'animagineXL40_v4Opt.safetensors';
  String _positivePrompt    = '';
  String _negativePrompt    = 'lowres, bad anatomy, bad hands, text, error, missing finger, extra digits, fewer digits, cropped, worst quality, low quality, low score, bad score, average score, signature, watermark, username, blurry';
  String _lora1             = '';
  double _lora1Strength     = 0.7;
  String _lora2             = '';
  double _lora2Strength     = 0.7;
  String _lora3             = '';
  double _lora3Strength     = 0.7;
  String _lora4             = '';
  double _lora4Strength     = 0.7;
  int    _width             = 832;
  int    _height            = 1216;
  int    _steps             = 85;
  double _cfg               = 9.0;
  double _denoise           = 0.9;
  bool   _useUpscale        = false;
  String _sampler           = 'euler_ancestral';
  String _scheduler         = 'normal';
  int    _seed              = -1;
  bool   _randomSeed        = true;
  int    _batchCount        = 1;

  // ── Text controllers (needed so prefs can update fields after build) ────────
  late TextEditingController _posCtrl;
  late TextEditingController _negCtrl;
  late TextEditingController _widthCtrl;
  late TextEditingController _heightCtrl;

  // ── UI state ───────────────────────────────────────────────────────────────
  List<String>    _checkpoints  = [];
  List<String>    _loras        = [];
  List<String>    _samplers     = [];
  List<String>    _schedulers   = [];
  bool            _loading      = false;
  String          _status       = '';
  List<Uint8List> _resultImages = [];
  int             _currentImage = 0;

  // ── Queue ──────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _queue = [];
  bool _processingQueue = false;

  // Presets — 'Custom' = user enters their own resolution
  static const _resolutions = {
    'Custom':                          (832, 1216),
    'RedMagic Portrait 608×1344':      (608, 1344),
    'RedMagic Landscape 1344×608':     (1344, 608),
  };

  bool get _isCustomResolution => _selectedResolution == 'Custom';
  String _selectedResolution = 'Custom';

  @override
  void initState() {
    super.initState();
    debugPrint('[Generate] initState comfyUrl: ${widget.comfyUrl}');
    _comfy = ComfyService(widget.comfyUrl);
    _posCtrl = TextEditingController(text: _positivePrompt);
    _negCtrl = TextEditingController(text: _negativePrompt);
    _widthCtrl = TextEditingController(text: _width.toString());
    _heightCtrl = TextEditingController(text: _height.toString());
    _loadOptions();
  }

  Future<void> _loadPrefs() async {
    final p = await GenerationPrefs.load();
    debugPrint('[Generate] _loadPrefs: ${p.keys.toList()}');
    debugPrint('[Generate] _loadPrefs positive: ${p['positive']}');
    debugPrint('[Generate] _loadPrefs lora1: ${p['lora1']}');
    if (p.isEmpty) return;
    setState(() {
      _checkpoint    = p['checkpoint']    ?? _checkpoint;
      _positivePrompt= p['positive']      ?? _positivePrompt;
      _negativePrompt= p['negative']      ?? _negativePrompt;
      // Update text controllers so fields visually refresh
      _posCtrl.text = _positivePrompt;
      _negCtrl.text = _negativePrompt;
      _lora1         = p['lora1']         ?? _lora1;
      _lora1Strength = (p['lora1s']       as num?)?.toDouble() ?? _lora1Strength;
      _lora2         = p['lora2']         ?? _lora2;
      _lora2Strength = (p['lora2s']       as num?)?.toDouble() ?? _lora2Strength;
      _lora3         = p['lora3']         ?? _lora3;
      _lora3Strength = (p['lora3s']       as num?)?.toDouble() ?? _lora3Strength;
      _lora4         = p['lora4']         ?? _lora4;
      _lora4Strength = (p['lora4s']       as num?)?.toDouble() ?? _lora4Strength;
      _denoise       = (p['denoise']      as num?)?.toDouble() ?? _denoise;
      _useUpscale    = p['upscale']       ?? _useUpscale;
      _width         = p['width']         ?? _width;
      _height        = p['height']        ?? _height;
      _selectedResolution = p['resPreset'] ?? _selectedResolution;
      // Update text controllers to reflect loaded values
      _widthCtrl.text  = _width.toString();
      _heightCtrl.text = _height.toString();
      // If loaded from image metadata (no resPreset), force Custom
      if (p['resPreset'] == null && (p['width'] != null || p['height'] != null)) {
        _selectedResolution = 'Custom';
      }
      _steps         = p['steps']         ?? _steps;
      _cfg           = (p['cfg']          as num?)?.toDouble() ?? _cfg;
      _sampler       = p['sampler']       ?? _sampler;
      _scheduler     = p['scheduler']     ?? _scheduler;
      _randomSeed    = p['randomSeed']    ?? _randomSeed;
      _seed          = p['seed']          ?? _seed;
      _batchCount    = p['batch']         ?? _batchCount;
    });
  }

  @override
  void dispose() {
    _posCtrl.dispose();
    _negCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePrefs() async {
    await GenerationPrefs.save({
      'checkpoint':  _checkpoint,
      'positive':    _positivePrompt,
      'negative':    _negativePrompt,
      'lora1':       _lora1,
      'lora1s':      _lora1Strength,
      'lora2':       _lora2,
      'lora2s':      _lora2Strength,
      'lora3':       _lora3,
      'lora3s':      _lora3Strength,
      'lora4':       _lora4,
      'lora4s':      _lora4Strength,
      'denoise':     _denoise,
      'upscale':     _useUpscale,
      'width':       _width,
      'height':      _height,
      'resPreset':   _selectedResolution,
      'steps':       _steps,
      'cfg':         _cfg,
      'sampler':     _sampler,
      'scheduler':   _scheduler,
      'randomSeed':  _randomSeed,
      'seed':        _seed,
      'batch':       _batchCount,
    });
  }

  Future<void> _loadOptions() async {
    debugPrint('[Generate] _loadOptions called, url: ${widget.comfyUrl}');
    setState(() => _status = 'Loading models from ComfyUI...');
    try {
      final results = await Future.wait([
        _comfy.getCheckpoints(),
        _comfy.getLoras(),
        _comfy.getSamplers(),
        _comfy.getSchedulers(),
      ]);
      debugPrint('[Generate] loaded: ${results[0].length} checkpoints, ${results[1].length} loras');
      setState(() {
        _checkpoints = results[0];
        _loras       = ['', ...results[1]];
        _samplers    = results[2];
        _schedulers  = results[3];
        _status      = '';
      });
      // Load prefs AFTER options are available so validation works
      await _loadPrefs();
      setState(() {
        if (!_checkpoints.contains(_checkpoint) && _checkpoints.isNotEmpty) {
          _checkpoint = _checkpoints.first;
        }
        if (!_samplers.contains(_sampler) && _samplers.isNotEmpty) {
          _sampler = _samplers.first;
        }
        if (!_schedulers.contains(_scheduler) && _schedulers.isNotEmpty) {
          _scheduler = _schedulers.first;
        }
        if (!_loras.contains(_lora1)) _lora1 = '';
        if (!_loras.contains(_lora2)) _lora2 = '';
        if (!_loras.contains(_lora3)) _lora3 = '';
        if (!_loras.contains(_lora4)) _lora4 = '';
      });
    } catch (e) {
      debugPrint('[Generate] _loadOptions error: $e');
      setState(() => _status = 'ComfyUI not reachable. Is it running?\n$e');
    }
  }

  void _openFullscreen(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenViewer(
          images: _resultImages,
          initialIndex: index,
        ),
      ),
    );
  }

  // Capture current settings as a snapshot
  Map<String, dynamic> _captureSettings() => {
    'checkpoint':  _checkpoint,
    'positive':    _positivePrompt,
    'negative':    _negativePrompt,
    'width':       _width,
    'height':      _height,
    'steps':       _steps,
    'cfg':         _cfg,
    'sampler':     _sampler,
    'scheduler':   _scheduler,
    'denoise':     _denoise,
    'lora1':       _lora1,   'lora1s': _lora1Strength,
    'lora2':       _lora2,   'lora2s': _lora2Strength,
    'lora3':       _lora3,   'lora3s': _lora3Strength,
    'lora4':       _lora4,   'lora4s': _lora4Strength,
    'upscale':     _useUpscale,
    'batch':       _batchCount,
    'randomSeed':  _randomSeed,
    'seed':        _seed,
  };

  void _addToQueue() {
    if (_positivePrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }
    setState(() => _queue.add(_captureSettings()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to queue (${_queue.length} total)')),
    );
    if (!_processingQueue) _processQueue();
  }

  Future<void> _processQueue() async {
    if (_processingQueue || _queue.isEmpty) return;
    _processingQueue = true;
    await WakelockPlus.enable();

    // Init foreground service
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'comfy_generation',
        channelName: 'ComfyUI Generation',
        channelDescription: 'Keeps generation running in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
      ),
    );

    // Request notification permission and start service
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    await FlutterForegroundTask.startService(
      serviceId: 1000,
      notificationTitle: 'ComfyUI Remote',
      notificationText: 'Starting generation...',
    );

    while (_queue.isNotEmpty) {
      final job = _queue.first;
      final batch = job['batch'] as int;
      final queueLen = _queue.length;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'ComfyUI Remote — Generating',
        notificationText: 'Batch of $batch${queueLen > 1 ? " • ${queueLen - 1} more in queue" : ""}',
      );
      await _runJob(job);
      if (mounted) setState(() => _queue.removeAt(0));
    }

    await FlutterForegroundTask.stopService();
    await WakelockPlus.disable();
    _processingQueue = false;
  }

  Future<void> _runJob(Map<String, dynamic> job) async {
    final checkpoint = job['checkpoint'] as String;
    final positive   = job['positive']   as String;
    final negative   = job['negative']   as String;
    final width      = job['width']      as int;
    final height     = job['height']     as int;
    final steps      = job['steps']      as int;
    final cfg        = (job['cfg']       as num).toDouble();
    final sampler    = job['sampler']    as String;
    final scheduler  = job['scheduler']  as String;
    final denoise    = (job['denoise']   as num).toDouble();
    final lora1      = job['lora1']      as String;
    final lora1s     = (job['lora1s']    as num).toDouble();
    final lora2      = job['lora2']      as String;
    final lora2s     = (job['lora2s']    as num).toDouble();
    final lora3      = job['lora3']      as String;
    final lora3s     = (job['lora3s']    as num).toDouble();
    final lora4      = job['lora4']      as String;
    final lora4s     = (job['lora4s']    as num).toDouble();
    final upscale    = job['upscale']    as bool;
    final batch      = job['batch']      as int;
    final randomSeed = job['randomSeed'] as bool;
    final baseSeed   = job['seed']       as int;

    if (mounted) setState(() { _loading = true; _status = 'Starting...'; _resultImages = []; _currentImage = 0; });

    try {
      final dlDir = Directory('/storage/emulated/0/Download/ComfyUI');
      if (!await dlDir.exists()) await dlDir.create(recursive: true);

      for (int i = 0; i < batch; i++) {
        final qInfo = _queue.length > 1 ? ' (${_queue.length - 1} queued)' : '';
        final seed = randomSeed ? Random().nextInt(2147483647) : baseSeed + i;
        if (mounted) setState(() => _status = 'Image ${i + 1}/$batch — queuing$qInfo');

        final workflow = ComfyService.buildWorkflow(
          checkpoint:     checkpoint,
          positivePrompt: positive,
          negativePrompt: negative,
          width:          width,
          height:         height,
          steps:          steps,
          cfg:            cfg,
          sampler:        sampler,
          scheduler:      scheduler,
          seed:           seed,
          denoise:        denoise,
          lora1Name:      lora1, lora1Strength: lora1s,
          lora2Name:      lora2, lora2Strength: lora2s,
          lora3Name:      lora3, lora3Strength: lora3s,
          lora4Name:      lora4, lora4Strength: lora4s,
          useUpscale:     upscale,
        );

        final promptId = await _comfy.queuePrompt(workflow);
        if (mounted) setState(() => _status = 'Image ${i + 1}/$batch — generating$qInfo');
        await FlutterForegroundTask.updateService(
          notificationTitle: 'ComfyUI Remote — Generating',
          notificationText: 'Image ${i + 1}/$batch${_queue.length > 1 ? " • ${_queue.length - 1} more in queue" : ""}',
        );

        final result = await _comfy.waitForResultMap(promptId);
        final targetFile = result['upscaled'] ?? result['regular'];
        if (targetFile == null) throw Exception('No output image found');
        final imageBytes = await _comfy.getImage(targetFile);
        debugPrint('[Generate] got image: $targetFile (upscaled: ${result['upscaled'] != null})');

        if (mounted) setState(() {
          _resultImages.add(imageBytes);
          _currentImage = _resultImages.length - 1;
        });

        try {
          final file = File('${dlDir.path}/comfy_${DateTime.now().millisecondsSinceEpoch}.png');
          final bytesWithMeta = PngMetadata.embedPrompt(imageBytes, workflow);
          await file.writeAsBytes(bytesWithMeta);
          debugPrint('[Save] saved to ${file.path} (${bytesWithMeta.length} bytes)');
        } catch (e) {
          debugPrint('[Save] failed: $e');
        }
      }
      if (mounted) setState(() => _status = 'Done! $batch image${batch > 1 ? "s" : ""} generated.');
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_positivePrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }
    _savePrefs();
    setState(() => _queue.insert(0, _captureSettings()));
    if (!_processingQueue) _processQueue();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadOptions,
            tooltip: 'Reload options',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Result preview (small, tap to view fullscreen) ─────────────
            if (_resultImages.isNotEmpty) ...[
              GestureDetector(
                onTap: () => _openFullscreen(_currentImage),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Image.memory(
                      _resultImages[_currentImage],
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                ),
              ),
              if (_resultImages.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_currentImage + 1} / ${_resultImages.length} — tap to view',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 8),
            ],

            // ── Status ─────────────────────────────────────────────────────
            if (_status.isNotEmpty) ...[
              Text(_status, textAlign: TextAlign.center,
                  style: TextStyle(color: _status.startsWith('Error') ||
                      _status.startsWith('ComfyUI')
                      ? Colors.red : Colors.grey)),
              const SizedBox(height: 8),
            ],
            if (_status.startsWith('ComfyUI'))
              FilledButton.icon(
                onPressed: _loadOptions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            if (_checkpoints.isEmpty && _status.isEmpty)
              FilledButton.icon(
                onPressed: _loadOptions,
                icon: const Icon(Icons.refresh),
                label: const Text('Load models from ComfyUI'),
              ),
            if (_loading)
              const LinearProgressIndicator(),
            const SizedBox(height: 16),

            // ── Checkpoint ─────────────────────────────────────────────────
            _SectionLabel('Model'),
            if (_checkpoints.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _checkpoints.contains(_checkpoint) ? _checkpoint : null,
                decoration: _inputDec('Checkpoint'),
                isExpanded: true,
                items: _checkpoints.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => _checkpoint = v!),
              ),
            const SizedBox(height: 16),

            // ── Prompts ────────────────────────────────────────────────────
            _SectionLabel('Prompt'),
            TextFormField(
              controller: _posCtrl,
              decoration: _inputDec('Positive prompt'),
              maxLines: 4,
              onChanged: (v) => _positivePrompt = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _negCtrl,
              decoration: _inputDec('Negative prompt'),
              maxLines: 2,
              onChanged: (v) => _negativePrompt = v,
            ),
            const SizedBox(height: 16),

            // ── LoRAs ──────────────────────────────────────────────────────
            _SectionLabel('LoRAs'),
            _LoraRow(
              label: 'LoRA 1',
              loras: _loras,
              value: _lora1,
              strength: _lora1Strength,
              onChanged: (n, s) => setState(() { _lora1 = n; _lora1Strength = s; }),
            ),
            const SizedBox(height: 8),
            _LoraRow(
              label: 'LoRA 2',
              loras: _loras,
              value: _lora2,
              strength: _lora2Strength,
              onChanged: (n, s) => setState(() { _lora2 = n; _lora2Strength = s; }),
            ),
            const SizedBox(height: 8),
            _LoraRow(
              label: 'LoRA 3',
              loras: _loras,
              value: _lora3,
              strength: _lora3Strength,
              onChanged: (n, s) => setState(() { _lora3 = n; _lora3Strength = s; }),
            ),
            const SizedBox(height: 8),
            _LoraRow(
              label: 'LoRA 4',
              loras: _loras,
              value: _lora4,
              strength: _lora4Strength,
              onChanged: (n, s) => setState(() { _lora4 = n; _lora4Strength = s; }),
            ),
            const SizedBox(height: 16),

            // ── Resolution ─────────────────────────────────────────────────
            _SectionLabel('Resolution'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _resolutions.entries.map((e) {
                final selected = _width == e.value.$1 && _height == e.value.$2;
                return ChoiceChip(
                  label: Text(e.key, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _width  = e.value.$1;
                    _height = e.value.$2;
                  }),
                );
              }).toList(),
            ),
            if (_isCustomResolution) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _widthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final val = int.tryParse(v);
                      if (val != null && val > 0) setState(() => _width = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('×', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _heightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final val = int.tryParse(v);
                      if (val != null && val > 0) setState(() => _height = val);
                    },
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 16),

            // ── Sampler ────────────────────────────────────────────────────
            _SectionLabel('Sampler'),
            Row(children: [
              Expanded(
                child: _samplers.isNotEmpty
                    ? DropdownButtonFormField<String>(
                        value: _samplers.contains(_sampler) ? _sampler : null,
                        decoration: _inputDec('Sampler'),
                        isExpanded: true,
                        items: _samplers.map((s) => DropdownMenuItem(
                          value: s, child: Text(s, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _sampler = v!),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _schedulers.isNotEmpty
                    ? DropdownButtonFormField<String>(
                        value: _schedulers.contains(_scheduler) ? _scheduler : null,
                        decoration: _inputDec('Scheduler'),
                        isExpanded: true,
                        items: _schedulers.map((s) => DropdownMenuItem(
                          value: s, child: Text(s, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _scheduler = v!),
                      )
                    : const SizedBox.shrink(),
              ),
            ]),
            const SizedBox(height: 16),

            // ── Steps & CFG ────────────────────────────────────────────────
            _SectionLabel('Steps: $_steps'),
            Slider(
              value: _steps.toDouble(),
              min: 1, max: 200, divisions: 199,
              label: '$_steps',
              onChanged: (v) => setState(() => _steps = v.round()),
            ),
            _SectionLabel('CFG: ${_cfg.toStringAsFixed(1)}'),
            Slider(
              value: _cfg,
              min: 1, max: 20, divisions: 190,
              label: _cfg.toStringAsFixed(1),
              onChanged: (v) => setState(() => _cfg = (v * 10).round() / 10),
            ),
            const SizedBox(height: 8),

            // ── Seed ───────────────────────────────────────────────────────
            _SectionLabel('Seed'),
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: _seed == -1 ? '' : '$_seed',
                  decoration: _inputDec('Seed (empty = random)'),
                  keyboardType: TextInputType.number,
                  enabled: !_randomSeed,
                  onChanged: (v) => _seed = int.tryParse(v) ?? -1,
                ),
              ),
              const SizedBox(width: 8),
              Column(children: [
                const Text('Random', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _randomSeed,
                  onChanged: (v) => setState(() => _randomSeed = v),
                ),
              ]),
            ]),
            const SizedBox(height: 16),

            // ── Upscale ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionLabel('Upscale x2 (RealESRGAN)'),
                Switch(
                  value: _useUpscale,
                  onChanged: (v) => setState(() => _useUpscale = v),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Batch count ────────────────────────────────────────────────
            _SectionLabel('Batch: $_batchCount image${_batchCount > 1 ? "s" : ""}'),
            Slider(
              value: _batchCount.toDouble(),
              min: 1, max: 50, divisions: 49,
              label: '$_batchCount',
              onChanged: (v) => setState(() => _batchCount = v.round()),
            ),
            const SizedBox(height: 8),

            // ── Queue status ───────────────────────────────────────────────
            if (_queue.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_queue.length - 1} job${_queue.length > 2 ? "s" : ""} waiting in queue',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.deepPurple),
                ),
              ),

            // ── Generate button ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _generate,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome),
                    label: Text(_loading ? 'Generating...' : 'Generate'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _addToQueue,
                  icon: const Icon(Icons.queue),
                  label: Text(_queue.isEmpty ? 'Queue' : '+${_queue.length}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label) => InputDecoration(
    labelText: label,
    border: const OutlineInputBorder(),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

// ── Section label ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
  );
}

// ── LoRA row widget ────────────────────────────────────────────────────────

class _LoraRow extends StatefulWidget {
  final String label;
  final List<String> loras;
  final String value;
  final double strength;
  final void Function(String name, double strength) onChanged;

  const _LoraRow({
    required this.label,
    required this.loras,
    required this.value,
    required this.strength,
    required this.onChanged,
  });

  @override
  State<_LoraRow> createState() => _LoraRowState();
}

class _LoraRowState extends State<_LoraRow> {
  late double _strength;

  @override
  void initState() {
    super.initState();
    _strength = widget.strength;
  }

  @override
  Widget build(BuildContext context) {
    // Use widget.value directly so it updates when parent rebuilds
    final currentName = widget.loras.contains(widget.value) ? widget.value : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.loras.isNotEmpty)
          DropdownButtonFormField<String>(
            value: currentName,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            isExpanded: true,
            items: widget.loras.map((l) => DropdownMenuItem(
              value: l,
              child: Text(l.isEmpty ? 'None' : l, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) {
              setState(() => _strength = _strength);
              widget.onChanged(v ?? '', _strength);
            },
          ),
        if (currentName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Text('Strength:', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _strength,
                min: 0, max: 1.5, divisions: 30,
                label: _strength.toStringAsFixed(2),
                onChanged: (v) {
                  setState(() => _strength = (v * 20).round() / 20);
                  widget.onChanged(currentName, _strength);
                },
              ),
            ),
            Text(_strength.toStringAsFixed(2), style: const TextStyle(fontSize: 12)),
          ]),
        ],
      ],
    );
  }
}

// ── Fullscreen swipeable viewer ────────────────────────────────────────────

class _FullscreenViewer extends StatefulWidget {
  final List<Uint8List> images;
  final int initialIndex;
  const _FullscreenViewer({required this.images, required this.initialIndex});

  @override
  State<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends State<_FullscreenViewer> {
  late PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (ctx, i) => GestureDetector(
          onDoubleTap: () {
            // handled by InteractiveViewer reset on double tap
          },
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Image.memory(widget.images[i], fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}