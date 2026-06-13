import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../services/comfy_service.dart';
import '../services/png_metadata.dart';
import '../services/generation_prefs.dart';

class GalleryScreen extends StatefulWidget {
  final String comfyUrl;
  final Future<void> Function(Map<String, dynamic>)? onLoadSettings;
  const GalleryScreen({super.key, required this.comfyUrl, this.onLoadSettings});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late ComfyService _comfy;

  List<File> _localImages = [];
  List<Map<String, dynamic>> _remoteImages = [];

  bool _loading = true;
  String _error = '';
  bool _showLocal = true;
  bool _selectMode = false;
  final Set<int> _selected = {};

  static const _localDir = '/storage/emulated/0/Download/ComfyUI';

  @override
  void initState() {
    super.initState();
    _comfy = ComfyService(widget.comfyUrl);
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() { _loading = true; _error = ''; });
    // Load local first — fast, no network needed
    await _loadLocal();
    setState(() => _loading = false);
    // Load remote in background with timeout — don't block UI
    _loadRemote().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    ).catchError((_) {});
  }

  Future<void> _loadLocal() async {
    try {
      // Request storage/media permission (needed to read images from previous installs)
      if (Platform.isAndroid) {
        final photos = await Permission.photos.status;
        final storage = await Permission.storage.status;
        if (!photos.isGranted && !storage.isGranted) {
          // Android 13+ uses photos, older uses storage
          await Permission.photos.request();
          await Permission.storage.request();
        }
      }

      final dir = Directory(_localDir);
      if (!await dir.exists()) return;
      final files = await dir
          .list()
          .where((f) => f is File &&
              (f.path.endsWith('.png') || f.path.endsWith('.jpg') || f.path.endsWith('.webp')))
          .cast<File>()
          .toList();
      // Sort newest first by modified date
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      setState(() => _localImages = files);
    } catch (e) {
      debugPrint('[Gallery] _loadLocal error: $e');
    }
  }

  Future<void> _loadRemote() async {
    try {
      final images = await _comfy.getOutputImages();
      images.sort((a, b) {
        final aNum = int.tryParse(RegExp(r'(\d+)_\.').firstMatch(a['filename'] as String)?.group(1) ?? '0') ?? 0;
        final bNum = int.tryParse(RegExp(r'(\d+)_\.').firstMatch(b['filename'] as String)?.group(1) ?? '0') ?? 0;
        return bNum.compareTo(aNum);
      });
      // Check all URLs in parallel - much faster than sequential
      final results = await Future.wait(
        images.map((img) async {
          try {
            final res = await http.head(Uri.parse(img['url'] as String))
                .timeout(const Duration(seconds: 5));
            return res.statusCode == 200 ? img : null;
          } catch (_) {
            return null;
          }
        }),
      );
      final valid = results.whereType<Map<String, dynamic>>().toList();
      debugPrint('[Gallery] remote: ${images.length} total, ${valid.length} valid');
      if (mounted) setState(() => _remoteImages = valid);
    } catch (e) {
      debugPrint('[Gallery] _loadRemote error: $e');
    }
  }

  Future<void> _saveRemoteImage(Map<String, dynamic> img) async {
    try {
      final res = await http.get(Uri.parse(img['url'] as String));
      final dlDir = Directory(_localDir);
      if (!await dlDir.exists()) await dlDir.create(recursive: true);
      final fname = img['filename'] as String;
      final file = File('$_localDir/$fname');
      await file.writeAsBytes(res.bodyBytes);
      await _loadLocal(); // refresh local list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Downloads/ComfyUI ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete image?'),
        content: const Text('This will remove it from your device permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;
    try {
      await file.delete();
      await _loadLocal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  void _openLocalFullscreen(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LocalFullscreenGallery(
          files: _localImages,
          initialIndex: index,
          onLoadSettings: widget.onLoadSettings,
          onDelete: (file) async {
            Navigator.of(context).pop();
            await _deleteImage(file);
          },
        ),
      ),
    );
  }

  void _openRemoteFullscreen(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RemoteFullscreenGallery(
          images: _remoteImages,
          initialIndex: index,
          onSave: _saveRemoteImage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localCount = _localImages.length;
    final remoteCount = _remoteImages.length;

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selected.length} selected')
            : Text(_showLocal ? 'Local ($localCount)' : 'ComfyUI history ($remoteCount)'),
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() { _selectMode = false; _selected.clear(); }),
              )
            : null,
        actions: _selectMode ? [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
            onPressed: () => setState(() {
              if (_selected.length == _localImages.length) {
                _selected.clear();
                _selectMode = false;
              } else {
                _selected.addAll(List.generate(_localImages.length, (i) => i));
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete selected',
            onPressed: _selected.isEmpty ? null : _deleteSelected,
          ),
        ] : [
          IconButton(
            icon: Icon(_showLocal ? Icons.cloud_outlined : Icons.phone_android),
            tooltip: _showLocal ? 'Show ComfyUI history' : 'Show local saved',
            onPressed: () => setState(() => _showLocal = !_showLocal),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadImages,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _loadImages, child: const Text('Retry')),
                  ],
                ))
              : _showLocal
                  ? _buildLocalGrid()
                  : _buildRemoteGrid(),
    );
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selected.length} image${_selected.length > 1 ? "s" : ""}?'),
        content: const Text('This will remove them from your device permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
    if (!confirmed) return;
    final toDelete = _selected.toList()..sort((a, b) => b.compareTo(a));
    for (final i in toDelete) {
      try { await _localImages[i].delete(); } catch (_) {}
    }
    setState(() { _selectMode = false; _selected.clear(); });
    await _loadLocal();
  }

  Widget _buildLocalGrid() {
    if (_localImages.isEmpty) {
      return const Center(child: Text('No images saved locally yet'));
    }
    return RefreshIndicator(
      onRefresh: _loadLocal,
      child: GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.shortestSide >= 600 ? 5 : 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 9 / 16,
      ),
      itemCount: _localImages.length,
      itemBuilder: (ctx, i) {
        final isSelected = _selected.contains(i);
        return GestureDetector(
          onTap: () {
            if (_selectMode) {
              setState(() {
                if (isSelected) _selected.remove(i); else _selected.add(i);
                if (_selected.isEmpty) _selectMode = false;
              });
            } else {
              _openLocalFullscreen(i);
            }
          },
          onLongPress: () => setState(() {
            _selectMode = true;
            _selected.add(i);
          }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(_localImages[i], fit: BoxFit.cover),
              if (_selectMode)
                Container(
                  color: isSelected ? Colors.deepPurple.withOpacity(0.5) : Colors.transparent,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
            ],
          ),
        );
      },
      ),
    );
  }

  Widget _buildRemoteGrid() {
    if (_remoteImages.isEmpty) {
      return const Center(child: Text('No images in ComfyUI history'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.shortestSide >= 600 ? 5 : 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 9 / 16,
      ),
      itemCount: _remoteImages.length,
      itemBuilder: (ctx, i) {
        final img = _remoteImages[i];
        return GestureDetector(
          onTap: () => _openRemoteFullscreen(i),
          onLongPress: () => _saveRemoteImage(img),
          child: Image.network(
            img['url'] as String,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) =>
                progress == null ? child
                    : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            errorBuilder: (ctx, e, _) => const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      },
    );
  }
}

// ── Local fullscreen swipeable gallery ─────────────────────────────────────

class _LocalFullscreenGallery extends StatefulWidget {
  final List<File> files;
  final int initialIndex;
  final Future<void> Function(Map<String, dynamic>)? onLoadSettings;
  final Future<void> Function(File)? onDelete;

  const _LocalFullscreenGallery({
    required this.files,
    required this.initialIndex,
    this.onLoadSettings,
    this.onDelete,
  });

  @override
  State<_LocalFullscreenGallery> createState() => _LocalFullscreenGalleryState();
}

class _LocalFullscreenGalleryState extends State<_LocalFullscreenGallery> {
  late PageController _pageController;
  late int _current;
  bool _loadingSettings = false;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    debugPrint('[Gallery] LocalFullscreen opened, onLoadSettings=${widget.onLoadSettings != null}');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _useSettings() async {
    debugPrint('[Gallery] _useSettings called, onLoadSettings=${widget.onLoadSettings != null}');
    if (widget.onLoadSettings == null) return;
    setState(() => _loadingSettings = true);
    try {
      final file = widget.files[_current];
      final meta = await PngMetadata.read(file);
      debugPrint('[Gallery] meta read result: ${meta == null ? "null" : "${meta.keys.length} keys: ${meta.keys.take(5).toList()}"}');
      if (meta == null || meta.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No ComfyUI metadata found in this image')),
          );
        }
        return;
      }
      // meta IS the prompt JSON — parse it directly
      final settings = PngMetadata.parsePrompt(meta);
      debugPrint('[Gallery] parsed settings keys: ${settings.keys.toList()}');
      debugPrint('[Gallery] positive: ${settings['positive']}');
      debugPrint('[Gallery] lora1: ${settings['lora1']}');
      if (settings.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not parse image settings')),
          );
        }
        return;
      }
      debugPrint('[Gallery] calling onLoadSettings with ${settings.keys.length} keys');
      await widget.onLoadSettings!(settings);
      debugPrint('[Gallery] onLoadSettings done, popping');
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.files.length}',
            style: const TextStyle(fontSize: 14)),
        actions: [
          if (widget.onLoadSettings != null)
            _loadingSettings
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  )
                : IconButton(
                    icon: const Icon(Icons.tune, color: Colors.white),
                    tooltip: 'Use these settings in Generate',
                    onPressed: _useSettings,
                  ),
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete image',
              onPressed: () => widget.onDelete!(widget.files[_current]),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.files.length,
        physics: _isZoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (ctx, i) => _ZoomableImage(
          onZoomChanged: (zoomed) => setState(() => _isZoomed = zoomed),
          child: Image.file(widget.files[i], fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ── Remote fullscreen swipeable gallery ────────────────────────────────────

class _RemoteFullscreenGallery extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;
  final void Function(Map<String, dynamic>) onSave;

  const _RemoteFullscreenGallery({
    required this.images,
    required this.initialIndex,
    required this.onSave,
  });

  @override
  State<_RemoteFullscreenGallery> createState() => _RemoteFullscreenGalleryState();
}

class _RemoteFullscreenGalleryState extends State<_RemoteFullscreenGallery> {
  late PageController _pageController;
  late int _current;
  bool _isZoomed = false;

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
    final img = widget.images[_current];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.images.length}',
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            tooltip: 'Save to Downloads',
            onPressed: () => widget.onSave(img),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        physics: _isZoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (ctx, i) => _ZoomableImage(
          onZoomChanged: (zoomed) => setState(() => _isZoomed = zoomed),
          child: Image.network(
            widget.images[i]['url'] as String,
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, progress) =>
                progress == null ? child
                    : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }
}

// ── Double-tap to zoom widget ──────────────────────────────────────────────

class _ZoomableImage extends StatefulWidget {
  final Widget child;
  final void Function(bool zoomed)? onZoomChanged;
  const _ZoomableImage({required this.child, this.onZoomChanged});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final _transformController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        _transformController.value = _animation!.value;
      });
    _transformController.addListener(() {
      final zoomed = _transformController.value != Matrix4.identity();
      if (zoomed != _isZoomed) {
        setState(() => _isZoomed = zoomed);
        widget.onZoomChanged?.call(zoomed);
      }
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onDoubleTap(TapDownDetails details) {
    if (_isZoomed) {
      _animation = Matrix4Tween(
        begin: _transformController.value,
        end: Matrix4.identity(),
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    } else {
      final pos = details.localPosition;
      final zoomed = Matrix4.identity()
        ..translate(-pos.dx * 1.5, -pos.dy * 1.5)
        ..scale(2.5);
      _animation = Matrix4Tween(
        begin: _transformController.value,
        end: zoomed,
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    }
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _onDoubleTap,
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 0.5,
        maxScale: 5.0,
        // When zoomed in, intercept pan gestures so PageView doesn't steal them
        panEnabled: true,
        scaleEnabled: true,
        child: Center(child: widget.child),
      ),
    );
  }
}

// ── Self-filtering remote image cell ──────────────────────────────────────
class _RemoteImageCell extends StatefulWidget {
  final Map<String, dynamic> img;
  final VoidCallback onError;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _RemoteImageCell({
    required this.img,
    required this.onError,
    required this.onTap,
    required this.onLongPress,
  });
  @override
  State<_RemoteImageCell> createState() => _RemoteImageCellState();
}

class _RemoteImageCellState extends State<_RemoteImageCell> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Image.network(
        widget.img['url'] as String,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child
                : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorBuilder: (ctx, e, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _failed = true);
              widget.onError();
            }
          });
          return const SizedBox.shrink();
        },
      ),
    );
  }
}