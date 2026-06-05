import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/comfy_service.dart';
import '../services/generation_prefs.dart';
import '../services/png_metadata.dart';

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

  // ── UI state ───────────────────────────────────────────────────────────────
  List<String>    _checkpoints  = [];
  List<String>    _loras        = [];
  List<String>    _samplers     = [];
  List<String>    _schedulers   = [];
  bool            _loading      = false;
  String          _status       = '';
  List<Uint8List> _resultImages = [];
  int             _currentImage = 0;

  // Presets
  static const _resolutions = {
    'Portrait 832×1216':               (832, 1216),
    'Landscape 1216×832':              (1216, 832),
    'Square 1024×1024':                (1024, 1024),
    'Portrait 768×1344':               (768, 1344),
    'RedMagic Portrait 608×1344':      (608, 1344),  // → 1216×2688 after 2x upscale
    'RedMagic Landscape 1344×608':     (1344, 608),  // → 2688×1216 after 2x upscale
  };

  @override
  void initState() {
    super.initState();
    debugPrint('[Generate] initState comfyUrl: ${widget.comfyUrl}');
    _comfy = ComfyService(widget.comfyUrl);
    _posCtrl = TextEditingController(text: _positivePrompt);
    _negCtrl = TextEditingController(text: _negativePrompt);
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

  Future<void> _generate() async {
    if (_positivePrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }

    setState(() { _loading = true; _status = 'Starting batch...'; _resultImages = []; _currentImage = 0; });
    _savePrefs(); // persist settings

    try {
      final dlDir = Directory('/storage/emulated/0/Download/ComfyUI');
      if (!await dlDir.exists()) await dlDir.create(recursive: true);

      for (int i = 0; i < _batchCount; i++) {
        final seed = _randomSeed ? Random().nextInt(2147483647) : _seed + i;
        setState(() => _status = 'Image ${i + 1}/$_batchCount — queuing (seed: $seed)');

        final workflow = ComfyService.buildWorkflow(
          checkpoint:      _checkpoint,
          positivePrompt:  _positivePrompt,
          negativePrompt:  _negativePrompt,
          width:           _width,
          height:          _height,
          steps:           _steps,
          cfg:             _cfg,
          sampler:         _sampler,
          scheduler:       _scheduler,
          seed:            seed,
          denoise:         _denoise,
          lora1Name:       _lora1,
          lora1Strength:   _lora1Strength,
          lora2Name:       _lora2,
          lora2Strength:   _lora2Strength,
          lora3Name:       _lora3,
          lora3Strength:   _lora3Strength,
          lora4Name:       _lora4,
          lora4Strength:   _lora4Strength,
          useUpscale:      _useUpscale,
        );

        final promptId = await _comfy.queuePrompt(workflow);
        setState(() => _status = 'Image ${i + 1}/$_batchCount — generating...');

        final images = await _comfy.waitForResult(promptId);
        final imageBytes = await _comfy.getImage(images.first);

        setState(() {
          _resultImages.add(imageBytes);
          _currentImage = _resultImages.length - 1;
        });

        // Auto-save with embedded metadata
        try {
          final file = File('${dlDir.path}/comfy_${DateTime.now().millisecondsSinceEpoch}.png');
          // Embed the workflow JSON into the PNG so settings can be recovered later
          final bytesWithMeta = PngMetadata.embedPrompt(imageBytes, workflow);
          await file.writeAsBytes(bytesWithMeta);
        } catch (e) {
          debugPrint('[Save] failed: $e');
        }
      }

      setState(() => _status = 'Done! $_batchCount image${_batchCount > 1 ? "s" : ""} generated.');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
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
      body: SingleChildScrollView(
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

            // ── Batch count ────────────────────────────────────────────────
            _SectionLabel('Batch: $_batchCount image${_batchCount > 1 ? "s" : ""}'),
            Slider(
              value: _batchCount.toDouble(),
              min: 1, max: 50, divisions: 49,
              label: '$_batchCount',
              onChanged: (v) => setState(() => _batchCount = v.round()),
            ),
            const SizedBox(height: 8),

            // ── Generate button ────────────────────────────────────────────
            FilledButton.icon(
              onPressed: _loading ? null : _generate,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'Generating...' : 'Generate'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 32),
          ],
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
        itemBuilder: (ctx, i) => InteractiveViewer(
          child: Center(
            child: Image.memory(widget.images[i], fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}