/// Who sells a listing, and what kind of institution that is (ADR 0048).
library;

/// Seller kind the app filters on. The JSON value is [name].
enum SellerType {
  bank,
  participationBank,
  leasing,
  reit,
  assetManagement,
  foundation,
  company,
  other,
}

/// One seller. [group] joins accounts of the same institution so one
/// property listed under two of them is matched by its number.
class Seller {
  const Seller(this.id, this.name, this.type, {String? group})
    : group = group ?? id;

  final String id;
  final String name;
  final SellerType type;
  final String group;
}

/// İntengo `companyName` values seen on the public search, 2026-11.
///
/// An unknown value still gets a row: [sellerForIntengo] falls back to
/// [SellerType.other] with the raw name, so a new İntengo customer shows up
/// without a code change.
const Map<String, Seller> _intengoSellers = <String, Seller>{
  'vakifbank': Seller('vakifbank', 'VakıfBank', SellerType.bank),
  'vakiflarbankasi': Seller(
    'vakiflarbankasi',
    'VakıfBank',
    SellerType.bank,
    group: 'vakifbank',
  ),
  'vakifbankdiger': Seller(
    'vakifbankdiger',
    'VakıfBank (diğer)',
    SellerType.bank,
    group: 'vakifbank',
  ),
  'denizbank': Seller('denizbank', 'DenizBank', SellerType.bank),
  'garanti': Seller('garanti', 'Garanti BBVA', SellerType.bank),
  'yapikredi': Seller('yapikredi', 'Yapı Kredi', SellerType.bank),
  'sekerbank': Seller('sekerbank', 'Şekerbank', SellerType.bank),
  'Şekerbank Toplu Satış GM': Seller(
    'sekerbanktoplu',
    'Şekerbank (toplu satış)',
    SellerType.bank,
    group: 'sekerbank',
  ),
  'isbankasi': Seller('isbankasi', 'İş Bankası', SellerType.bank),
  'burganbank': Seller('burganbank', 'Burgan Bank', SellerType.bank),
  'qnbbank': Seller('qnbbank', 'QNB', SellerType.bank),
  'akbank': Seller('akbank', 'Akbank', SellerType.bank),
  'anadolubank': Seller('anadolubank', 'Anadolubank', SellerType.bank),
  'ingbank': Seller('ingbank', 'ING', SellerType.bank),
  'icbc': Seller('icbc', 'ICBC Turkey', SellerType.bank),
  'tbank': Seller('tbank', 'Turkish Bank', SellerType.bank),
  'fibabanka': Seller('fibabanka', 'Fibabanka', SellerType.bank),
  'ziraatkatilim': Seller(
    'ziraatkatilim',
    'Ziraat Katılım',
    SellerType.participationBank,
  ),
  'emlakkatilim': Seller(
    'emlakkatilim',
    'Emlak Katılım',
    SellerType.participationBank,
  ),
  'turkiyefinans': Seller(
    'turkiyefinans',
    'Türkiye Finans',
    SellerType.participationBank,
  ),
  'vakifleasing': Seller('vakifleasing', 'Vakıf Leasing', SellerType.leasing),
  'garantileasing': Seller(
    'garantileasing',
    'Garanti BBVA Leasing',
    SellerType.leasing,
  ),
  'QNB Leasing': Seller('qnbleasing', 'QNB Leasing', SellerType.leasing),
  'vakifgyo': Seller('vakifgyo', 'Vakıf GYO', SellerType.reit),
  'gelecekvarlik': Seller(
    'gelecekvarlik',
    'Gelecek Varlık',
    SellerType.assetManagement,
  ),
  'dunyavarlik': Seller(
    'dunyavarlik',
    'Dünya Varlık',
    SellerType.assetManagement,
  ),
  'istanbulvarlik': Seller(
    'istanbulvarlik',
    'İstanbul Varlık',
    SellerType.assetManagement,
  ),
  'darussafaka': Seller('darussafaka', 'Darüşşafaka', SellerType.foundation),
  'tev': Seller('tev', 'Türk Eğitim Vakfı', SellerType.foundation),
  'garantiemeklisandigi': Seller(
    'garantiemeklisandigi',
    'Garanti Emekli Sandığı',
    SellerType.foundation,
  ),
  'senpilic': Seller('senpilic', 'Şenpiliç', SellerType.company),
  // The portal does not name the institution behind these accounts.
  'emlak': Seller('emlak', 'İntengo · emlak', SellerType.other),
  'emlak1': Seller(
    'emlak1',
    'İntengo · emlak',
    SellerType.other,
    group: 'emlak',
  ),
  'gayrimenkul': Seller('gayrimenkul', 'İntengo · çeşitli', SellerType.other),
  'intengo': Seller('intengo', 'İntengo', SellerType.other),
};

/// Catalog row for an İntengo `companyName`.
Seller sellerForIntengo(String companyName) {
  final Seller? known = _intengoSellers[companyName];
  if (known != null) {
    return known;
  }
  final String id = companyName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return Seller(id.isEmpty ? 'unknown' : id, companyName, SellerType.other);
}

/// Halkbank sells through its own portal.
const Seller halkbankSeller = Seller('halkbank', 'Halkbank', SellerType.bank);
