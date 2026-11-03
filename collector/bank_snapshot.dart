/// Snapshot format and day-over-day merge for bank listings (ADR 0048).
///
/// The collector runs once a day. It reads yesterday's snapshot, fetches the
/// sources, and writes one file that carries each listing's first-seen day,
/// price changes and removal day. The app only reads that file.
library;

import 'bank_text.dart';
import 'seller_catalog.dart';

/// Bump when a field changes meaning. The app refuses other versions.
const int snapshotSchema = 1;

/// Removed listings stay this many days so the app can show "kaldırıldı".
const int removedKeepDays = 14;

/// One price on the day it was first seen.
class PricePoint {
  const PricePoint(this.day, this.price);

  final String day;
  final double price;

  List<Object> toJson() => <Object>[day, price];

  static PricePoint? fromJson(Object? value) {
    if (value is! List || value.length != 2) {
      return null;
    }
    final Object? day = value[0];
    final double? price = parsePrice(value[1]);
    if (day is! String || price == null) {
      return null;
    }
    return PricePoint(day, price);
  }
}

/// One property for sale, as written to `snapshot.json`.
class BankListingRecord {
  const BankListingRecord({
    required this.source,
    required this.sellerId,
    required this.sellerName,
    required this.sellerType,
    required this.sellerGroup,
    required this.ref,
    required this.title,
    required this.category,
    required this.subCategory,
    required this.il,
    required this.ilce,
    required this.mahalle,
    required this.url,
    this.ada = '',
    this.parsel = '',
    this.unit = '',
    this.address = '',
    this.areaM2,
    this.price,
    this.lastBid,
    this.endsAt,
    this.photo = '',
    this.detailFetched = false,
    this.firstSeen = '',
    this.lastSeen = '',
    this.removedOn,
    this.prices = const <PricePoint>[],
    this.alsoAt = const <String>[],
  });

  /// `intengo`, `halkbank`.
  final String source;
  final String sellerId;
  final String sellerName;
  final SellerType sellerType;
  final String sellerGroup;

  /// Reference as the platform prints it, e.g. `P-401991`.
  final String ref;
  final String title;
  final String category;
  final String subCategory;
  final String il;
  final String ilce;
  final String mahalle;
  final String url;
  final String ada;
  final String parsel;

  /// Bağımsız bölüm, empty for land.
  final String unit;
  final String address;
  final double? areaM2;

  /// Starting (or asking) price in TL.
  final double? price;

  /// Highest bid so far when the platform publishes it.
  final double? lastBid;

  /// Local auction end, ISO without zone. Null when the platform has none.
  final String? endsAt;
  final String photo;

  /// True once the detail page was read, even when it had no ada/parsel.
  final bool detailFetched;
  final String firstSeen;
  final String lastSeen;
  final String? removedOn;

  /// Price on each day it changed, oldest first.
  final List<PricePoint> prices;

  /// Other platform URLs for the same property.
  final List<String> alsoAt;

  /// Stable id: platform, seller account and platform reference.
  String get key => '$source:$sellerId:$ref';

  /// Bank number shared across platforms, e.g. `401991` for `P-401991`.
  String get refNorm => normalizeRef(ref);

  bool get hasParcel => parsel.isNotEmpty;

  BankListingRecord copyWith({
    String? ada,
    String? parsel,
    String? unit,
    String? address,
    String? mahalle,
    double? areaM2,
    String? endsAt,
    bool? detailFetched,
    String? firstSeen,
    String? lastSeen,
    String? removedOn,
    bool clearRemovedOn = false,
    List<PricePoint>? prices,
    List<String>? alsoAt,
  }) {
    return BankListingRecord(
      source: source,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerType: sellerType,
      sellerGroup: sellerGroup,
      ref: ref,
      title: title,
      category: category,
      subCategory: subCategory,
      il: il,
      ilce: ilce,
      mahalle: mahalle ?? this.mahalle,
      url: url,
      ada: ada ?? this.ada,
      parsel: parsel ?? this.parsel,
      unit: unit ?? this.unit,
      address: address ?? this.address,
      areaM2: areaM2 ?? this.areaM2,
      price: price,
      lastBid: lastBid,
      endsAt: endsAt ?? this.endsAt,
      photo: photo,
      detailFetched: detailFetched ?? this.detailFetched,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      removedOn: clearRemovedOn ? null : (removedOn ?? this.removedOn),
      prices: prices ?? this.prices,
      alsoAt: alsoAt ?? this.alsoAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'source': source,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'sellerType': sellerType.name,
      'sellerGroup': sellerGroup,
      'ref': ref,
      'title': title,
      'category': category,
      'subCategory': subCategory,
      'il': il,
      'ilce': ilce,
      'mahalle': mahalle,
      'ada': ada,
      'parsel': parsel,
      'unit': unit,
      'address': address,
      'areaM2': areaM2,
      'price': price,
      'lastBid': lastBid,
      'endsAt': endsAt,
      'url': url,
      'photo': photo,
      'detailFetched': detailFetched,
      'firstSeen': firstSeen,
      'lastSeen': lastSeen,
      'removedOn': removedOn,
      'prices': prices.map((PricePoint p) => p.toJson()).toList(),
      'alsoAt': alsoAt,
    };
  }

  static BankListingRecord? fromJson(Map<String, Object?> json) {
    String text(String name) {
      final Object? value = json[name];
      return value is String ? value : '';
    }

    final String source = text('source');
    final String sellerId = text('sellerId');
    final String ref = text('ref');
    if (source.isEmpty || sellerId.isEmpty || ref.isEmpty) {
      return null;
    }
    final Object? rawPrices = json['prices'];
    final Object? rawAlso = json['alsoAt'];
    final Object? removed = json['removedOn'];
    final Object? ends = json['endsAt'];
    return BankListingRecord(
      source: source,
      sellerId: sellerId,
      sellerName: text('sellerName'),
      sellerType: SellerType.values.firstWhere(
        (SellerType t) => t.name == text('sellerType'),
        orElse: () => SellerType.other,
      ),
      sellerGroup: text('sellerGroup').isEmpty ? sellerId : text('sellerGroup'),
      ref: ref,
      title: text('title'),
      category: text('category'),
      subCategory: text('subCategory'),
      il: text('il'),
      ilce: text('ilce'),
      mahalle: text('mahalle'),
      url: text('url'),
      ada: text('ada'),
      parsel: text('parsel'),
      unit: text('unit'),
      address: text('address'),
      areaM2: parsePrice(json['areaM2']),
      price: parsePrice(json['price']),
      lastBid: parsePrice(json['lastBid']),
      endsAt: ends is String ? ends : null,
      photo: text('photo'),
      detailFetched: json['detailFetched'] == true,
      firstSeen: text('firstSeen'),
      lastSeen: text('lastSeen'),
      removedOn: removed is String ? removed : null,
      prices: rawPrices is List
          ? <PricePoint>[
              for (final Object? item in rawPrices)
                ?PricePoint.fromJson(item),
            ]
          : const <PricePoint>[],
      alsoAt: rawAlso is List
          ? <String>[
              for (final Object? item in rawAlso)
                if (item is String) item,
            ]
          : const <String>[],
    );
  }
}

/// How one source did on this run.
class SourceStatus {
  const SourceStatus({
    required this.id,
    required this.name,
    required this.ok,
    required this.count,
    this.error,
  });

  final String id;
  final String name;
  final bool ok;
  final int count;
  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'ok': ok,
    'count': count,
    'error': error,
  };
}

/// Folds today's fetch into yesterday's records.
///
/// [fetched] holds rows from sources that answered. A listing missing from a
/// source that failed today is kept unchanged, so an outage does not mark the
/// whole portfolio as removed. Detail fields (ada, parsel, unit) are carried
/// over when today's row did not read the detail page.
List<BankListingRecord> mergeSnapshot({
  required List<BankListingRecord> previous,
  required List<BankListingRecord> fetched,
  required Set<String> failedSources,
  required String today,
}) {
  final Map<String, BankListingRecord> before = <String, BankListingRecord>{
    for (final BankListingRecord row in previous) row.key: row,
  };
  final Map<String, BankListingRecord> out = <String, BankListingRecord>{};

  for (final BankListingRecord row in fetched) {
    final BankListingRecord? old = before[row.key];
    BankListingRecord next = row;
    if (old != null && !row.detailFetched && old.detailFetched) {
      next = next.copyWith(
        ada: old.ada,
        parsel: old.parsel,
        unit: old.unit,
        address: old.address.isNotEmpty ? old.address : null,
        mahalle: old.mahalle.isNotEmpty ? old.mahalle : null,
        areaM2: old.areaM2,
        endsAt: row.endsAt ?? old.endsAt,
        detailFetched: true,
      );
    }
    final List<PricePoint> prices = <PricePoint>[...?old?.prices];
    final double? price = row.price;
    if (price != null && (prices.isEmpty || prices.last.price != price)) {
      prices.add(PricePoint(today, price));
    }
    out[row.key] = next.copyWith(
      firstSeen: old?.firstSeen.isNotEmpty == true ? old!.firstSeen : today,
      lastSeen: today,
      clearRemovedOn: true,
      prices: prices,
    );
  }

  final DateTime todayDate = DateTime.parse(today);
  for (final BankListingRecord old in previous) {
    if (out.containsKey(old.key)) {
      continue;
    }
    if (failedSources.contains(old.source)) {
      out[old.key] = old;
      continue;
    }
    final String removed = old.removedOn ?? today;
    final int age = todayDate.difference(DateTime.parse(removed)).inDays;
    if (age <= removedKeepDays) {
      out[old.key] = old.copyWith(removedOn: removed);
    }
  }
  return dedupeListings(out.values.toList());
}

/// Joins rows that are one property on two platforms or two accounts.
///
/// The first key is the seller group plus the bank's own number. The second
/// is seller group, place, ada, parsel and unit, used only when the unit is
/// known and only across platforms: on one platform two numbers are two
/// listings, even in a site whose villas share one parcel and unit number.
/// The kept row is the one with parcel data; the other's URL goes to
/// [alsoAt].
List<BankListingRecord> dedupeListings(List<BankListingRecord> rows) {
  final Map<String, int> byRef = <String, int>{};
  final Map<String, int> byLot = <String, int>{};
  final List<BankListingRecord> out = <BankListingRecord>[];
  for (final BankListingRecord row in rows) {
    final String? refKey = row.refNorm.length >= 3
        ? '${row.sellerGroup}|${row.refNorm}'
        : null;
    final String? lotKey = row.hasParcel && row.unit.isNotEmpty
        ? '${row.sellerGroup}|${foldText(row.il)}|${foldText(row.ilce)}|'
              '${row.ada}|${row.parsel}|${row.unit}'
        : null;
    int? hit = refKey == null ? null : byRef[refKey];
    if (hit == null && lotKey != null) {
      final int? lot = byLot[lotKey];
      if (lot != null && out[lot].source != row.source) {
        hit = lot;
      }
    }
    if (hit == null) {
      if (refKey != null) {
        byRef[refKey] = out.length;
      }
      if (lotKey != null) {
        byLot.putIfAbsent(lotKey, () => out.length);
      }
      out.add(row);
      continue;
    }
    final BankListingRecord kept = out[hit];
    final bool swap = !kept.hasParcel && row.hasParcel;
    final BankListingRecord winner = swap ? row : kept;
    final BankListingRecord loser = swap ? kept : row;
    out[hit] = winner.copyWith(
      alsoAt: <String>{
        ...winner.alsoAt,
        loser.url,
        ...loser.alsoAt,
      }.where((String url) => url != winner.url).toList(),
    );
    if (refKey != null) {
      byRef[refKey] = hit;
    }
  }
  return out;
}

/// The whole file the app downloads.
Map<String, Object?> snapshotJson({
  required DateTime generatedAt,
  required String day,
  required List<SourceStatus> sources,
  required List<BankListingRecord> listings,
}) {
  return <String, Object?>{
    'schema': snapshotSchema,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'day': day,
    'sources': sources.map((SourceStatus s) => s.toJson()).toList(),
    'listings': listings.map((BankListingRecord r) => r.toJson()).toList(),
  };
}

/// Records from a decoded snapshot. Empty for another schema or bad input.
List<BankListingRecord> recordsFromSnapshot(Object? decoded) {
  if (decoded is! Map || decoded['schema'] != snapshotSchema) {
    return const <BankListingRecord>[];
  }
  final Object? rows = decoded['listings'];
  if (rows is! List) {
    return const <BankListingRecord>[];
  }
  return <BankListingRecord>[
    for (final Object? row in rows)
      if (row is Map<String, Object?>) ?BankListingRecord.fromJson(row),
  ];
}
