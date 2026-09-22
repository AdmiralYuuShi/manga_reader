import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app_theme.dart';
import 'core/api/api_client.dart';
import 'features/chapter/chapter_controller.dart';
import 'features/chapter/chapter_persistence.dart';
import 'features/chapter/source_hierarchy.dart';
import 'features/library/library_controller.dart';
import 'features/library/library_model.dart';
import 'features/library/library_view.dart';
import 'features/manga_processing/data/processing_repository.dart';
import 'features/manga_processing/presentation/processing_controller.dart';
import 'features/manga_processing/presentation/manga_viewer_workspace.dart';
import 'features/manga_processing/presentation/region_editor.dart';
import 'features/settings/manga_overlay_font.dart';
import 'features/settings/appearance_mode.dart';
import 'features/settings/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = AppPreferences();
  await preferences.load();
  runApp(MangaTranslatorApp(preferences: preferences));
}

class MangaTranslatorApp extends StatelessWidget {
  const MangaTranslatorApp({super.key, required this.preferences, this.home});

  final AppPreferences preferences;
  final Widget? home;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => MaterialApp(
      title: 'Manga Translator',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: preferences.appearance.themeMode,
      home: home ?? HomePage(preferences: preferences),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.apiClient,
    this.controller,
    this.chapterController,
    this.preferences,
    this.sourceHierarchy,
    this.libraryController,
  });

  final ApiClient? apiClient;
  final ProcessingController? controller;
  final ChapterController? chapterController;
  final AppPreferences? preferences;
  final SourceHierarchy? sourceHierarchy;
  final LibraryController? libraryController;

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
  late final AppPreferences _preferences =
      widget.preferences ?? AppPreferences();
  late final LibraryController _library =
      widget.libraryController ?? LibraryController();
  late bool _chapterMode = _chapter.directoryPath != null;
  late SourceHierarchy? _hierarchy = widget.sourceHierarchy;
  bool _libraryMode = false;
  bool _switchingChapter = false;
  bool _showTranslationOverlay = true;
  bool _showDetectionBoxes = true;

  @override
  void initState() {
    super.initState();
    if (widget.preferences == null) _preferences.load();
    _library.load();
  }

  Future<void> _showSettings() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 340,
        child: ListenableBuilder(
          listenable: _preferences,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<AppearanceMode>(
                segments: [
                  for (final mode in AppearanceMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {_preferences.appearance},
                onSelectionChanged: (selection) async {
                  try {
                    await _preferences.selectAppearance(selection.single);
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text('Could not save appearance: $error'),
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Manga overlay font',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final font in MangaOverlayFont.all)
                ListTile(
                  key: ValueKey('font-option-${font.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(font.label),
                  subtitle: Text(
                    'Manga 123',
                    style: TextStyle(fontFamily: font.family, fontSize: 18),
                  ),
                  trailing: _preferences.overlayFont == font
                      ? const Icon(Icons.check)
                      : null,
                  selected: _preferences.overlayFont == font,
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    try {
                      await _preferences.selectFont(font);
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not save overlay font: $error',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

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
        setState(() {
          _chapterMode = false;
          _hierarchy = null;
          _libraryMode = false;
        });
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
      await _openChapterPath(path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open chapter: $error')),
        );
      }
    }
  }

  Future<void> _openChapterPath(
    String path, {
    String? chapterRelativePath,
    String? pageName,
  }) async {
    await _controller.flushSaves();
    final hierarchy = await SourceHierarchy.discover(path);
    if (hierarchy.chapters.isEmpty) {
      throw StateError(
        'No supported chapter images were found in this folder.',
      );
    }
    final folder = chapterRelativePath == null
        ? hierarchy.chapters.first
        : hierarchy.chapters.firstWhere(
            (candidate) => candidate.relativePath == chapterRelativePath,
            orElse: () => throw StateError(
              'The selected chapter is no longer in this folder. Refresh the library.',
            ),
          );
    if (pageName != null && !folder.pageNames.contains(pageName)) {
      throw StateError(
        'The selected page is no longer in this chapter. Refresh the library.',
      );
    }
    if (widget.chapterController == null) {
      _chapter.persistence ??= ChapterPersistenceRepository(
        await getApplicationSupportDirectory(),
      );
    }
    await _chapter.open(folder.path);
    if (pageName != null) {
      final index = _chapter.pages.indexWhere((page) => page.name == pageName);
      if (index < 0) {
        throw StateError('The selected page is no longer available.');
      }
      _chapter.selectPage(index);
    }
    if (mounted) {
      setState(() {
        _chapterMode = true;
        _libraryMode = false;
        _hierarchy = hierarchy;
      });
    }
    try {
      final root = await _library.register(hierarchy);
      _library.refresh(root.id, discovered: hierarchy);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Chapter opened, but library registration failed: $error',
            ),
          ),
        );
      }
    }
  }

  Future<void> _enterLibrary() async {
    await _chapter.flushSaves();
    if (!mounted) return;
    setState(() => _libraryMode = true);
    final root = _hierarchy?.root;
    if (root != null) {
      _library.refresh(chapterStorageId(root.path));
    }
  }

  Future<void> _openLibraryRoot(
    LibraryRoot root, {
    LibraryFolder? folder,
    String? pageName,
  }) async {
    try {
      await _openChapterPath(
        root.path,
        chapterRelativePath: folder?.relativePath,
        pageName: pageName,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open library item: $error')),
        );
      }
    }
  }

  Future<void> _selectChapter(SourceFolder folder) async {
    if (_switchingChapter || folder.path == _chapter.directoryPath) return;
    setState(() => _switchingChapter = true);
    try {
      await _chapter.open(folder.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open chapter: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingChapter = false);
    }
  }

  List<(SourceFolder, int)> get _folderEntries {
    final entries = <(SourceFolder, int)>[];
    void visit(SourceFolder folder, int depth) {
      if (folder.isChapter || depth > 0) {
        entries.add((folder, depth));
      }
      for (final child in folder.children) {
        visit(child, depth + 1);
      }
    }

    final root = _hierarchy?.root;
    if (root != null) visit(root, 0);
    return entries;
  }

  @override
  void dispose() {
    if (widget.chapterController == null) _chapter.dispose();
    if (widget.controller == null) _controller.dispose();
    if (widget.preferences == null) _preferences.dispose();
    if (widget.libraryController == null) _library.dispose();
    super.dispose();
  }

  Widget _topActions() => SizedBox(
    height: 52,
    child: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _openImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Open Image'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _openChapter,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open Chapter'),
                  ),
                  const SizedBox(width: 16),
                  if (!_libraryMode && _chapterMode) ...[
                    FilledButton.icon(
                      onPressed:
                          _chapter.processing || _chapter.pendingCount == 0
                          ? null
                          : _chapter.processPending,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Process Chapter'),
                    ),
                    if (_chapter.processing) ...[
                      const SizedBox(width: 8),
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
                    ],
                    if (_chapter.selectedPage?.status ==
                            ChapterPageStatus.failed &&
                        !_chapter.processing) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () =>
                            _chapter.retryPage(_chapter.selectedPageIndex),
                        child: const Text('Retry Page'),
                      ),
                    ],
                  ] else if (!_libraryMode)
                    FilledButton.icon(
                      onPressed:
                          _controller.imageBytes == null ||
                              _controller.status == ProcessingStatus.processing
                          ? null
                          : _controller.detect,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Analyze Page'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _libraryMode
                        ? () => setState(() => _libraryMode = false)
                        : _enterLibrary,
                    icon: Icon(
                      _libraryMode
                          ? Icons.menu_book_outlined
                          : Icons.library_books_outlined,
                    ),
                    label: Text(_libraryMode ? 'Reader' : 'Library'),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _showSettings,
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

  Widget _navigationPanel(double width) {
    final colors = Theme.of(context).colorScheme;
    final entries = _folderEntries;
    final showFolders =
        _hierarchy != null &&
        (_hierarchy!.chapters.length > 1 ||
            _hierarchy!.root.children.isNotEmpty);
    return SizedBox(
      width: width,
      child: ColoredBox(
        color: colors.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showFolders) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Text(
                  'Folders',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              SizedBox(
                height: 210,
                child: ListView.builder(
                  key: const ValueKey('chapter-folder-list'),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final (folder, depth) = entries[index];
                    final active =
                        folder.isChapter &&
                        folder.path == _chapter.directoryPath;
                    return Tooltip(
                      message: folder.relativePath.isEmpty
                          ? folder.name
                          : folder.relativePath,
                      child: ListTile(
                        key: ValueKey('chapter-folder-${folder.relativePath}'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.only(
                          left: 8.0 + depth * 12,
                          right: 4,
                        ),
                        leading: Icon(
                          folder.isChapter
                              ? Icons.folder_open_outlined
                              : Icons.folder_outlined,
                          size: 18,
                        ),
                        title: Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: active,
                        selectedTileColor: colors.primaryContainer,
                        onTap: folder.isChapter && !_switchingChapter
                            ? () => _selectChapter(folder)
                            : null,
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text(
                'Pages',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('chapter-page-list'),
                itemCount: _chapter.pages.length,
                itemBuilder: (context, index) {
                  final page = _chapter.pages[index];
                  final icon = switch (page.status) {
                    ChapterPageStatus.pending => Icons.radio_button_unchecked,
                    ChapterPageStatus.processing => Icons.hourglass_top,
                    ChapterPageStatus.completed => Icons.check_circle_outline,
                    ChapterPageStatus.failed => Icons.error_outline,
                  };
                  return ListTile(
                    key: ValueKey('chapter-page-$index'),
                    selected: index == _chapter.selectedPageIndex,
                    selectedTileColor: colors.primaryContainer,
                    dense: true,
                    leading: Icon(
                      icon,
                      size: 18,
                      color: page.status == ChapterPageStatus.failed
                          ? colors.error
                          : colors.primary,
                    ),
                    title: Text(page.name, overflow: TextOverflow.ellipsis),
                    trailing: page.edits.hasEdits
                        ? const Tooltip(
                            message: 'Edited',
                            child: Icon(Icons.edit, size: 16),
                          )
                        : page.restoredFromCache
                        ? const Tooltip(
                            message: 'Cached',
                            child: Icon(Icons.cloud_done_outlined, size: 16),
                          )
                        : null,
                    subtitle: page.duration == null
                        ? null
                        : Text(formatDuration(page.duration!)),
                    onTap: () => _chapter.selectPage(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewerToolbar() => SizedBox(
    height: 48,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (_chapterMode) ...[
            if (_hierarchy != null && _hierarchy!.chapters.length > 1)
              PopupMenuButton<SourceFolder>(
                tooltip: 'Choose Chapter',
                enabled: !_switchingChapter,
                onSelected: _selectChapter,
                itemBuilder: (context) => [
                  for (final folder in _hierarchy!.chapters)
                    PopupMenuItem(
                      value: folder,
                      child: Text(
                        folder.relativePath.isEmpty
                            ? folder.name
                            : folder.relativePath,
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          _chapter.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
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
              onPressed: _chapter.selectedPageIndex + 1 < _chapter.pages.length
                  ? () => _chapter.selectPage(_chapter.selectedPageIndex + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next Page',
            ),
            const VerticalDivider(width: 16),
          ],
          const SizedBox(width: 8),
          const Tooltip(
            message: 'Translation Overlay',
            child: Icon(Icons.translate, size: 18),
          ),
          Switch(
            value: _showTranslationOverlay,
            onChanged: (value) =>
                setState(() => _showTranslationOverlay = value),
          ),
          const SizedBox(width: 8),
          const Tooltip(
            message: 'Detection Boxes',
            child: Icon(Icons.crop_free, size: 18),
          ),
          Switch(
            value: _showDetectionBoxes,
            onChanged: (value) => setState(() => _showDetectionBoxes = value),
          ),
        ],
      ),
    ),
  );

  Widget _viewer() {
    final hasImage = _chapterMode
        ? _chapter.selectedPage != null
        : _controller.imageBytes != null;
    final chapterMode = _chapterMode;
    final page = chapterMode ? _chapter.selectedPage : null;
    final analysis = chapterMode ? _chapter.analysis : _controller.analysis;
    final selected = chapterMode
        ? _chapter.selectedRegion
        : _controller.selectedRegion;
    final edits = chapterMode
        ? (page?.edits ?? _controller.edits)
        : _controller.edits;
    return Column(
      children: [
        _viewerToolbar(),
        const Divider(height: 1),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: !hasImage
                ? const Center(child: Text('Open a manga image to begin'))
                : MangaViewerWorkspace(
                    file: page?.file,
                    bytes: chapterMode ? null : _controller.imageBytes,
                    analysis: analysis,
                    edits: edits,
                    selectedRegion: selected,
                    showTranslation: _showTranslationOverlay,
                    showDetectionBoxes: _showDetectionBoxes,
                    onSelectRegion: (id) => chapterMode
                        ? _chapter.selectRegion(id)
                        : _controller.selectRegion(id),
                    onPreviewBox: (box) {
                      if (selected == null) return;
                      if (chapterMode) {
                        if (_chapter.selectedPage == page &&
                            _chapter.selectedRegionId == selected.id) {
                          _chapter.setBox(selected.id, box, persist: false);
                        }
                      } else if (_controller.analysis == analysis &&
                          _controller.selectedRegionId == selected.id) {
                        _controller.setBox(selected.id, box, persist: false);
                      }
                    },
                    onCommitBox: () {
                      if (chapterMode) {
                        _chapter.commitBoxPreview(page!);
                      } else {
                        _controller.commitBoxPreview();
                      }
                    },
                    overlayFont: _preferences.overlayFont,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _inspector(double width) {
    final region = _chapterMode
        ? _chapter.selectedRegion
        : _controller.selectedRegion;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: ColoredBox(
        color: colors.surfaceContainerLow,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Inspector',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (region != null)
                    IconButton(
                      onPressed: () => setState(() {
                        _chapter.selectedRegionId = null;
                        _controller.selectedRegionId = null;
                      }),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close Editor',
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: region == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Select a text region to inspect or edit it.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RegionEditor(
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar() {
    final colors = Theme.of(context).colorScheme;
    if (_libraryMode) {
      return SizedBox(
        height: 34,
        child: ColoredBox(
          color: colors.surfaceContainerLow,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${_library.roots.length} library roots · Last indexed statuses update on refresh',
              ),
            ),
          ),
        ),
      );
    }
    final messages = <Widget>[];
    void add(String value, {bool error = false}) => messages.add(
      Text(
        value,
        style: TextStyle(color: error ? colors.error : colors.onSurface),
      ),
    );
    if (_chapterMode) {
      if (_hierarchy != null && _hierarchy!.chapters.length > 1) {
        add('Chapter: ${_chapter.name}');
      }
      add(
        '${_chapter.completedCount} completed / ${_chapter.pages.length} pages',
      );
      if (_hierarchy?.skippedFolders case final skipped? when skipped > 0) {
        add('$skipped inaccessible or linked folders skipped', error: true);
      }
      if (_chapter.processing) {
        add(
          'Processing page ${_chapter.currentPageIndex + 1} / ${_chapter.pages.length}',
        );
        add('Elapsed ${formatDuration(_chapter.chapterElapsed)}');
        if (_chapter.estimatedRemaining case final remaining?) {
          add('Remaining ~${formatDuration(remaining)}');
        }
      }
      if (_chapter.selectedPage?.restoredFromCache == true) {
        add('Cached');
      }
      if (_chapter.selectedPage?.edits.hasEdits == true) {
        add('Edited');
      }
      if (_chapter.error != null) {
        add(_chapter.error!, error: true);
      }
      if (_chapter.selectedPage?.error case final pageError?) {
        add(pageError, error: true);
      }
      if (_chapter.cacheWarning != null) {
        add(_chapter.cacheWarning!, error: true);
      }
      if (_chapter.saveError != null) {
        add(_chapter.saveError!, error: true);
      }
    } else {
      switch (_controller.status) {
        case ProcessingStatus.initial:
          if (_controller.imageBytes != null) {
            add('Ready to analyze');
          }
        case ProcessingStatus.processing:
          add('Detecting, recognizing, and translating text...');
        case ProcessingStatus.success:
          add('${_controller.analysis!.regions.length} regions detected');
        case ProcessingStatus.failure:
          add('Detection failed: ${_controller.error}', error: true);
      }
      if (_controller.restoredFromCache) {
        add('Cached analysis');
      }
      if (_controller.edits.hasEdits) {
        add('Edited');
      }
      if (_controller.cacheWarning != null) {
        add(_controller.cacheWarning!, error: true);
      }
      if (_controller.saveError != null) {
        add(_controller.saveError!, error: true);
      }
    }
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_chapterMode && _chapter.pages.isNotEmpty)
            LinearProgressIndicator(
              value: _chapter.settledCount / _chapter.pages.length,
            ),
          if (!_chapterMode &&
              _controller.status == ProcessingStatus.processing)
            const LinearProgressIndicator(),
          SizedBox(
            height: 34,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 12),
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
                    iconSize: 18,
                  ),
                  for (final message in messages) ...[
                    const SizedBox(width: 16),
                    message,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workspace() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final narrow = width < 640;
      final inspectorWidth = width >= 1100
          ? 320.0
          : width >= 800
          ? 260.0
          : 230.0;
      if (narrow) {
        return Column(
          children: [
            Expanded(child: _viewer()),
            const Divider(height: 1),
            SizedBox(
              height: (constraints.maxHeight * 0.42).clamp(160.0, 260.0),
              child: _inspector(width),
            ),
          ],
        );
      }
      return Row(
        children: [
          if (_chapterMode) ...[
            _navigationPanel(width >= 1000 ? 190 : 150),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: _viewer()),
          const VerticalDivider(width: 1),
          _inspector(inspectorWidth),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    // No Need Appbar
    // appBar: AppBar(title: const Text('Manga Translator')),
    body: AnimatedBuilder(
      animation: Listenable.merge([_controller, _chapter, _preferences]),
      builder: (context, _) => Column(
        children: [
          _topActions(),
          const Divider(height: 1),
          Expanded(
            child: _libraryMode
                ? LibraryView(
                    controller: _library,
                    onAddFolder: _openChapter,
                    onOpenRoot: (root) => _openLibraryRoot(root),
                    onOpenPage: (root, folder, page) =>
                        _openLibraryRoot(root, folder: folder, pageName: page),
                  )
                : _workspace(),
          ),
          const Divider(height: 1),
          _statusBar(),
        ],
      ),
    ),
  );
}
