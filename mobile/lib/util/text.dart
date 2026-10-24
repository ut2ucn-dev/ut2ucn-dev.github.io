// Ukrainian alphabetical order. Dart compares by code point, which puts
// є, і, ї and ґ after я; this ranks them where they belong.

const _alphabet = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя";
final _rank = {for (var i = 0; i < _alphabet.length; i++) _alphabet[i]: i};

int ukCompare(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final cx = x[i];
    final cy = y[i];
    if (cx == cy) continue;
    final rx = _rank[cx];
    final ry = _rank[cy];
    if (rx != null && ry != null) return rx - ry;
    // Letters of the alphabet sort after digits/Latin, like the web list.
    if (rx != null) return 1;
    if (ry != null) return -1;
    return cx.compareTo(cy);
  }
  return x.length - y.length;
}

/// Digits and a leading + only, for tel:/viber:/t.me links.
String phoneDigits(String phone) => phone.replaceAll(RegExp(r'[^\d+]'), '');
