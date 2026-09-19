import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'features/manga_processing/data/processing_repository.dart';
import 'features/manga_processing/domain/page_analysis.dart';
import 'features/manga_processing/presentation/processing_controller.dart';
import 'features/manga_processing/presentation/region_geometry.dart';

void main() => runApp(const MangaTranslatorApp());

class MangaTranslatorApp extends StatelessWidget {
  const MangaTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Manga Translator',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.apiClient, this.controller});

  final ApiClient? apiClient;
  final ProcessingController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ApiClient _apiClient = widget.apiClient ?? ApiClient();
  late final ProcessingController _controller =
      widget.controller ??
      ProcessingController(
        ProcessingRepository(ProcessingRemoteDataSource(_apiClient)),
      );
  late Future<HealthResponse> _health = _apiClient.getHealth();

  void _refresh() => setState(() => _health = _apiClient.getHealth());

  Future<void> _openImage() async {
    const images = XTypeGroup(
      label: 'Manga images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    try {
      final selected = await openFile(acceptedTypeGroups: [images]);
      if (selected != null) {
        _controller.selectImage(selected.name, await selected.readAsBytes());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open image: $error')));
      }
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manga Translator')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              FilledButton(
                onPressed: _openImage,
                child: const Text('Open Image'),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => FilledButton.tonal(
                  onPressed:
                      _controller.imageBytes == null ||
                          _controller.status == ProcessingStatus.processing
                      ? null
                      : _controller.detect,
                  child: const Text('Analyze Page'),
                ),
              ),
              const Spacer(),
              FutureBuilder<HealthResponse>(
                future: _health,
                builder: (context, snapshot) => Text(
                  snapshot.connectionState != ConnectionState.done
                      ? 'Checking backend...'
                      : !snapshot.hasData
                      ? 'Backend unavailable'
                      : !snapshot.data!.detectorReady
                      ? 'Detector unavailable'
                      : !snapshot.data!.ocrReady
                      ? 'OCR unavailable'
                      : 'Backend ready',
                ),
              ),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Retry backend',
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Column(
              children: [
                if (_controller.status == ProcessingStatus.processing)
                  const LinearProgressIndicator(),
                if (_controller.status == ProcessingStatus.processing)
                  const Text('Detecting and recognizing text...'),
                if (_controller.status == ProcessingStatus.failure)
                  Text(
                    'Detection failed: ${_controller.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_controller.status == ProcessingStatus.success)
                  Text(
                    '${_controller.analysis!.regions.length} regions detected',
                  ),
                Expanded(
                  child: _controller.imageBytes == null
                      ? const Center(child: Text('Open a manga image to begin'))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final canvasSize = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            final analysis = _controller.analysis;
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.memory(
                                    _controller.imageBytes!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                if (analysis != null)
                                  for (final region in analysis.regions)
                                    _regionBox(
                                      region,
                                      Size(
                                        analysis.width.toDouble(),
                                        analysis.height.toDouble(),
                                      ),
                                      canvasSize,
                                    ),
                              ],
                            );
                          },
                        ),
                ),
                if (_controller.selectedRegion case final region?)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Selected Region: ${region.id}'),
                        const Text('Japanese:'),
                        Text(
                          region.errorCode != null
                              ? 'OCR failed for this region (${region.errorCode})'
                              : region.sourceText?.isNotEmpty == true
                              ? region.sourceText!
                              : 'No text recognized',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _regionBox(DetectedRegion region, Size imageSize, Size canvasSize) {
    final box = displayRectForRegion(region, imageSize, canvasSize);
    return Positioned(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      child: GestureDetector(
        onTap: () => _controller.selectRegion(region.id),
        child: Container(
          key: ValueKey(region.id),
          decoration: BoxDecoration(
            color: _controller.selectedRegionId == region.id
                ? Colors.amber.withValues(alpha: 0.3)
                : Colors.red.withValues(alpha: 0.15),
            border: Border.all(
              color: _controller.selectedRegionId == region.id
                  ? Colors.amber
                  : Colors.red,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}
