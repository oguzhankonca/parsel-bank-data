/// Halkbank Gayrimenkul: the bank's own portal, JSON list and JSON detail
/// (ADR 0048).
library;

import 'bank_snapshot.dart';
import 'bank_text.dart';
import 'collector_http.dart';
import 'seller_catalog.dart';

const String halkbankOrigin = 'https://www.halkbankgayrimenkul.com.tr';

/// The portal returns 10 rows per page and ignores a size field.
const int _maxPages = 600;

String halkbankDetailUrl(int seriNo) => '$halkbankOrigin/ilan-detay/$seriNo';

/// One list row, or null without a seri no.
BankListingRecord? halkbankRowFromJson(Map<String, Object?> row) {
  String text(String name) {
    final Object? value = row[name];
    return value is String ? value.trim() : (value?.toString() ?? '');
  }

  final Object? seri = row['seriNo'];
  if (seri is! int) {
    return null;
  }
  final DateTime? ends = parseLocalDateTime(row['ihaleBitisTarihi']);
  final String il = text('intengoIl').isNotEmpty
      ? text('intengoIl')
      : text('il');
  final String ilce = text('intengoIlce').isNotEmpty
      ? text('intengoIlce')
      : text('ilce');
  return BankListingRecord(
    source: 'halkbank',
    sellerId: halkbankSeller.id,
    sellerName: halkbankSeller.name,
    sellerType: halkbankSeller.type,
    sellerGroup: halkbankSeller.group,
    // ilanNo repeats (0, 4, 6 ... on 2026-11-03); seriNo is the portal's id.
    ref: '$seri',
    title: text('baslik'),
    category: titleCaseTr(text('satisNiteligi')),
    subCategory: titleCaseTr(text('emlakTipAd')),
    il: titleCaseTr(il),
    ilce: titleCaseTr(ilce),
    mahalle: '',
    url: halkbankDetailUrl(seri),
    areaM2: parsePrice(row['mevcutKullanimAlani']),
    price: parsePrice(row['baslangicFiyati']),
    lastBid: _higherBid(row),
    endsAt: ends?.toIso8601String(),
    photo: _photo(row),
  );
}

double? _higherBid(Map<String, Object?> row) {
  final double? start = parsePrice(row['baslangicFiyati']);
  final double? now = parsePrice(row['fiyat']);
  if (start == null || now == null || now <= start) {
    return null;
  }
  return now;
}

String _photo(Map<Object?, Object?> row) {
  final Object? path = row['path'];
  final Object? name = row['fotoMd'];
  if (path is! String || name is! String || name.isEmpty) {
    return '';
  }
  final String folder = '${path}medium/';
  return '$halkbankOrigin/IlanWeb/FotoGoster?path=${Uri.encodeComponent(folder)}'
      '&name=${Uri.encodeComponent(name)}';
}

/// Photo key `<folder>|<medium file>` of a gallery entry. The app builds
/// `FotoGoster` URLs for the `small/` and `medium/` folders from it.
String _photoKey(Map<Object?, Object?> item) {
  final Object? path = item['path'];
  final Object? name = item['fotoMd'];
  if (path is! String || name is! String || name.isEmpty) {
    return '';
  }
  return '$path|$name';
}

/// Photo key of a `FotoGoster` URL, for the list's cover photo.
String halkbankPhotoKey(String url) {
  final Uri? uri = Uri.tryParse(url);
  final String? path = uri?.queryParameters['path'];
  final String? name = uri?.queryParameters['name'];
  if (path == null || name == null || !path.endsWith('medium/')) {
    return '';
  }
  return '${path.substring(0, path.length - 'medium/'.length)}|$name';
}

int _seriFromUrl(String url) => int.parse(url.split('/').last);

/// Every live Halkbank listing, without detail fields.
Future<List<BankListingRecord>> fetchHalkbankList(CollectorHttp http) async {
  final Map<int, BankListingRecord> out = <int, BankListingRecord>{};
  int? total;
  for (int page = 1; page <= _maxPages; page++) {
    final Object? decoded = await http.postJson(
      '$halkbankOrigin/IlanWeb/Ilan/ListeTumu',
      <String, Object>{'tab': 0, 'page': page},
    );
    final Map<Object?, Object?> data = _data(decoded);
    total ??= int.tryParse('${data['totalCount']}');
    final Object? list = data['list'];
    if (list is! List || list.isEmpty) {
      break;
    }
    for (final Object? row in list) {
      if (row is Map<String, Object?>) {
        final BankListingRecord? record = halkbankRowFromJson(row);
        if (record != null) {
          out[_seriFromUrl(record.url)] = record;
        }
      }
    }
    if (total != null && out.length >= total) {
      break;
    }
  }
  return out.values.toList();
}

Map<Object?, Object?> _data(Object? decoded) {
  if (decoded is! Map || decoded['statusCode'] != '0') {
    throw CollectorHttpException('Halkbank: unexpected reply');
  }
  final Object? data = decoded['data'];
  if (data is! Map) {
    throw CollectorHttpException('Halkbank: no data');
  }
  return data;
}

/// [row] with mahalle, ada, parsel and unit from the detail JSON.
Future<BankListingRecord> fetchHalkbankDetail(
  CollectorHttp http,
  BankListingRecord row,
) async {
  final Object? decoded = await http.postJson(
    '$halkbankOrigin/IlanWeb/Ilan/Detay',
    <String, Object>{'seriNo': _seriFromUrl(row.url)},
  );
  final Map<Object?, Object?> data = _data(decoded);
  final Object? detail = data['detay'];
  if (detail is! Map) {
    return row.copyWith(detailFetched: true);
  }
  final Object? gallery = data['galeri'];
  return applyHalkbankDetail(
    row,
    detail,
    gallery: gallery is List ? gallery : const <Object?>[],
  );
}

/// Pure part of [fetchHalkbankDetail], for tests.
BankListingRecord applyHalkbankDetail(
  BankListingRecord row,
  Map<Object?, Object?> detail, {
  List<Object?> gallery = const <Object?>[],
}) {
  String text(String name) {
    final Object? value = detail[name];
    return value == null ? '' : '$value'.trim();
  }

  final ({String ada, String parsel})? lot = parseAdaParsel(
    ada: text('ada'),
    parsel: text('parsel'),
  );
  final String mahalle = text('intengoMahalle').isNotEmpty
      ? text('intengoMahalle')
      : text('mahalleKoy');
  final DateTime? ends = parseLocalDateTime(detail['ihaleBitisTarihi']);
  final ({double latitude, double longitude})? pin = parsePin(
    detail['enlem'],
    detail['boylam'],
  );
  return row.copyWith(
    ada: lot?.ada ?? '',
    parsel: lot?.parsel ?? '',
    unit: text('bagimsizBolumNo'),
    address: text('adres'),
    mahalle: cleanMahalle(mahalle),
    endsAt: ends?.toIso8601String(),
    detailFetched: true,
    latitude: pin?.latitude,
    longitude: pin?.longitude,
    detailVersion: detailVersion,
    photos: <String>{
      halkbankPhotoKey(row.photo),
      for (final Object? item in gallery)
        if (item is Map) _photoKey(item),
    }.where((String key) => key.isNotEmpty).take(maxPhotos).toList(),
  );
}
