import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../manga_processing/domain/page_analysis.dart';
import '../manga_processing/domain/region_edits.dart';

const currentPersistenceSchemaVersion = 1;
const currentAnalysisCacheVersion = 1;
const currentTargetLanguage = 'id';

String normalizeSourcePath(String path) {
  final normalized = p.normalize(p.absolute(path));
  return Platform.isWindows
      ? normalized.replaceAll('\\', '/').toLowerCase()
      : normalized;
}

String chapterStorageId(String path) =>
    sha256.convert(utf8.encode(normalizeSourcePath(path))).toString();

bool safePageName(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains('/') &&
    !name.contains('\\') &&
    !name.contains(':') &&
    !p.isAbsolute(name);

class SourceFingerprint {
  const SourceFingerprint(this.size, this.modifiedMicros, this.sha256Hash);
  final int size;
  final int modifiedMicros;
  final String sha256Hash;

  Map<String, Object> toJson() => {
    'size': size,
    'modifiedMicros': modifiedMicros,
    'sha256': sha256Hash,
  };

  static SourceFingerprint fromJson(Map<String, dynamic> json) {
    final size = json['size'] as int;
    final modified = json['modifiedMicros'] as int;
    final hash = json['sha256'] as String;
    if (size < 0 || modified < 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid source fingerprint');
    }
    return SourceFingerprint(size, modified, hash);
  }
}

Future<SourceFingerprint> fingerprintFile(File file) async {
  final stat = await file.stat();
  final digest = await sha256.bind(file.openRead()).first;
  return SourceFingerprint(
    stat.size,
    stat.modified.microsecondsSinceEpoch,
    digest.toString(),
  );
}

class PersistedPage {
  PersistedPage({
    required this.name,
    required this.fingerprint,
    required this.analysis,
    required this.edits,
    this.duration,
  });
  final String name;
  final SourceFingerprint fingerprint;
  final PageAnalysis analysis;
  final PageEdits edits;
  final Duration? duration;

  Map<String, Object?> toJson() => {
    'relativePath': name,
    'sourceFingerprint': fingerprint.toJson(),
    'analysisCacheVersion': currentAnalysisCacheVersion,
    'targetLanguage': currentTargetLanguage,
    'analysis': {
      'width': analysis.width,
      'height': analysis.height,
      'regions': [
        for (final r in analysis.regions)
          {
            'id': r.id,
            'bbox': {'x': r.x, 'y': r.y, 'width': r.width, 'height': r.height},
            'sourceLanguage': r.sourceLanguage,
            'sourceText': r.sourceText,
            'ocrErrorCode': r.errorCode,
            'targetLanguage': r.targetLanguage,
            'machineTranslatedText': r.translatedText,
            'translationErrorCode': r.translationErrorCode,
          },
      ],
    },
    'userEdits': {
      for (final entry in edits.entries)
        entry.key: {
          'translatedText': entry.value.translatedText,
          'box': entry.value.box == null
              ? null
              : {
                  'x': entry.value.box!.x,
                  'y': entry.value.box!.y,
                  'width': entry.value.box!.width,
                  'height': entry.value.box!.height,
                },
        },
    },
    'durationMicros': duration?.inMicroseconds,
  };

  static PersistedPage fromJson(Map<String, dynamic> json) {
    final name = json['relativePath'] as String;
    if (!safePageName(name)) throw const FormatException('Unsafe page path');
    final rawAnalysis = json['analysis'] as Map<String, dynamic>;
    final regions = (rawAnalysis['regions'] as List<dynamic>).map((value) {
      final r = value as Map<String, dynamic>;
      final box = r['bbox'] as Map<String, dynamic>;
      return DetectedRegion(
        id: r['id'] as String,
        x: box['x'] as int,
        y: box['y'] as int,
        width: box['width'] as int,
        height: box['height'] as int,
        sourceLanguage: r['sourceLanguage'] as String?,
        sourceText: r['sourceText'] as String?,
        errorCode: r['ocrErrorCode'] as String?,
        targetLanguage: r['targetLanguage'] as String?,
        translatedText: r['machineTranslatedText'] as String?,
        translationErrorCode: r['translationErrorCode'] as String?,
      );
    }).toList();
    final analysis = PageAnalysis(
      width: rawAnalysis['width'] as int,
      height: rawAnalysis['height'] as int,
      regions: regions,
    );
    if (analysis.width <= 0 || analysis.height <= 0) {
      throw const FormatException('Invalid image dimensions');
    }
    final ids = <String>{};
    for (final region in regions) {
      if (region.id.isEmpty ||
          !ids.add(region.id) ||
          region.x < 0 ||
          region.y < 0 ||
          region.width <= 0 ||
          region.height <= 0 ||
          region.x + region.width > analysis.width ||
          region.y + region.height > analysis.height) {
        throw const FormatException('Invalid cached region geometry');
      }
    }
    final edits = PageEdits();
    final rawEdits = json['userEdits'] as Map<String, dynamic>? ?? {};
    for (final region in regions) {
      final raw = rawEdits[region.id];
      if (raw is! Map<String, dynamic>) continue;
      if (raw.containsKey('translatedText')) {
        edits.setTranslation(region.id, raw['translatedText'] as String?);
      }
      final rawBox = raw['box'];
      if (rawBox is Map<String, dynamic>) {
        final box = RegionBox(
          rawBox['x'] as int,
          rawBox['y'] as int,
          rawBox['width'] as int,
          rawBox['height'] as int,
        );
        if (validateRegionBox(box, analysis) == null) {
          edits.setBox(region.id, box);
        }
      }
    }
    final micros = json['durationMicros'] as int?;
    return PersistedPage(
      name: name,
      fingerprint: SourceFingerprint.fromJson(
        json['sourceFingerprint'] as Map<String, dynamic>,
      ),
      analysis: analysis,
      edits: edits,
      duration: micros == null ? null : Duration(microseconds: micros),
    );
  }
}

class LoadedChapter {
  LoadedChapter(this.pages, {this.warning, this.writable = true});
  final Map<String, PersistedPage> pages;
  final String? warning;
  final bool writable;
}

class ChapterPersistenceRepository {
  ChapterPersistenceRepository(this.root);
  final Directory root;

  File chapterFile(String sourceDirectory) => File(
    p.join(
      root.path,
      'chapters',
      chapterStorageId(sourceDirectory),
      'chapter.json',
    ),
  );

  Future<LoadedChapter> load(String sourceDirectory) async {
    final file = chapterFile(sourceDirectory);
    final backup = File('${file.path}.bak');
    final candidate = await file.exists() ? file : backup;
    if (!await candidate.exists()) return LoadedChapter({});
    try {
      final document =
          jsonDecode(await candidate.readAsString()) as Map<String, dynamic>;
      if (document['schemaVersion'] != currentPersistenceSchemaVersion) {
        return LoadedChapter(
          {},
          warning:
              'Unsupported chapter cache schema; results were not restored.',
          writable: false,
        );
      }
      if (document['sourceDirectory'] != normalizeSourcePath(sourceDirectory)) {
        return LoadedChapter(
          {},
          warning: 'Chapter cache path does not match this folder.',
          writable: false,
        );
      }
      final entries = document['pages'] as List<dynamic>;
      final pages = <String, PersistedPage>{};
      var invalid = false;
      for (final value in entries) {
        try {
          final raw = value as Map<String, dynamic>;
          final page = PersistedPage.fromJson(raw);
          if (raw['analysisCacheVersion'] != currentAnalysisCacheVersion ||
              raw['targetLanguage'] != currentTargetLanguage) {
            invalid = true;
            continue;
          }
          pages[page.name] = page;
        } catch (_) {
          invalid = true;
        }
      }
      return LoadedChapter(
        pages,
        warning: invalid
            ? 'Some cached pages were invalid or incompatible and will be processed again.'
            : null,
      );
    } catch (_) {
      return LoadedChapter(
        {},
        warning:
            'Chapter cache is corrupt or unreadable; processing can continue, but saving is disabled to protect it.',
        writable: false,
      );
    }
  }

  Future<void> savePage(String sourceDirectory, PersistedPage page) async {
    if (!safePageName(page.name)) {
      throw const FormatException('Unsafe page path');
    }
    final file = chapterFile(sourceDirectory);
    final backup = File('${file.path}.bak');
    final existing = await _readRawDocument(sourceDirectory);
    final pages = <String, Map<String, dynamic>>{};
    for (final value in (existing?['pages'] as List<dynamic>? ?? [])) {
      if (value is Map<String, dynamic> &&
          value['relativePath'] is String &&
          safePageName(value['relativePath'] as String)) {
        pages[value['relativePath'] as String] = value;
      }
    }
    pages[page.name] = page.toJson();
    final document = {
      'schemaVersion': currentPersistenceSchemaVersion,
      'sourceDirectory': normalizeSourcePath(sourceDirectory),
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'pages': pages.values.toList(),
    };
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(document), flush: true);
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

  Future<Map<String, dynamic>?> _readRawDocument(String sourceDirectory) async {
    final file = chapterFile(sourceDirectory);
    final backup = File('${file.path}.bak');
    final candidate = await file.exists() ? file : backup;
    if (!await candidate.exists()) return null;
    final document =
        jsonDecode(await candidate.readAsString()) as Map<String, dynamic>;
    if (document['schemaVersion'] != currentPersistenceSchemaVersion ||
        document['sourceDirectory'] != normalizeSourcePath(sourceDirectory) ||
        document['pages'] is! List) {
      throw const FormatException('Unsupported or invalid chapter cache');
    }
    return document;
  }
}
