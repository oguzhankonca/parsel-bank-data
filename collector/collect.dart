/// Daily bank listing collector (ADR 0048).
///
/// ```
/// dart run tool/bank_collector/collect.dart \
///   --previous data/snapshot.json --out data --max-details 3000
/// ```
///
/// Reads the previous snapshot, lists İntengo and Halkbank, reads detail
/// pages only for rows that never had one, merges, and writes
/// `<out>/snapshot.json`. Live calls only; never part of `flutter test`.
library;

import 'dart:convert';
import 'dart:io';

import 'bank_snapshot.dart';
import 'bank_text.dart';
import 'collector_http.dart';
import 'halkbank_source.dart';
import 'intengo_source.dart';

Future<void> main(List<String> args) async {
  final Map<String, String> options = _options(args);
  final String outDir = options['out'] ?? 'data';
  final int maxDetails = int.tryParse(options['max-details'] ?? '') ?? 3000;
  final int pauseMs = int.tryParse(options['pause-ms'] ?? '') ?? 1200;
  final CollectorHttp http = CollectorHttp(
    pause: Duration(milliseconds: pauseMs),
  );
  // Turkey has no DST; the run day is the Istanbul calendar day.
  final DateTime now = DateTime.now().toUtc();
  final String today = dayKey(now.add(const Duration(hours: 3)));

  final List<BankListingRecord> previous = _readPrevious(options['previous']);
  final Map<String, BankListingRecord> before = <String, BankListingRecord>{
    for (final BankListingRecord row in previous) row.key: row,
  };
  stdout.writeln('previous: ${previous.length} rows, day $today');

  final List<SourceStatus> sources = <SourceStatus>[];
  final Set<String> failed = <String>{};
  final List<BankListingRecord> fetched = <BankListingRecord>[];

  Future<void> run(
    String id,
    String name,
    Future<List<BankListingRecord>> Function() list,
  ) async {
    try {
      final List<BankListingRecord> rows = await list();
      fetched.addAll(rows);
      sources.add(SourceStatus(id: id, name: name, ok: true, count: rows.length));
      stdout.writeln('$id: ${rows.length} rows');
    } on Object catch (error) {
      failed.add(id);
      sources.add(
        SourceStatus(id: id, name: name, ok: false, count: 0, error: '$error'),
      );
      stderr.writeln('$id failed: $error');
    }
  }

  await run('intengo', 'İntengo', () => fetchIntengoList(http));
  await run('halkbank', 'Halkbank', () => fetchHalkbankList(http));

  // New rows first, then rows whose detail never loaded.
  final List<int> order = List<int>.generate(fetched.length, (int i) => i)
    ..sort((int a, int b) {
      final bool newA = !before.containsKey(fetched[a].key);
      final bool newB = !before.containsKey(fetched[b].key);
      return newA == newB ? 0 : (newA ? -1 : 1);
    });
  int details = 0;
  int detailErrors = 0;
  for (final int i in order) {
    final BankListingRecord row = fetched[i];
    if (before[row.key]?.detailFetched == true) {
      continue;
    }
    if (details >= maxDetails) {
      break;
    }
    details++;
    try {
      fetched[i] = row.source == 'halkbank'
          ? await fetchHalkbankDetail(http, row)
          : applyIntengoDetail(row, await http.getText(row.url));
    } on Object catch (error) {
      detailErrors++;
      stderr.writeln('detail ${row.key}: $error');
    }
    if (details % 250 == 0) {
      stdout.writeln('details: $details');
    }
  }

  final List<BankListingRecord> merged = mergeSnapshot(
    previous: previous,
    fetched: fetched,
    failedSources: failed,
    today: today,
  );
  final Directory dir = Directory(outDir)..createSync(recursive: true);
  final File file = File('${dir.path}/snapshot.json');
  file.writeAsStringSync(
    jsonEncode(
      snapshotJson(
        generatedAt: now,
        day: today,
        sources: sources,
        listings: merged,
      ),
    ),
  );
  final int active = merged.where((BankListingRecord r) => r.removedOn == null)
      .length;
  final int withParcel = merged.where((BankListingRecord r) => r.hasParcel)
      .length;
  stdout.writeln(
    'wrote ${file.path}: ${merged.length} rows, $active active, '
    '$withParcel with ada/parsel, $details details ($detailErrors failed), '
    '${http.requests} requests',
  );
  http.close();
  if (failed.length == sources.length) {
    exitCode = 1;
  }
}

List<BankListingRecord> _readPrevious(String? path) {
  if (path == null) {
    return const <BankListingRecord>[];
  }
  final File file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('no previous snapshot at $path');
    return const <BankListingRecord>[];
  }
  try {
    return recordsFromSnapshot(jsonDecode(file.readAsStringSync()));
  } on FormatException catch (error) {
    stderr.writeln('previous snapshot unreadable: $error');
    return const <BankListingRecord>[];
  }
}

Map<String, String> _options(List<String> args) {
  final Map<String, String> out = <String, String>{};
  for (int i = 0; i + 1 < args.length; i++) {
    if (args[i].startsWith('--')) {
      out[args[i].substring(2)] = args[i + 1];
      i++;
    }
  }
  return out;
}
