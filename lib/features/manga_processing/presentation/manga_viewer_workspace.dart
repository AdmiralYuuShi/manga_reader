import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/page_analysis.dart';
import '../domain/region_edits.dart';
import '../../settings/manga_overlay_font.dart';
import 'region_geometry.dart';
import 'selected_box_overlay.dart';
import 'translation_region_overlay.dart';

/// Shared image canvas for single pages and chapter pages.
class MangaViewerWorkspace extends StatelessWidget {
  const MangaViewerWorkspace({
    super.key,
    this.file,
    this.bytes,
    required this.analysis,
    required this.edits,
    required this.selectedRegion,
    required this.showTranslation,
    required this.showDetectionBoxes,
    required this.onSelectRegion,
    required this.onPreviewBox,
    required this.onCommitBox,
    this.overlayFont = MangaOverlayFont.defaultFont,
  });

  final File? file;
  final Uint8List? bytes;
  final PageAnalysis? analysis;
  final PageEdits edits;
  final DetectedRegion? selectedRegion;
  final bool showTranslation;
  final bool showDetectionBoxes;
  final ValueChanged<String> onSelectRegion;
  final ValueChanged<RegionBox> onPreviewBox;
  final VoidCallback onCommitBox;
  final MangaOverlayFont overlayFont;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
      final result = analysis;
      final imageSize = result == null
          ? null
          : Size(result.width.toDouble(), result.height.toDouble());
      final imageRect = imageSize == null
          ? null
          : displayRectForImage(imageSize, canvasSize);
      final detectorRects = result == null
          ? <Rect>[]
          : [
              for (final region in result.regions)
                displayRectForRegion(region, imageSize!, canvasSize),
            ];

      return Stack(
        children: [
          Positioned.fill(
            child: file != null
                ? Image.file(
                    file!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        Center(child: Text('Could not display image: $error')),
                  )
                : Image.memory(bytes!, fit: BoxFit.contain),
          ),
          if (result != null)
            for (var index = 0; index < result.regions.length; index++)
              TranslationRegionOverlay(
                overlayFont: overlayFont,
                region: result.regions[index],
                rect: detectorRects[index],
                translationRect: displayRectForBox(
                  edits.effectiveBox(result.regions[index]),
                  imageSize!,
                  canvasSize,
                ),
                editedTranslatedText: edits
                    .forRegion(result.regions[index].id)
                    .translatedText,
                imageRect: imageRect!,
                obstacles: [
                  for (var other = 0; other < detectorRects.length; other++)
                    if (other != index) detectorRects[other],
                ],
                selected: selectedRegion?.id == result.regions[index].id,
                showTranslation: showTranslation,
                showDetectionBox: showDetectionBoxes,
                onTap: () => onSelectRegion(result.regions[index].id),
              ),
          if (result != null && selectedRegion != null)
            SelectedBoxOverlay(
              key: ValueKey(
                'box-${file?.path ?? identityHashCode(bytes)}-${selectedRegion!.id}',
              ),
              box: edits.effectiveBox(selectedRegion!),
              imageSize: imageSize!,
              canvasSize: canvasSize,
              onPreview: onPreviewBox,
              onCommit: onCommitBox,
            ),
        ],
      );
    },
  );
}
