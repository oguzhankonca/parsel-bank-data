/// Text helpers shared by the bank listing collector (ADR 0048).
///
/// Pure functions, no I/O, so the app tests can cover them too.
library;

/// Lower-case ASCII fold for Turkish text: `İSTANBUL` and `istanbul` match.
String foldText(String value) {
  final StringBuffer out = StringBuffer();
  for (final int rune in value.runes) {
    final String char = String.fromCharCode(rune);
    out.write(switch (char) {
      'İ' || 'I' || 'ı' || 'i' => 'i',
      'Ş' || 'ş' => 's',
      'Ğ' || 'ğ' => 'g',
      'Ü' || 'ü' => 'u',
      'Ö' || 'ö' => 'o',
      'Ç' || 'ç' => 'c',
      'Â' || 'â' => 'a',
      'Î' || 'î' => 'i',
      'Û' || 'û' => 'u',
      _ => char.toLowerCase(),
    });
  }
  // A dotted capital İ lower-cased by some portals leaves U+0307 behind.
  return out.toString().replaceAll('̇', '').trim();
}

/// Title case for an all-caps place name: `DÖŞEMEALTI` -> `Döşemealtı`.
String titleCaseTr(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return trimmed
      .split(RegExp(r'\s+'))
      .map((String word) {
        if (word.isEmpty) {
          return word;
        }
        final String head = _upperTr(word.substring(0, 1));
        final String tail = _lowerTr(word.substring(1));
        return '$head$tail';
      })
      .join(' ');
}

String _upperTr(String value) =>
    value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

String _lowerTr(String value) =>
    value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Platform reference without its prefix and leading zeros.
///
/// İntengo writes Akbank `401991` as `P-401991` and QNB `7637` as
/// `QNB-7637`. Gayrimenko writes `QNB7643`. The bank's own number is what
/// links one property across platforms.
String normalizeRef(String value) {
  String ref = value.trim();
  ref = ref.replaceFirst(RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşü]+-?'), '');
  ref = ref.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return ref;
}

/// Mahalle name without the platform's district prefix and suffix.
///
/// İntengo sends `Köyler-Balaban Mh.` and `Merkez-Cumhuriyet Mah.`; Halkbank
/// sends `YEŞİLBAYIR`. All become a plain title-case name.
String cleanMahalle(String? value) {
  String text = (value ?? '').trim();
  if (text.isEmpty) {
    return '';
  }
  final int dash = text.lastIndexOf('-');
  if (dash > 0 && dash < text.length - 1) {
    text = text.substring(dash + 1);
  }
  text = text.replaceAll(
    RegExp(
      r'\s+(mahallesi|mah\.?|mh\.?|köyü|koyu|beldesi)\s*$',
      caseSensitive: false,
    ),
    '',
  );
  text = text.trim();
  final bool allCaps = text == text.toUpperCase();
  return allCaps ? titleCaseTr(text) : text;
}

/// Ada and parsel from one of the field shapes the portals use.
///
/// Accepts `1771 / 29`, `1771/29`, `1771 / 29 / 25F3B` and separate values.
/// Returns null when parsel is missing. Ada `0` stays: TKGM uses it for
/// parcels outside an ada.
({String ada, String parsel})? parseAdaParsel({
  String? combined,
  String? ada,
  String? parsel,
}) {
  final String joined = (combined ?? '').trim();
  if (joined.isNotEmpty) {
    final List<String> parts = joined
        .split('/')
        .map((String part) => part.trim())
        .toList();
    if (parts.length >= 2 && _digits(parts[1]).isNotEmpty) {
      return (ada: _digits(parts[0]), parsel: _digits(parts[1]));
    }
  }
  final String p = _digits(parsel ?? '');
  if (p.isEmpty) {
    return null;
  }
  return (ada: _digits(ada ?? ''), parsel: p);
}

String _digits(String value) {
  final Match? match = RegExp(r'\d+').firstMatch(value);
  return match?.group(0) ?? '';
}

/// Bağımsız bölüm number from an address line, or empty.
///
/// Reads `D:3`, `DAİRE: 12`, `BB: 1`, `BB No: 1,16` and
/// `Bağımsız Bölüm No 4`.
String unitFromAddress(String? address) {
  final String text = address ?? '';
  final List<RegExp> patterns = <RegExp>[
    RegExp(r'BB\s*(?:No)?\s*:?\s*([\d,]+)', caseSensitive: false),
    RegExp(r'Ba[ğg][ıi]ms[ıi]z\s+B[öo]l[üu]m\s*(?:No)?\s*:?\s*([\d,]+)',
        caseSensitive: false),
    RegExp(r'\bD(?:A[İI]RE)?\s*:\s*(\d+)', caseSensitive: false),
  ];
  for (final RegExp pattern in patterns) {
    final Match? match = pattern.firstMatch(text);
    if (match != null) {
      return match.group(1)!.replaceAll(RegExp(r',$'), '');
    }
  }
  return '';
}

/// Parses `14400000.0`, `1.44E+7`, `17500000.00` and `27.000.000 TL`.
double? parsePrice(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is! String) {
    return null;
  }
  final String text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  final double? plain = double.tryParse(text);
  if (plain != null) {
    return plain;
  }
  final String digits = text
      .replaceAll(RegExp(r'[^\d,]'), '')
      .replaceAll(',', '.');
  return double.tryParse(digits);
}

/// Parses `2026-11-05 15:34:59`, `2026-11-04 10:14:46.000` and ISO strings.
DateTime? parseLocalDateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  final String text = value.trim().replaceFirst(' ', 'T');
  return DateTime.tryParse(text);
}

/// `yyyy-mm-dd` for [time]'s calendar day.
String dayKey(DateTime time) {
  final String month = time.month.toString().padLeft(2, '0');
  final String day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}

/// Minimal HTML entity decoding for the fields the collector reads.
String decodeHtmlEntities(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (Match m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (Match m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
