import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/api/api_client.dart';
import 'features/chapter/chapter_controller.dart';
import 'features/chapter/chapter_persistence.dart';
import 'features/manga_processing/data/processing_repository.dart';
import 'features/manga_processing/presentation/processing_controller.dart';
import 'features/manga_processing/presentation/region_editor.dart';
import 'features/manga_processing/presentation/region_geometry.dart';
import 'features/manga_processing/presentation/translation_region_overlay.dart';

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
  const HomePage({
    super.key,
    this.apiClient,
    this.controller,
    this.chapterController,
  });

  final ApiClient? apiClient;
  final ProcessingController? controller;
  final ChapterController? chapterController;

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
  late final ChapterController _chapter =
      widget.chapterController ?? ChapterController(_controller.repository);
  late bool _chapterMode = _chapter.directoryPath != null;
  bool _showTranslationOverlay = true;
  bool _showDetectionBoxes = true;

  void _refresh() => setState(() => _health = _apiClient.getHealth());

  Future<void> _openImage() async {
    const images = XTypeGroup(
      label: 'Manga images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    try {
      final selected = await openFile(acceptedTypeGroups: [images]);
      if (selected != null) {
        await _chapter.stopAndWait();
        setState(() => _chapterMode = false);
        if (widget.controller == null) {
          _controller.persistence ??= ChapterPersistenceRepository(
            await getApplicationSupportDirectory(),
          );
        }
        await _controller.openImageFile(
          selected.path,
          await selected.readAsBytes(),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open image: $error')));
      }
    }
  }

  Future<void> _openChapter() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: 'Open Chapter');
      if (path == null) return;
      await _controller.flushSaves();
      if (widget.chapterController == null) {
        _chapter.persistence ??= ChapterPersistenceRepository(
          await getApplicationSupportDirectory(),
        );
      }
      await _chapter.open(path);
      if (mounted) setState(() => _chapterMode = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open chapter: $error')),
        );
      }
    }
  }

  @override
  void dispose() {
    if (widget.chapterController == null) _chapter.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _chapterToolbar() {
    final page = _chapter.selectedPage;
    final average = _chapter.averageDuration;
    String estimate(Duration? value) =>
        value == null ? 'Calculating...' : '~${formatDuration(value)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _chapter.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              FilledButton.tonal(
                onPressed: _chapter.processing || _chapter.pendingCount == 0
                    ? null
                    : _chapter.processPending,
                child: const Text('Process Chapter'),
              ),
              if (_chapter.processing)
                OutlinedButton(
                  onPressed: _chapter.stopRequested
                      ? null
                      : _chapter.requestStop,
                  child: Text(
                    _chapter.stopRequested
                        ? 'Stopping after page...'
                        : 'Stop After Page',
                  ),
                ),
              if (page?.status == ChapterPageStatus.failed &&
                  !_chapter.processing)
                OutlinedButton(
                  onPressed: () =>
                      _chapter.retryPage(_chapter.selectedPageIndex),
                  child: const Text('Retry Page'),
                ),
              IconButton(
                onPressed: _chapter.selectedPageIndex > 0
                    ? () => _chapter.selectPage(_chapter.selectedPageIndex - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous Page',
              ),
              Text(
                _chapter.pages.isEmpty
                    ? 'Page 0 / 0'
                    : 'Page ${_chapter.selectedPageIndex + 1} / ${_chapter.pages.length}',
              ),
              IconButton(
                onPressed:
                    _chapter.selectedPageIndex + 1 < _chapter.pages.length
                    ? () => _chapter.selectPage(_chapter.selectedPageIndex + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next Page',
              ),
            ],
          ),
          if (_chapter.error != null)
            Text(
              _chapter.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_chapter.cacheWarning != null)
            Text(
              _chapter.cacheWarning!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_chapter.saveError != null)
            Text(
              _chapter.saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (page?.error != null)
            Text(
              '${page!.name}: ${page.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          LinearProgressIndicator(
            value: _chapter.pages.isEmpty
                ? 0
                : _chapter.settledCount / _chapter.pages.length,
          ),
          const SizedBox(height: 4),
          Text(
            '${_chapter.completedCount} completed / ${_chapter.pages.length} pages, '
            '${_chapter.pages.where((p) => p.status == ChapterPageStatus.failed).length} failed',
          ),
          if (_chapter.currentPageIndex >= 0)
            Text(
              'Processing page ${_chapter.currentPageIndex + 1} / ${_chapter.pages.length} '
              '• Page elapsed: ${formatDuration(_chapter.pageElapsed)} '
              '• Page estimate: ${estimate(average)} '
              '• Page remaining: ${estimate(_chapter.pageRemaining)}',
            ),
          Text(
            'Chapter elapsed: ${formatDuration(_chapter.chapterElapsed)} '
            '• Estimated remaining: ${estimate(_chapter.estimatedRemaining)} '
            '• Estimated total: ${estimate(_chapter.estimatedTotal)}',
          ),
        ],
      ),
    );
  }

  Widget _pageList() => SizedBox(
    width: 190,
    child: ListView.builder(
      itemCount: _chapter.pages.length,
      itemBuilder: (context, index) {
        final page = _chapter.pages[index];
        final icon = switch (page.status) {
          ChapterPageStatus.pending => Icons.radio_button_unchecked,
          ChapterPageStatus.processing => Icons.hourglass_top,
          ChapterPageStatus.completed => Icons.check_circle,
          ChapterPageStatus.failed => Icons.error,
        };
        return ListTile(
          selected: index == _chapter.selectedPageIndex,
          dense: true,
          leading: Icon(icon, size: 18),
          title: Text(page.name, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (page.restoredFromCache)
                const Tooltip(
                  message: 'Cached',
                  child: Icon(Icons.cloud_done_outlined, size: 16),
                ),
              if (page.edits.hasEdits)
                const Tooltip(
                  message: 'Edited',
                  child: Icon(Icons.edit, size: 16),
                ),
            ],
          ),
          subtitle: page.duration == null
              ? null
              : Text(formatDuration(page.duration!)),
          onTap: () => _chapter.selectPage(index),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manga Translator')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                        _chapterMode ||
                            _controller.imageBytes == null ||
                            _controller.status == ProcessingStatus.processing
                        ? null
                        : _controller.detect,
                    child: const Text('Analyze Page'),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Show translated text over detected regions',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Translation Overlay'),
                      Switch(
                        value: _showTranslationOverlay,
                        onChanged: (value) =>
                            setState(() => _showTranslationOverlay = value),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Show detected region boxes',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Detection Boxes'),
                      Switch(
                        value: _showDetectionBoxes,
                        onChanged: (value) =>
                            setState(() => _showDetectionBoxes = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _openChapter,
                  child: const Text('Open Chapter'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _chapter.selectedRegionId = null;
                      _controller.selectedRegionId = null;
                    });
                  },
                  child: const Text('Close Editor'),
                ),
                const SizedBox(width: 16),
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
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([_controller, _chapter]),
            builder: (context, _) => Column(
              children: [
                if (_chapterMode) _chapterToolbar(),
                if (!_chapterMode &&
                    _controller.status == ProcessingStatus.processing)
                  const LinearProgressIndicator(),
                if (!_chapterMode &&
                    _controller.status == ProcessingStatus.processing)
                  const Text('Detecting, recognizing, and translating text...'),
                if (!_chapterMode &&
                    _controller.status == ProcessingStatus.failure)
                  Text(
                    'Detection failed: ${_controller.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (!_chapterMode &&
                    _controller.status == ProcessingStatus.success)
                  Text(
                    '${_controller.analysis!.regions.length} regions detected',
                  ),
                if (!_chapterMode && _controller.restoredFromCache)
                  const Text('Cached analysis'),
                if (!_chapterMode && _controller.cacheWarning != null)
                  Text(
                    _controller.cacheWarning!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (!_chapterMode && _controller.saveError != null)
                  Text(
                    _controller.saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (_chapterMode) _pageList(),
                      Expanded(
                        child:
                            (_chapterMode
                                ? _chapter.selectedPage == null
                                : _controller.imageBytes == null)
                            ? const Center(
                                child: Text('Open a manga image to begin'),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  final canvasSize = Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  );
                                  final analysis = _chapterMode
                                      ? _chapter.analysis
                                      : _controller.analysis;
                                  final edits = _chapterMode
                                      ? _chapter.selectedPage!.edits
                                      : _controller.edits;
                                  final imageSize = analysis == null
                                      ? null
                                      : Size(
                                          analysis.width.toDouble(),
                                          analysis.height.toDouble(),
                                        );
                                  final imageRect = imageSize == null
                                      ? null
                                      : displayRectForImage(
                                          imageSize,
                                          canvasSize,
                                        );
                                  final detectorRects = analysis == null
                                      ? <Rect>[]
                                      : [
                                          for (final region in analysis.regions)
                                            displayRectForRegion(
                                              region,
                                              imageSize!,
                                              canvasSize,
                                            ),
                                        ];
                                  return Stack(
                                    children: [
                                      Positioned.fill(
                                        child: _chapterMode
                                            ? Image.file(
                                                _chapter.selectedPage!.file,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stack,
                                                    ) => Center(
                                                      child: Text(
                                                        'Could not display image: $error',
                                                      ),
                                                    ),
                                              )
                                            : Image.memory(
                                                _controller.imageBytes!,
                                                fit: BoxFit.contain,
                                              ),
                                      ),
                                      if (analysis != null)
                                        for (
                                          var index = 0;
                                          index < analysis.regions.length;
                                          index++
                                        )
                                          TranslationRegionOverlay(
                                            region: analysis.regions[index],
                                            rect: detectorRects[index],
                                            translationRect: displayRectForBox(
                                              edits.effectiveBox(
                                                analysis.regions[index],
                                              ),
                                              imageSize!,
                                              canvasSize,
                                            ),
                                            editedTranslatedText: edits
                                                .forRegion(
                                                  analysis.regions[index].id,
                                                )
                                                .translatedText,
                                            imageRect: imageRect!,
                                            obstacles: [
                                              for (
                                                var other = 0;
                                                other < detectorRects.length;
                                                other++
                                              )
                                                if (other != index)
                                                  detectorRects[other],
                                            ],
                                            selected:
                                                (_chapterMode
                                                    ? _chapter.selectedRegionId
                                                    : _controller
                                                          .selectedRegionId) ==
                                                analysis.regions[index].id,
                                            showTranslation:
                                                _showTranslationOverlay,
                                            showDetectionBox:
                                                _showDetectionBoxes,
                                            onTap: () => _chapterMode
                                                ? _chapter.selectRegion(
                                                    analysis.regions[index].id,
                                                  )
                                                : _controller.selectRegion(
                                                    analysis.regions[index].id,
                                                  ),
                                          ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                if ((_chapterMode
                        ? _chapter.selectedRegion
                        : _controller.selectedRegion)
                    case final region?)
                  RegionEditor(
                    key: ValueKey(
                      '${_chapterMode ? '${_chapter.directoryPath}:${_chapter.selectedPageIndex}' : _controller.filename}:${region.id}',
                    ),
                    region: region,
                    analysis: _chapterMode
                        ? _chapter.analysis!
                        : _controller.analysis!,
                    edits: _chapterMode
                        ? _chapter.selectedPage!.edits
                        : _controller.edits,
                    onTranslation: (text) => _chapterMode
                        ? _chapter.setTranslation(region.id, text)
                        : _controller.setTranslation(region.id, text),
                    onBox: (box) => _chapterMode
                        ? _chapter.setBox(region.id, box)
                        : _controller.setBox(region.id, box),
                    onResetBox: () => _chapterMode
                        ? _chapter.resetBox(region.id)
                        : _controller.resetBox(region.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
