import 'package:flutter/material.dart';

import '../domain/page_analysis.dart';
import '../../settings/manga_overlay_font.dart';
import 'translation_overlay_layout.dart';

class TranslationRegionOverlay extends StatelessWidget {
  const TranslationRegionOverlay({
    super.key,
    required this.region,
    required this.rect,
    this.translationRect,
    this.sourceTranslationRect,
    this.sourceImageRect,
    this.sourceObstacles,
    this.editedTranslatedText,
    required this.imageRect,
    required this.obstacles,
    required this.selected,
    required this.showTranslation,
    required this.showDetectionBox,
    required this.onTap,
    this.overlayFont = MangaOverlayFont.defaultFont,
  });

  final DetectedRegion region;
  final Rect rect;
  final Rect? translationRect;

  /// Original-image pixels. Used for temporary expansion before display mapping.
  final Rect? sourceTranslationRect;
  final Rect? sourceImageRect;
  final List<Rect>? sourceObstacles;
  final String? editedTranslatedText;
  final Rect imageRect;
  final List<Rect> obstacles;
  final bool selected;
  final bool showTranslation;
  final bool showDetectionBox;
  final VoidCallback onTap;
  final MangaOverlayFont overlayFont;

  @override
  Widget build(BuildContext context) {
    final sourceBounds = sourceImageRect;
    final scale = sourceBounds == null
        ? 1.0
        : imageRect.width / sourceBounds.width;
    Rect toDisplay(Rect source) => sourceBounds == null
        ? source
        : Rect.fromLTWH(
            imageRect.left + (source.left - sourceBounds.left) * scale,
            imageRect.top + (source.top - sourceBounds.top) * scale,
            source.width * scale,
            source.height * scale,
          );
    final baseRect = sourceTranslationRect ?? translationRect ?? rect;
    final layoutBounds = sourceBounds ?? imageRect;
    final text = editedTranslatedText ?? region.translatedText;
    final visibleText =
        showTranslation &&
        (region.errorCode == null || editedTranslatedText != null) &&
        (region.translationErrorCode == null || editedTranslatedText != null) &&
        text?.trim().isNotEmpty == true &&
        baseRect.width > 0 &&
        baseRect.height > 0;
    final baseStyle = TextStyle(
      inherit: false,
      color: Colors.black87,
      height: 1.1,
      fontWeight: FontWeight.normal,
      letterSpacing: 0,
      fontFamily: overlayFont.family,
    );
    final layout = visibleText
        ? findTranslationOverlayLayout(
            text: text!,
            detectorRect: baseRect,
            imageRect: layoutBounds,
            obstacles: sourceObstacles ?? obstacles,
            style: baseStyle,
            direction: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            displayScale: scale,
          )
        : TranslationOverlayLayout(baseRect, minimumOverlayFontSize, false);
    final displayedRect = sourceTranslationRect == null
        ? (visibleText ? layout.rect : baseRect)
        : toDisplay(layout.rect);
    final translation = Text(
      text ?? '',
      key: ValueKey('translation-text-${region.id}'),
      textAlign: TextAlign.center,
      softWrap: true,
      style: baseStyle.copyWith(fontSize: layout.fontSize),
    );

    return Stack(
      children: [
        Positioned.fromRect(
          rect: displayedRect,
          child: GestureDetector(
            key: ValueKey(region.id),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(overlayPadding),
                decoration: BoxDecoration(
                  color: visibleText
                      ? Colors.white.withValues(alpha: 0.94)
                      : showDetectionBox || selected
                      ? (selected ? Colors.amber : Colors.red).withValues(
                          alpha: 0.15,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selected ? Colors.amber : Colors.transparent,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: visibleText
                    ? layout.cannotFit
                          ? Tooltip(
                              message: text!,
                              child: Text(
                                'Translation exceeds page. Select the region to read it in the Inspector.',
                                textAlign: TextAlign.center,
                                style: baseStyle.copyWith(
                                  fontSize: minimumOverlayFontSize,
                                ),
                              ),
                            )
                          : translation
                    : null,
              ),
            ),
          ),
        ),
        if (showDetectionBox || selected)
          Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: Container(
                key: ValueKey('detector-box-${region.id}'),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? Colors.amber : Colors.red,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
