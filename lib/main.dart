import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data_page.dart';
import 'saved_page.dart';
import 'scan_page.dart';
import 'settings_page.dart';

const appName = 'Smart & Fast Count';
const teal = Color(0xFF00A6A6);
const tealDark = Color(0xFF006D6D);

void main() => runApp(MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal),
          appBarTheme: const AppBarTheme(backgroundColor: teal, foregroundColor: Colors.white),
          useMaterial3: true),
      home: const Home(),
    ));

// ---------- Veri modeli ----------
class V {
  String code, name, color, size;
  List<String> a; // Ozellik1Kod, Ozellik1Ad ... Ozellik4Ad
  List<String> bc = [];
  V(this.code, this.name, this.color, this.size, this.a);
}

class L {
  String bc, dep, loc;
  int q;
  bool undef;
  L(this.bc, this.dep, this.loc, this.q, this.undef);
  Map toJson() => {'bc': bc, 'dep': dep, 'loc': loc, 'q': q, 'u': undef};
  factory L.fromJson(Map j) => L(j['bc'], j['dep'], j['loc'], j['q'], j['u']);
}

Map<String, V> byBarcode = {};
String device = '', user = '', dataPath = '';
late SharedPreferences prefs;

List<String> getDepots() => prefs.getStringList('depots') ?? List.generate(21, (i) => '07${(i + 1).toString().padLeft(2, '0')}');
Future<void> setDepots(List<String> l) => prefs.setStringList('depots', l);
String countMode() => prefs.getString('mode') ?? 'merge'; // merge | each

// ---------- Ağır işler (arka plan isolate'ında çalışır, ekran donmaz) ----------
const hdr = [
  'UrunKodu', 'UrunAdi', 'Renk', 'Beden', 'Ozellik1Kod', 'Ozellik1Ad', 'Ozellik2Kod', 'Ozellik2Ad',
  'Ozellik3Kod', 'Ozellik3Ad', 'Ozellik4Kod', 'Ozellik4Ad', 'Barkod'
];

String cellStr(CellValue? v) {
  if (v == null) return '';
  if (v is DoubleCellValue) {
    final d = v.value;
    return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
  }
  if (v is IntCellValue) return v.value.toString();
  if (v is TextCellValue) return v.value.toString();
  return v.toString();
}

List<List<String>> readTable(String path) {
  final bytes = File(path).readAsBytesSync();
  if (path.toLowerCase().endsWith('.xlsx')) {
    final x = Excel.decodeBytes(bytes);
    return x.tables.values.first.rows.map((r) => r.map((c) => cellStr(c?.value)).toList()).toList();
  }
  final t = utf8.decode(bytes, allowMalformed: true).replaceAll('\uFEFF', '');
  final nl = t.indexOf('\n');
  final d = (nl < 0 ? t : t.substring(0, nl)).contains(';') ? ';' : ',';
  return const CsvToListConverter(shouldParseNumbers: false)
      .convert(t, fieldDelimiter: d, eol: '\n')
      .map((r) => r.map((e) => e.toString()).toList())
      .toList();
}

/// Dosyayı veri deposuna işler. update=false: yeni yükleme, update=true: mevcut ürünleri günceller/yeni ekler.
/// Bir barkod hiçbir zaman iki satırda tutulmaz. Döner: [okunan, eklenen, güncellenen, tekrar, hatalı, toplam]
List<int> importJob(String src, String dst, bool update) {
  final rows = readTable(src);
  final map = <String, List<String>>{};
  if (update && File(dst).existsSync()) {
    for (final r in readTable(dst).skip(1)) {
      if (r.length >= 13) map[r[12].trim()] = r;
    }
  }
  int read = 0, added = 0, updated = 0, dup = 0, bad = 0;
  final seen = <String>{};
  for (final r0 in rows.skip(1)) {
    if (r0.length < 13) {
      bad++;
      continue;
    }
    final r = r0.take(13).map((e) => e.trim()).toList();
    final bc = r[12];
    if (bc.isEmpty) {
      bad++;
      continue;
    }
    read++;
    final first = seen.add(bc);
    if (!first) {
      dup++;
      if (!update) continue; // yeni yüklemede ilk satır geçerli
    }
    if (map.containsKey(bc)) {
      if (first) updated++;
    } else {
      added++;
    }
    map[bc] = r;
  }
  File(dst).writeAsStringSync(const ListToCsvConverter(fieldDelimiter: ';').convert([hdr, ...map.values]));
  return [read, added, updated, dup, bad, map.length];
}

Map<String, V> loadMap(String path) {
  final out = <String, V>{};
  if (!File(path).existsSync()) return out;
  final variants = <String, V>{};
  for (final r in readTable(path).skip(1)) {
    if (r.length < 13) continue;
    final s = r.map((e) => e.trim()).toList();
    final v = variants.putIfAbsent('${s[0]}|${s[2]}|${s[3]}', () => V(s[0], s[1], s[2], s[3], s.sublist(4, 12)));
    if (s[12].isNotEmpty) {
      v.bc.add(s[12]);
      out[s[12]] = v;
    }
  }
  return out;
}

Future<Map<String, V>> loadDataAsync() {
  final p = dataPath;
  return Isolate.run(() => loadMap(p));
}

Future<List<int>> importAsync(String src, bool update) {
  final d = dataPath;
  return Isolate.run(() => importJob(src, d, update));
}

Future<String> ask(BuildContext context, String title, String hint) async {
  final c = TextEditingController();
  String r = '';
  while (r.isEmpty) {
    await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
              title: Text(title),
              content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
            ));
    r = c.text.trim();
  }
  return r;
}

List<L> loadLines() {
  final s = prefs.getString('lines');
  return s == null ? [] : (jsonDecode(s) as List).map((e) => L.fromJson(e)).toList();
}

// ---------- Ana ekran ----------
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool ready = false;
  String status = 'Başlatılıyor...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => boot());
  }

  Future<void> boot() async {
    prefs = await SharedPreferences.getInstance();
    dataPath = '${(await getApplicationDocumentsDirectory()).path}/urun_verisi.csv';
    device = prefs.getString('device') ?? '';
    if (device.isEmpty) {
      device = await ask(context, 'Cihaz Adı', 'Bu ad sonradan DEĞİŞTİRİLEMEZ.');
      await prefs.setString('device', device);
    }
    user = await ask(context, 'Kullanıcı Adı', 'Giriş yapan kullanıcı');
    setState(() => status = 'Ürün verisi yükleniyor...');
    byBarcode = await loadDataAsync();
    setState(() => ready = true);
  }

  void snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> openSaved() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPage()));
    setState(() {});
  }

  Future<void> openData() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DataPage()));
    setState(() {});
  }

  Future<void> openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    setState(() {});
  }

  Future<void> openCount() async {
    if (byBarcode.isEmpty) return snack('Önce ürün verisini yükleyin');
    final r = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const CountPage()));
    setState(() {});
    if (r != null) snack(r.isEmpty ? 'Excel kaydedilemedi!' : 'Excel kaydedildi: $r');
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(status),
      ])));
    }
    final open = loadLines();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tealDark, teal, Color(0xFF7FDCDC)])),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(icon: const Icon(Icons.settings, color: Colors.white, size: 30), tooltip: 'Ayarlar', onPressed: openSettings)),
              const SizedBox(height: 8),
              Center(child: Image.asset('assets/logo.png', height: 150)),
              const SizedBox(height: 8),
              const Text(appName, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Kullanıcı: $user   •   Cihaz: $device', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const Spacer(),
              SizedBox(
                height: 80,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: tealDark),
                  onPressed: openCount,
                  icon: const Icon(Icons.fact_check, size: 32),
                  label: Text(open.isEmpty ? 'SAYIM' : 'SAYIM (devam: ${open.length} satır)', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                  onPressed: openData,
                  icon: const Icon(Icons.upload_file),
                  label: Text('Veri Yükle  (${byBarcode.length} barkod)'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                  onPressed: openSaved,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Kaydedilen Sayımlar'),
                ),
              ),
              const Spacer(),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------- Sayım ekranı ----------
class CountPage extends StatefulWidget {
  const CountPage({super.key});
  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> {
  List<L> lines = [];
  List<String> depots = [];
  String dep = '', loc = '', fb = '';
  bool add = true;
  bool kb = false; // true: elle yazma (ekran klavyesi açık)
  final scanC = TextEditingController(), locC = TextEditingController();
  final scanF = FocusNode(), locF = FocusNode();

  @override
  void initState() {
    super.initState();
    lines = loadLines(); // kaldığı yerden devam
    depots = getDepots();
    dep = prefs.getString('dep') ?? '';
    if (!depots.contains(dep)) dep = depots.isEmpty ? '' : depots.first;
    loc = prefs.getString('loc') ?? '';
    locC.text = loc;
    WidgetsBinding.instance.addPostFrameCallback((_) => scanF.requestFocus());
  }

  void snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> save() async {
    await prefs.setString('lines', jsonEncode(lines.map((e) => e.toJson()).toList()));
    await prefs.setString('dep', dep);
    await prefs.setString('loc', loc);
  }

  void openKb(FocusNode f) {
    if (kb) return;
    setState(() => kb = true);
    f.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => f.requestFocus());
  }

  void backToScanner() {
    setState(() => kb = false);
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) scanF.requestFocus();
    });
  }

  /// Lokasyon ilk okutmada kaydedilir. Sonra farklı bir lokasyon okutulursa onay sorulur.
  Future<void> setLoc(String raw) async {
    final v = raw.trim();
    if (v.isEmpty || v == loc) {
      locC.text = loc;
      backToScanner();
      return;
    }
    if (loc.isNotEmpty) {
      final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
                title: const Text('Lokasyon değiştirilsin mi?'),
                content: Text('Mevcut lokasyon: $loc\nYeni lokasyon: $v\n\nLokasyonu değiştirmek istediğinize emin misiniz?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet')),
                ],
              ));
      if (ok != true) {
        locC.text = loc;
        backToScanner();
        return;
      }
    }
    loc = v;
    locC.text = loc;
    backToScanner();
    await save();
    setState(() {});
  }

  Future<void> scan(String raw) async {
    final bc = raw.trim();
    scanC.clear();
    if (kb) {
      backToScanner();
    } else {
      scanF.requestFocus();
    }
    if (bc.isEmpty) return;
    if (loc.isEmpty) return snack('Önce lokasyonu okutun (Lokasyon alanı)');
    if (depots.isEmpty) return snack('Önce Ayarlar > Depo Kodları bölümünden depo ekleyin');
    final each = countMode() == 'each'; // her okutma yeni satır
    final i = lines.indexWhere((l) => l.bc == bc && l.dep == dep && l.loc == loc);
    if (add && (i < 0 || each)) {
      final known = lines.any((l) => l.bc == bc && l.undef);
      final l = L(bc, dep, loc, 1, !byBarcode.containsKey(bc));
      lines.insert(0, l);
      fb = each ? '$bc  →  +1  (${lines.where((x) => x.bc == bc).length} satır)' : '$bc  →  1 adet';
      await save();
      setState(() {});
      if (l.undef && !known) {
        await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
                  title: const Text('Uyarı'),
                  content: Text('Tanımsız barkod okuttunuz:\n$bc'),
                  actions: [
                    TextButton(
                        onPressed: () {
                          lines.remove(l);
                          Navigator.pop(context);
                        },
                        child: const Text('Çıkar')),
                    FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Devam')),
                  ],
                ));
      }
    } else if (i < 0) {
      return snack('Bu barkod için satır yok');
    } else if (each) {
      lines.removeAt(i);
      fb = '$bc  →  -1';
    } else {
      final n = lines[i].q + (add ? 1 : -1);
      if (n < 0) return snack('Miktar 0\'ın altına inemez');
      lines[i].q = n;
      fb = '$bc  →  $n adet';
    }
    HapticFeedback.lightImpact();
    await save();
    setState(() {});
    scanF.requestFocus();
  }

  Future<void> camLoc() async {
    final c = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage(title: 'Lokasyon barkodunu okutun')));
    if (c != null) await setLoc(c);
  }

  Future<void> camProd() async {
    if (loc.isEmpty) return snack('Önce lokasyonu okutun (Lokasyon alanındaki kamera düğmesi)');
    if (depots.isEmpty) return snack('Önce Ayarlar > Depo Kodları bölümünden depo ekleyin');
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ScanPage(
                title: 'Ürün barkodlarını okutun',
                onCode: scan,
                isAdd: () => add,
                feedback: () =>
                    'Depo $dep  •  Lokasyon: $loc  •  ${add ? "EKLE" : "ÇIKAR"}\n$fb')));
    setState(() {});
    scanF.requestFocus();
  }

  Future<void> editQty(L l) async {
    final c = TextEditingController(text: '${l.q}');
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(l.bc),
              content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () {
                      lines.remove(l);
                      Navigator.pop(context);
                    },
                    child: const Text('Satırı Sil')),
                FilledButton(
                    onPressed: () {
                      l.q = (int.tryParse(c.text) ?? l.q).clamp(0, 999999);
                      Navigator.pop(context);
                    },
                    child: const Text('Kaydet')),
              ],
            ));
    await save();
    setState(() {});
    scanF.requestFocus();
  }

  Future<void> finish() async {
    if (lines.isEmpty) return snack('Sayım boş');
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Sayımı kaydet?'),
              content: const Text('Excel oluşturulacak, sayım temizlenecek ve ana ekrana dönülecek.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
              ],
            ));
    if (ok != true) return;
    final path = await exportExcel();
    if (path.isEmpty) return snack('Excel yazılamadı, sayım silinmedi!');
    await saveRecord(path);
    lines.clear();
    loc = '';
    fb = '';
    await save();
    if (mounted) Navigator.pop(context, path);
  }

  Future<void> saveRecord(String xlsx) async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/sayimlar');
    await d.create(recursive: true);
    final base = xlsx.split('/').last.replaceAll('.xlsx', '');
    final rec = {
      'ts': DateTime.now().toIso8601String(),
      'xlsx': xlsx,
      'user': user,
      'device': device,
      'deps': lines.map((l) => l.dep).toSet().join(', '),
      'lines': lines.map((l) {
        final v = byBarcode[l.bc];
        return {...l.toJson(), 'n': v == null ? '' : '${v.name} ${v.color} ${v.size}'};
      }).toList(),
    };
    await File('${d.path}/$base.json').writeAsString(jsonEncode(rec));
  }

  Future<String> exportExcel() async {
    final x = Excel.createExcel();
    x.rename('Sheet1', 'Sayim');
    final sh = x['Sayim'];
    sh.appendRow(([
      'Ürün Kodu', 'Ürün Adı', 'Renk', 'Beden',
      'Özellik 1 Kodu', 'Özellik 1 Adı', 'Özellik 2 Kodu', 'Özellik 2 Adı',
      'Özellik 3 Kodu', 'Özellik 3 Adı', 'Özellik 4 Kodu', 'Özellik 4 Adı',
      'Barkod 1', 'Barkod 2', 'Barkod 3', 'Miktar', 'Lokasyon', 'Depo', 'Kullanıcı Adı', 'Cihaz Adı'
    ]).map((e) => TextCellValue(e)).toList());
    final agg = <String, List>{};
    final undef = <L>[];
    for (final l in lines) {
      final v = byBarcode[l.bc];
      if (l.undef || v == null) {
        undef.add(l);
        continue;
      }
      final k = '${v.code}|${v.color}|${v.size}|${l.dep}|${l.loc}';
      agg.putIfAbsent(k, () => [v, l.dep, l.loc, 0])[3] += l.q;
    }
    CellValue cv(c) => c is int ? IntCellValue(c) : TextCellValue('$c');
    for (final e in agg.values) {
      final V v = e[0];
      final b = [...v.bc, '', '', ''].sublist(0, 3);
      sh.appendRow([v.code, v.name, v.color, v.size, ...v.a, ...b, e[3], e[2], e[1], user, device].map(cv).toList());
    }
    final red = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#FFC7CE'), fontColorHex: ExcelColor.fromHexString('#9C0006'));
    for (final l in undef) {
      sh.appendRow(['', '', '', '', '', '', '', '', '', '', '', '', l.bc, '', '', l.q, l.loc, l.dep, user, device].map(cv).toList());
      for (var c = 0; c < 20; c++) {
        sh.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: sh.maxRows - 1)).cellStyle = red;
      }
    }
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final name = 'Sayim_${dep.isEmpty ? 'X' : dep}_${n.year}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}${p(n.second)}.xlsx';
    final bytes = x.encode()!;
    for (final dir in ['/storage/emulated/0/Download', (await getExternalStorageDirectory())?.path, (await getApplicationDocumentsDirectory()).path]) {
      if (dir == null) continue;
      try {
        final f = File('$dir/$name');
        await f.writeAsBytes(bytes);
        return f.path;
      } catch (_) {}
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sayım  •  $user', style: const TextStyle(fontSize: 16)),
        actions: [TextButton.icon(onPressed: finish, icon: const Icon(Icons.save, color: Colors.white), label: const Text('KAYDET', style: TextStyle(color: Colors.white)))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(children: [
            depots.isEmpty
                ? const InputDecorator(
                    decoration: InputDecoration(labelText: 'Depo Kodu', border: OutlineInputBorder(), isDense: true),
                    child: Text('Depo yok: Ayarlar > Depo Kodları', style: TextStyle(color: Colors.red)))
                : DropdownButtonFormField<String>(
                    value: dep,
                    decoration: const InputDecoration(labelText: 'Depo Kodu', border: OutlineInputBorder(), isDense: true),
                    items: depots.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) {
                      setState(() => dep = v!);
                      save();
                    },
                  ),
            const SizedBox(height: 8),
            TextField(
              controller: locC,
              focusNode: locF,
              keyboardType: kb ? TextInputType.text : TextInputType.none,
              onTap: () => openKb(locF),
              decoration: InputDecoration(
                  labelText: 'Lokasyon (okut / yaz / kamera)',
                  prefixIcon: const Icon(Icons.place),
                  suffixIcon: IconButton(icon: const Icon(Icons.photo_camera), tooltip: 'Kamera ile okut', onPressed: camLoc),
                  border: const OutlineInputBorder(),
                  isDense: true),
              onSubmitted: setLoc,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('EKLE'), icon: Icon(Icons.add)),
                  ButtonSegment(value: false, label: Text('ÇIKAR'), icon: Icon(Icons.remove)),
                ],
                selected: {add},
                onSelectionChanged: (s) {
                  setState(() => add = s.first);
                  scanF.requestFocus();
                },
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: scanC,
              focusNode: scanF,
              keyboardType: kb ? TextInputType.text : TextInputType.none,
              onTap: () => openKb(scanF),
              decoration: InputDecoration(
                  labelText: 'Ürün barkodu (okut / yaz / kamera)',
                  prefixIcon: const Icon(Icons.qr_code_scanner),
                  suffixIcon: IconButton(icon: const Icon(Icons.photo_camera), tooltip: 'Kamera ile okut', onPressed: camProd),
                  border: const OutlineInputBorder(),
                  isDense: true),
              onSubmitted: scan,
            ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.only(top: 8),
          color: teal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('Barkod', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Expanded(flex: 4, child: Text('Ürün Adı', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Text('Miktar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = lines[i];
              final v = byBarcode[l.bc];
              final c = l.undef ? Colors.red.shade900 : Colors.black87;
              return InkWell(
                onTap: () => editQty(l),
                child: Container(
                  color: l.undef ? const Color(0xFFFFC7CE) : (i.isEven ? const Color(0xFFE6F7F7) : Colors.white),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(l.bc, style: TextStyle(color: c, fontSize: 13))),
                    Expanded(
                        flex: 4,
                        child: Text(v == null ? 'TANIMSIZ' : '${v.name} ${v.color} ${v.size}',
                            style: TextStyle(color: c, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 48, child: Text('${l.q}', textAlign: TextAlign.right, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 16))),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Text('Toplam: ${lines.fold<int>(0, (s, l) => s + l.q)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              FilledButton.icon(onPressed: finish, icon: const Icon(Icons.save), label: const Text('Kaydet')),
            ]),
          ),
        ),
      ]),
    );
  }
}
