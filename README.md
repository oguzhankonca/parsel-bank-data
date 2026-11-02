# parsel-bank-data

Daily snapshot of public bank and institution real-estate sale listings, read
by the `parsel_app` graduation project (Satış → Banka & Kurum).

- `collector/` is a copy of `tool/bank_collector/` from the app repository.
  Edit it there and sync; see ADR 0048 in the app repo.
- `.github/workflows/collect.yml` runs once a day at 03:30 Istanbul time.
- The output is `snapshot.json` on the `data` branch:
  `https://raw.githubusercontent.com/oguzhankonca/parsel-bank-data/data/snapshot.json`

## Sources

| Source | What is read | Request pattern |
|---|---|---|
| İntengo (`gayrimenkul.intengo.com`) | The public search JSON the site's own page calls, and public listing pages for ada/parsel | ~20 list requests a day, detail pages only for new listings |
| Halkbank Gayrimenkul (`halkbankgayrimenkul.com.tr`) | The public list and detail JSON the site's own page calls | ~200 list requests a day, detail only for new listings |

One request at a time with a pause between requests. No login, no
authenticated API. A listing page always links back to the official source;
the snapshot is an index, not a copy of the notice.

## Snapshot schema (v1)

```json
{
  "schema": 1,
  "generatedAt": "2026-11-03T00:41:12Z",
  "day": "2026-11-03",
  "sources": [{"id": "intengo", "name": "İntengo", "ok": true, "count": 3520, "error": null}],
  "listings": [{
    "key": "intengo:akbank:P-401991",
    "source": "intengo", "sellerId": "akbank", "sellerName": "Akbank",
    "sellerType": "bank", "sellerGroup": "akbank", "ref": "P-401991",
    "title": "...", "category": "Konut", "subCategory": "Daire",
    "il": "Antalya", "ilce": "Konyaaltı", "mahalle": "Liman",
    "ada": "20901", "parsel": "11", "unit": "3", "address": "...",
    "areaM2": 144.0, "price": 10750000.0, "lastBid": null,
    "endsAt": "2026-11-05T15:34:59.000", "url": "https://...", "photo": "https://...",
    "detailFetched": true, "firstSeen": "2026-11-03", "lastSeen": "2026-11-03",
    "removedOn": null, "prices": [["2026-11-03", 10750000.0]], "alsoAt": []
  }]
}
```

`sellerType` is one of `bank`, `participationBank`, `leasing`, `reit`,
`assetManagement`, `foundation`, `company`, `other`. Removed listings stay for
14 days with `removedOn` set.
