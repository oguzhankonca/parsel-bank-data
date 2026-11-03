/// İntengo e-satış: one public search for every seller on the platform,
/// detail pages for ada and parsel (ADR 0048).
library;

import 'bank_snapshot.dart';
import 'bank_text.dart';
import 'collector_http.dart';
import 'seller_catalog.dart';

const String intengoOrigin = 'https://gayrimenkul.intengo.com';

/// `company: intengo` returns every seller's live listings.
const int _pageSize = 200;

/// Search body the portal's own page sends.
Map<String, Object> intengoSearchBody(int page) => <String, Object>{
  'company': 'intengo',
  'cityIdList': const <int>[],
  'townIdList': const <int>[],
  'quarterIdList': const <int>[],
  'categoryIdList': const <int>[],
  'subCategoryIdList': const <int>[],
  'minPrice': '',
  'maxPrice': '',
  'realEstateNo': '',
  'sortType': 'ALL',
  'orderType': 'DEFAULT',
  'limit': _pageSize,
  'page': page,
};

/// Public detail URL. The portal routes on the trailing notice id only.
String intengoDetailUrl(String companyName, String slug, int noticeId) {
  final String safeSlug = foldText(slug)
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final String company = Uri.encodeComponent(companyName);
  return '$intengoOrigin/$company/ilan/$safeSlug-$noticeId/';
}

/// One search row, or null when it is not a property with a reference.
BankListingRecord? intengoRowFromJson(Map<String, Object?> row) {
  String text(String name) {
    final Object? value = row[name];
    return value is String ? value.trim() : '';
  }

  final Object? noticeId = row['noticeId'];
  final String ref = text('realEstateNo');
  final String company = text('companyName');
  if (noticeId is! int || ref.isEmpty || company.isEmpty) {
    return null;
  }
  final Seller seller = sellerForIntengo(company);
  final double? introductory = parsePrice(row['introductoryPrice']);
  final double? last = parsePrice(row['lastPrice']);
  final DateTime? ends = parseLocalDateTime(row['bidEndingDate']);
  return BankListingRecord(
    source: 'intengo',
    sellerId: seller.id,
    sellerName: seller.name,
    sellerType: seller.type,
    sellerGroup: seller.group,
    ref: ref,
    title: text('realEstateName'),
    category: text('categoryName'),
    subCategory: text('subCategoryName'),
    il: text('cityName'),
    ilce: text('townName'),
    mahalle: cleanMahalle(text('quarterName')),
    url: intengoDetailUrl(company, text('realEstateNameForUrl'), noticeId),
    areaM2: parsePrice(row['area']),
    price: introductory,
    lastBid: last != null && introductory != null && last > introductory
        ? last
        : null,
    endsAt: ends?.toIso8601String(),
    photo: text('mainPhotoPath'),
  );
}

/// Every live İntengo listing, without detail fields.
Future<List<BankListingRecord>> fetchIntengoList(CollectorHttp http) async {
  final List<BankListingRecord> out = <BankListingRecord>[];
  for (int page = 0; page < 100; page++) {
    final Object? decoded = await http.postJson(
      '$intengoOrigin/look-up/search',
      intengoSearchBody(page),
    );
    if (decoded is! Map) {
      throw CollectorHttpException('İntengo: not a JSON object');
    }
    final Object? response = decoded['responseObject'];
    if (response is! Map) {
      throw CollectorHttpException('İntengo: no responseObject');
    }
    final Object? content = response['content'];
    if (content is! List) {
      throw CollectorHttpException('İntengo: no content');
    }
    for (final Object? row in content) {
      if (row is Map<String, Object?>) {
        final BankListingRecord? record = intengoRowFromJson(row);
        if (record != null) {
          out.add(record);
        }
      }
    }
    if (response['last'] == true || content.isEmpty) {
      break;
    }
  }
  return out;
}

/// `<li><span>Label</span><span>Value</span></li>` pairs of a detail page.
Map<String, String> intengoDetailFields(String html) {
  final Map<String, String> fields = <String, String>{};
  final RegExp pair = RegExp(
    r'<li>\s*<span>([^<]+)</span>\s*<span>([^<]*)</span>',
  );
  for (final RegExpMatch match in pair.allMatches(html)) {
    final String label = decodeHtmlEntities(match.group(1)!).trim();
    final String value = decodeHtmlEntities(match.group(2)!).trim();
    fields.putIfAbsent(label, () => value);
  }
  return fields;
}

/// [row] with the parcel fields of its detail page.
BankListingRecord applyIntengoDetail(BankListingRecord row, String html) {
  final Map<String, String> fields = intengoDetailFields(html);
  final ({String ada, String parsel})? lot = parseAdaParsel(
    combined: fields['Ada / Parsel'] ?? fields['Ada / Parsel / Pafta'],
    ada: fields['Ada No'] ?? fields['Ada'],
    parsel: fields['Parsel No'] ?? fields['Parsel'],
  );
  final String address = fields['Adres'] ?? '';
  final String place = fields['İl / İlçe / Semt'] ?? '';
  final List<String> placeParts = place.split('/');
  final String mahalle = placeParts.length >= 3
      ? cleanMahalle(placeParts.sublist(2).join('/'))
      : row.mahalle;
  // The location tab embeds `maps?q=<lat>,<lng>`.
  final Match? map = RegExp(r'maps\?q=(-?\d+\.\d+),(-?\d+\.\d+)')
      .firstMatch(html);
  final ({double latitude, double longitude})? pin = map == null
      ? null
      : parsePin(map.group(1), map.group(2));
  final String unit =
      fields['Bağımsız Bölüm No'] ??
      fields['Bağımsız Bölüm'] ??
      unitFromAddress(address);
  return row.copyWith(
    ada: lot?.ada ?? '',
    parsel: lot?.parsel ?? '',
    unit: unit,
    address: address,
    mahalle: mahalle.isNotEmpty ? mahalle : row.mahalle,
    areaM2:
        parsePrice(fields['m² (Brüt)']) ??
        parsePrice(fields['m²']) ??
        row.areaM2,
    detailFetched: true,
    latitude: pin?.latitude,
    longitude: pin?.longitude,
    detailVersion: detailVersion,
    photos: intengoPhotos(html, cover: row.photo),
  );
}

const String intengoPhotoBase =
    'https://refiles.intengo.com/images/real-estate/';

final RegExp _intengoImage = RegExp(
  r'https://refiles\.intengo\.com/images/real-estate/([\w/-]+?)'
  r'(?:_(?:medium|large|small))?\.(jpe?g|png|webp)',
);

/// Photo key of an İntengo image URL: `136/5388/<uuid>.jpg`. The site
/// serves `_small`, `_medium` and `_large` of each key (ADR 0050).
String intengoPhotoKey(String url) {
  final Match? m = _intengoImage.firstMatch(url);
  return m == null ? '' : '${m.group(1)}.${m.group(2)}';
}

/// Gallery photo keys of a detail page, [cover] first. With a cover, only
/// images in its folder count, so another listing's thumbnail is skipped.
List<String> intengoPhotos(String html, {String cover = ''}) {
  final String coverKey = intengoPhotoKey(cover);
  final Set<String> out = <String>{if (coverKey.isNotEmpty) coverKey};
  final int slash = coverKey.lastIndexOf('/');
  final String folder = slash < 0 ? '' : coverKey.substring(0, slash + 1);
  for (final Match m in _intengoImage.allMatches(html)) {
    final String key = '${m.group(1)}.${m.group(2)}';
    if (folder.isNotEmpty && !key.startsWith(folder)) {
      continue;
    }
    out.add(key);
    if (out.length >= maxPhotos) {
      break;
    }
  }
  return out.toList();
}
