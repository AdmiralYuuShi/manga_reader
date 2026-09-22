import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../chapter/chapter_persistence.dart';
import '../chapter/source_hierarchy.dart';
import 'library_index_repository.dart';
import 'library_model.dart';

class LibraryController extends ChangeNotifier {
  LibraryController({
    LibraryIndexRepository? index,
    Future<ChapterPersistenceRepository> Function()? chapterPersistence,
  }) : _index = index ?? LibraryIndexRepository(),
       _chapterPersistence = chapterPersistence ?? _defaultChapterPersistence;

  final LibraryIndexRepository _index;
  final Future<ChapterPersistenceRepository> Function() _chapterPersistence;
  final List<LibraryRoot> _roots = [];
  final Set<String> _refreshing = {};
  Future<void>? _loading;
  Future<void> _saveTail = Future<void>.value();
  String? warning;
  bool writable = true;
  bool _disposed = false;

  List<LibraryRoot> get roots => List.unmodifiable(_roots);
  bool get loaded => _loading != null;
  bool isRefreshing(String id) => _refreshing.contains(id);

  static Future<ChapterPersistenceRepository>
  _defaultChapterPersistence() async =>
      ChapterPersistenceRepository(await getApplicationSupportDirectory());

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final result = await _index.load();
      _roots
        ..clear()
        ..addAll(result.roots);
      warning = result.warning;
      writable = result.writable;
      _notify();
      unawaited(checkAvailability());
    } catch (error) {
      warning = 'Could not load the library index: $error';
      writable = false;
      _notify();
    }
  }

  Future<void> checkAvailability() async {
    var changed = false;
    for (var i = 0; i < _roots.length; i++) {
      final root = _roots[i];
      bool exists;
      try {
        exists = await Directory(root.path).exists();
      } catch (_) {
        exists = false;
      }
      if (exists != root.available) {
        _roots[i] = root.copyWith(available: exists);
        changed = true;
      }
    }
    if (changed) _notify();
  }

  Future<LibraryRoot> register(SourceHierarchy hierarchy) async {
    await load();
    if (!writable) {
      throw StateError(
        'Library index is read-only; existing data was preserved.',
      );
    }
    if (hierarchy.chapters.isEmpty) {
      throw StateError('No chapters were found in this folder.');
    }
    final path = p.normalize(p.absolute(hierarchy.root.path));
    final id = chapterStorageId(path);
    final index = _roots.indexWhere((entry) => entry.id == id);
    final root = index >= 0
        ? _roots[index].copyWith(available: true)
        : LibraryRoot(id: id, path: path, name: p.basename(path));
    if (index >= 0) {
      _roots[index] = root;
    } else {
      _roots.add(root);
    }
    _notify();
    await _persist();
    return root;
  }

  Future<void> refresh(String id, {SourceHierarchy? discovered}) async {
    await load();
    final initial = _roots.indexWhere((entry) => entry.id == id);
    if (initial < 0 || !_refreshing.add(id)) return;
    _notify();
    try {
      final root = _roots[initial];
      final hierarchy = discovered ?? await SourceHierarchy.discover(root.path);
      final persistence = await _chapterPersistence();
      final snapshot = await _snapshotFolder(hierarchy.root, persistence);
      final current = _roots.indexWhere((entry) => entry.id == id);
      if (current < 0) return;
      _roots[current] = _roots[current].copyWith(
        snapshot: snapshot,
        indexedAt: DateTime.now().toUtc(),
        available: true,
      );
      warning = hierarchy.skippedFolders > 0
          ? '${hierarchy.skippedFolders} nested folders could not be indexed.'
          : null;
      _notify();
      if (writable) await _persist();
    } on FileSystemException {
      final current = _roots.indexWhere((entry) => entry.id == id);
      if (current >= 0) {
        _roots[current] = _roots[current].copyWith(available: false);
        _notify();
        if (writable) await _persist();
      }
    } catch (error) {
      warning = 'Could not refresh ${_roots[initial].name}: $error';
      _notify();
    } finally {
      _refreshing.remove(id);
      _notify();
    }
  }

  Future<LibraryFolder> _snapshotFolder(
    SourceFolder folder,
    ChapterPersistenceRepository persistence,
  ) async {
    final cached = folder.isChapter
        ? (await persistence.load(folder.path)).pages
        : <String, PersistedPage>{};
    final pages = <LibraryPage>[];
    for (final name in folder.pageNames) {
      var status = LibraryPageStatus.pending;
      final saved = cached[name];
      if (saved != null) {
        try {
          final current = await fingerprintFile(
            File(p.join(folder.path, name)),
          );
          if (current.sha256Hash == saved.fingerprint.sha256Hash) {
            status = saved.edits.hasEdits
                ? LibraryPageStatus.edited
                : LibraryPageStatus.cached;
          }
        } catch (_) {
          // A vanished or unreadable source page cannot have a valid cache.
        }
      }
      pages.add(LibraryPage(name, status));
    }
    final children = <LibraryFolder>[];
    for (final child in folder.children) {
      children.add(await _snapshotFolder(child, persistence));
    }
    return LibraryFolder(
      name: folder.name,
      relativePath: folder.relativePath,
      pages: pages,
      children: children,
    );
  }

  Future<void> remove(String id) async {
    await load();
    if (!writable) {
      throw StateError(
        'Library index is read-only; existing data was preserved.',
      );
    }
    _roots.removeWhere((entry) => entry.id == id);
    _notify();
    await _persist();
  }

  Future<void> refreshAll() async {
    await load();
    for (final root in roots) {
      await refresh(root.id);
    }
  }

  Future<void> _persist() {
    final snapshot = List<LibraryRoot>.of(_roots);
    _saveTail = _saveTail
        .catchError((Object _) {})
        .then((_) => _index.save(snapshot));
    return _saveTail;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
