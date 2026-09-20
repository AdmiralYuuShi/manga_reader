import 'dart:math' as math;

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
    final baseRect = translationRect ?? rect;
    final text = editedTranslatedText ?? region.translatedText;
    final visibleText =
        showTranslation &&
        (region.errorCode == null || editedTranslatedText != null) &&
        (region.translationErrorCode == null || editedTranslatedText != null) &&
        (region.sourceText?.trim().isNotEmpty == true ||
            editedTranslatedText != null) &&
        text?.trim().isNotEmpty == true &&
        baseRect.width >= minimumOverlayWidth &&
        baseRect.height >= minimumOverlayHeight;
    final baseStyle = TextStyle(
      color: Colors.black87,
      height: 1.1,
      fontFamily: overlayFont.family,
    );
    final layout = visibleText
        ? findTranslationOverlayLayout(
            text: text!,
            detectorRect: baseRect,
            imageRect: imageRect,
            obstacles: obstacles,
            style: baseStyle,
            direction: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )
        : TranslationOverlayLayout(baseRect, minimumOverlayFontSize, false);
    final displayedRect = visibleText ? layout.rect : baseRect;
    final availableHeight = math.max(
      0,
      displayedRect.height - overlayPadding * 2,
    );
    final maxLines = math.max(
      1,
      (availableHeight / (layout.fontSize * 1.1)).floor(),
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
                    ? Text(
                        text!,
                        key: ValueKey('translation-text-${region.id}'),
                        textAlign: TextAlign.center,
                        softWrap: true,
                        maxLines: maxLines,
                        overflow: layout.requiresEllipsis
                            ? TextOverflow.ellipsis
                            : TextOverflow.clip,
                        style: baseStyle.copyWith(fontSize: layout.fontSize),
                      )
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
