import 'dart:io';

import 'package:path/path.dart' as p;

import 'chapter_controller.dart';
import 'chapter_persistence.dart';

/// A source directory. Direct image files belong to this folder's chapter;
/// child folders retain their own pages and position in the source tree.
class SourceFolder {
  const SourceFolder({
    required this.path,
    required this.relativePath,
    required this.name,
    required this.pageNames,
    required this.children,
  });

  final String path;
  final String relativePath;
  final String name;
  final List<String> pageNames;
  final List<SourceFolder> children;

  bool get isChapter => pageNames.isNotEmpty;
}

class SourceHierarchy {
  const SourceHierarchy(this.root, this.skippedFolders);

  final SourceFolder root;
  final int skippedFolders;

  List<SourceFolder> get chapters {
    final result = <SourceFolder>[];
    void visit(SourceFolder folder) {
      if (folder.isChapter) {
        result.add(folder);
      }
      for (final child in folder.children) {
        visit(child);
      }
    }

    visit(root);
    return result;
  }

  static Future<SourceHierarchy> discover(String selectedPath) async {
    final rootPath = p.normalize(p.absolute(selectedPath));
    final rootDirectory = Directory(rootPath);
    // A missing or inaccessible selected root is a user-visible import error.
    final rootCanonical = p.normalize(
      await rootDirectory.resolveSymbolicLinks(),
    );
    final visited = <String>{};
    var skipped = 0;

    Future<SourceFolder?> scan(
      Directory directory,
      String relativePath, {
      bool root = false,
    }) async {
      try {
        final canonical = p.normalize(await directory.resolveSymbolicLinks());
        if ((canonical != rootCanonical &&
                !p.isWithin(rootCanonical, canonical)) ||
            !visited.add(normalizeSourcePath(canonical))) {
          skipped++;
          return null;
        }
        final files = <File>[];
        final folders = <Directory>[];
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is Link ||
              await FileSystemEntity.type(entry.path, followLinks: false) ==
                  FileSystemEntityType.link) {
            continue;
          }
          if (entry is File && isChapterImage(entry.path)) files.add(entry);
          if (entry is Directory) folders.add(entry);
        }
        folders.sort(
          (a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)),
        );
        final children = <SourceFolder>[];
        for (final child in folders) {
          final childRelative = relativePath.isEmpty
              ? p.basename(child.path)
              : p.join(relativePath, p.basename(child.path));
          final found = await scan(child, childRelative);
          if (found != null) children.add(found);
        }
        final pages = orderedChapterFiles(
          files,
        ).map((file) => p.basename(file.path)).toList();
        if (!root && pages.isEmpty && children.isEmpty) return null;
        return SourceFolder(
          path: directory.path,
          relativePath: relativePath,
          name: p.basename(directory.path),
          pageNames: pages,
          children: children,
        );
      } on FileSystemException {
        if (root) rethrow;
        skipped++;
        return null;
      }
    }

    final root = await scan(rootDirectory, '', root: true);
    return SourceHierarchy(root!, skipped);
  }
}
