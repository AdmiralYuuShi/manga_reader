import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_model.dart';

const libraryIndexSchemaVersion = 1;

class LoadedLibraryIndex {
  const LoadedLibraryIndex(this.roots, {this.warning, this.writable = true});
  final List<LibraryRoot> roots;
  final String? warning;
  final bool writable;
}

class LibraryIndexRepository {
  LibraryIndexRepository({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<File> indexFile() async =>
      File(p.join((await _supportDirectory()).path, 'library_index.json'));

  Future<LoadedLibraryIndex> load() async {
    final file = await indexFile();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) {
      return const LoadedLibraryIndex([]);
    }
    for (final candidate in [file, backup]) {
      if (!await candidate.exists()) continue;
      try {
        final raw =
            jsonDecode(await candidate.readAsString()) as Map<String, dynamic>;
        if (raw['schemaVersion'] != libraryIndexSchemaVersion) {
          return const LoadedLibraryIndex(
            [],
            warning:
                'Unsupported library index version; the file was preserved.',
            writable: false,
          );
        }
        final roots = (raw['roots'] as List<dynamic>)
            .map((value) => LibraryRoot.fromJson(value as Map<String, dynamic>))
            .toList();
        final unique = <String, LibraryRoot>{};
        for (final root in roots) {
          unique[root.id] = root;
        }
        return LoadedLibraryIndex(
          unique.values.toList(),
          warning: candidate.path == backup.path
              ? 'Library index recovered from backup; refresh and save it.'
              : null,
        );
      } catch (_) {
        // Try the backup before treating the index as unreadable.
      }
    }
    return const LoadedLibraryIndex(
      [],
      warning: 'Library index is unreadable; the files were preserved.',
      writable: false,
    );
  }

  Future<void> save(List<LibraryRoot> roots) async {
    final file = await indexFile();
    final backup = File('${file.path}.bak');
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schemaVersion': libraryIndexSchemaVersion,
        'roots': [for (final root in roots) root.toJson()],
      }),
      flush: true,
    );
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await temporary.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
  }
}
