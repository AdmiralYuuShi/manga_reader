import 'package:path/path.dart' as p;

import '../chapter/chapter_persistence.dart';

enum LibraryPageStatus { pending, cached, edited }

enum LibraryStatus { notIndexed, pending, cached, partial, edited, unavailable }

class LibraryPage {
  const LibraryPage(this.name, this.status);
  final String name;
  final LibraryPageStatus status;

  Map<String, Object> toJson() => {'name': name, 'status': status.name};

  factory LibraryPage.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    if (!safePageName(name)) {
      throw const FormatException('Unsafe library page name');
    }
    return LibraryPage(
      name,
      LibraryPageStatus.values.byName(json['status'] as String),
    );
  }
}

class LibraryFolder {
  const LibraryFolder({
    required this.name,
    required this.relativePath,
    required this.pages,
    required this.children,
  });

  final String name;
  final String relativePath;
  final List<LibraryPage> pages;
  final List<LibraryFolder> children;

  LibraryCounts get counts {
    var result = LibraryCounts.zero;
    for (final page in pages) {
      result += LibraryCounts.fromPage(page.status);
    }
    for (final child in children) {
      result += child.counts;
    }
    return result;
  }

  Map<String, Object> toJson() => {
    'name': name,
    'relativePath': relativePath,
    'pages': [for (final page in pages) page.toJson()],
    'children': [for (final child in children) child.toJson()],
  };

  factory LibraryFolder.fromJson(Map<String, dynamic> json) {
    final relativePath = json['relativePath'] as String;
    if (relativePath.isNotEmpty &&
        (p.isAbsolute(relativePath) ||
            p.normalize(relativePath) == '..' ||
            p.normalize(relativePath).startsWith('..${p.separator}'))) {
      throw const FormatException('Unsafe library folder path');
    }
    return LibraryFolder(
      name: json['name'] as String,
      relativePath: relativePath,
      pages: (json['pages'] as List<dynamic>)
          .map((value) => LibraryPage.fromJson(value as Map<String, dynamic>))
          .toList(),
      children: (json['children'] as List<dynamic>)
          .map((value) => LibraryFolder.fromJson(value as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LibraryCounts {
  const LibraryCounts(this.pending, this.cached, this.edited);
  static const zero = LibraryCounts(0, 0, 0);

  final int pending;
  final int cached;
  final int edited;

  static LibraryCounts fromPage(LibraryPageStatus status) => switch (status) {
    LibraryPageStatus.pending => const LibraryCounts(1, 0, 0),
    LibraryPageStatus.cached => const LibraryCounts(0, 1, 0),
    LibraryPageStatus.edited => const LibraryCounts(0, 1, 1),
  };

  LibraryCounts operator +(LibraryCounts other) => LibraryCounts(
    pending + other.pending,
    cached + other.cached,
    edited + other.edited,
  );

  LibraryStatus get status {
    if (edited > 0) return LibraryStatus.edited;
    if (cached > 0 && pending > 0) return LibraryStatus.partial;
    if (cached > 0) return LibraryStatus.cached;
    return LibraryStatus.pending;
  }
}

class LibraryRoot {
  const LibraryRoot({
    required this.id,
    required this.path,
    required this.name,
    this.snapshot,
    this.indexedAt,
    this.available = true,
  });

  final String id;
  final String path;
  final String name;
  final LibraryFolder? snapshot;
  final DateTime? indexedAt;
  final bool available;

  LibraryStatus get status => !available
      ? LibraryStatus.unavailable
      : snapshot == null
      ? LibraryStatus.notIndexed
      : snapshot!.counts.status;

  LibraryRoot copyWith({
    LibraryFolder? snapshot,
    DateTime? indexedAt,
    bool? available,
  }) => LibraryRoot(
    id: id,
    path: path,
    name: name,
    snapshot: snapshot ?? this.snapshot,
    indexedAt: indexedAt ?? this.indexedAt,
    available: available ?? this.available,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'indexedAt': indexedAt?.toUtc().toIso8601String(),
    'availableAtLastCheck': available,
    'snapshot': snapshot?.toJson(),
  };

  factory LibraryRoot.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String;
    final id = json['id'] as String;
    if (!p.isAbsolute(path) || chapterStorageId(path) != id) {
      throw const FormatException('Invalid library root identity');
    }
    final snapshot = json['snapshot'];
    return LibraryRoot(
      id: id,
      path: path,
      name: json['name'] as String,
      indexedAt: switch (json['indexedAt']) {
        final String value => DateTime.parse(value),
        _ => null,
      },
      available: json['availableAtLastCheck'] as bool? ?? true,
      snapshot: snapshot == null
          ? null
          : LibraryFolder.fromJson(snapshot as Map<String, dynamic>),
    );
  }
}

String libraryStatusLabel(LibraryStatus status) => switch (status) {
  LibraryStatus.notIndexed => 'Not indexed',
  LibraryStatus.pending => 'Pending',
  LibraryStatus.cached => 'Cached',
  LibraryStatus.partial => 'Partial',
  LibraryStatus.edited => 'Edited',
  LibraryStatus.unavailable => 'Unavailable',
};

String libraryPageStatusLabel(LibraryPageStatus status) => switch (status) {
  LibraryPageStatus.pending => 'Pending',
  LibraryPageStatus.cached => 'Cached',
  LibraryPageStatus.edited => 'Edited',
};
