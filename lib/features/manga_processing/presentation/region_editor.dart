import 'package:flutter/material.dart';

import '../domain/page_analysis.dart';
import '../domain/region_edits.dart';

class RegionEditor extends StatefulWidget {
  const RegionEditor({
    super.key,
    required this.region,
    required this.analysis,
    required this.edits,
    required this.onTranslation,
    required this.onBox,
    required this.onResetBox,
  });

  final DetectedRegion region;
  final PageAnalysis analysis;
  final PageEdits edits;
  final ValueChanged<String?> onTranslation;
  final String? Function(RegionBox) onBox;
  final VoidCallback onResetBox;

  @override
  State<RegionEditor> createState() => _RegionEditorState();
}

class _RegionEditorState extends State<RegionEditor> {
  late final TextEditingController translation;
  late final List<TextEditingController> box;
  late RegionBox _displayedBox;
  String? validation;

  @override
  void initState() {
    super.initState();
    translation = TextEditingController(
      text: widget.edits.effectiveTranslation(widget.region) ?? '',
    );
    final values = widget.edits.effectiveBox(widget.region);
    _displayedBox = values;
    box = [
      values.x,
      values.y,
      values.width,
      values.height,
    ].map((value) => TextEditingController(text: '$value')).toList();
  }

  @override
  void didUpdateWidget(covariant RegionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.edits.effectiveBox(widget.region);
    if (current == _displayedBox) return;
    _displayedBox = current;
    final values = [current.x, current.y, current.width, current.height];
    for (var i = 0; i < box.length; i++) {
      box[i].text = '${values[i]}';
    }
    validation = null;
  }

  @override
  void dispose() {
    translation.dispose();
    for (final controller in box) {
      controller.dispose();
    }
    super.dispose();
  }

  void applyBox() {
    final values = box
        .map((controller) => int.tryParse(controller.text.trim()))
        .toList();
    if (values.any((value) => value == null)) {
      setState(
        () => validation = 'Enter integer pixels for X, Y, Width, and Height.',
      );
      return;
    }
    final candidate = RegionBox(values[0]!, values[1]!, values[2]!, values[3]!);
    // The controller rebuild updates fields only when the canonical box changes.
    setState(() => validation = widget.onBox(candidate));
  }

  void resetBox() {
    widget.onResetBox();
    final original = RegionBox.detector(widget.region);
    final values = [original.x, original.y, original.width, original.height];
    for (var i = 0; i < 4; i++) {
      box[i].text = '${values[i]}';
    }
    setState(() => validation = null);
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.edits.forRegion(widget.region.id);
    return SizedBox(
      height: 235,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selected Region: ${widget.region.id}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Text('Japanese:'),
              Text(
                widget.region.errorCode != null
                    ? 'OCR failed for this region (${widget.region.errorCode})'
                    : widget.region.sourceText?.isNotEmpty == true
                    ? widget.region.sourceText!
                    : 'No text recognized',
              ),
              const Text('Indonesian:'),
              Text(
                'Machine translation: ${widget.region.translatedText ?? 'No translation available'}',
              ),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('translation-editor'),
                controller: translation,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText:
                      'Translation${edit.translatedText != null ? ' • Edited' : ''}',
                  border: const OutlineInputBorder(),
                ),
                onChanged: widget.onTranslation,
              ),
              TextButton(
                onPressed: edit.translatedText == null
                    ? null
                    : () {
                        widget.onTranslation(null);
                        translation.text = widget.region.translatedText ?? '';
                      },
                child: const Text('Reset Translation'),
              ),
              Text(
                'Text Box (original image pixels)${edit.box != null ? ' • Edited' : ''}',
              ),
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextField(
                          key: ValueKey('box-field-$i'),
                          controller: box[i],
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                          ),
                          decoration: InputDecoration(
                            labelText: ['X', 'Y', 'Width', 'Height'][i],
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (validation != null) {
                              setState(() => validation = null);
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
              if (validation != null)
                Text(
                  validation!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: applyBox,
                    child: const Text('Apply Box'),
                  ),
                  TextButton(
                    onPressed: edit.box == null ? null : resetBox,
                    child: const Text('Reset Box'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
