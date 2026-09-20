class MangaOverlayFont {
  const MangaOverlayFont(this.id, this.label, this.family);

  final String id;
  final String label;
  final String family;

  static const comicNeue = MangaOverlayFont(
    'comic_neue',
    'Comic Neue',
    'ComicNeue',
  );
  static const patrickHand = MangaOverlayFont(
    'patrick_hand',
    'Patrick Hand',
    'PatrickHand',
  );
  static const bangers = MangaOverlayFont('bangers', 'Bangers', 'Bangers');
  static const permanentMarker = MangaOverlayFont(
    'permanent_marker',
    'Permanent Marker',
    'PermanentMarker',
  );

  static const defaultFont = comicNeue;
  static const all = [comicNeue, patrickHand, bangers, permanentMarker];

  static MangaOverlayFont fromId(String? id) =>
      all.firstWhere((font) => font.id == id, orElse: () => defaultFont);
}
