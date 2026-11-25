import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mssql_connection/mssql_connection.dart';
import 'package:path_provider/path_provider.dart';
import 'main.dart';

const spName = 'dbo.sp_SayimUrunVerisi';
const header = [
  'UrunKodu', 'UrunAdi', 'Renk', 'Beden',
  'Ozellik1Kod', 'Ozellik1Ad', 'Ozellik2Kod', 'Ozellik2Ad',
  'Ozellik3Kod', 'Ozellik3Ad', 'Ozellik4Kod', 'Ozellik4Ad', 'Barkod'
];

const spScript = r'''
-- =====================================================
-- SAYIM UYGULAMASI - URUN VERISI STORED PROCEDURE
-- Nebim V3 veritabaninda BIR KEZ calistirin.
-- Sonra veriyi almak icin:  EXEC dbo.sp_SayimUrunVerisi
-- =====================================================
CREATE OR ALTER PROCEDURE dbo.sp_SayimUrunVerisi
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.ItemCode                          AS UrunKodu,
        d.ItemDescription                   AS UrunAdi,
        v.ColorCode                         AS Renk,
        v.ItemDim1Code                      AS Beden,
        p1.AttributeCode AS Ozellik1Kod, a1.AttributeDescription AS Ozellik1Ad,
        p2.AttributeCode AS Ozellik2Kod, a2.AttributeDescription AS Ozellik2Ad,
        p3.AttributeCode AS Ozellik3Kod, a3.AttributeDescription AS Ozellik3Ad,
        p4.AttributeCode AS Ozellik4Kod, a4.AttributeDescription AS Ozellik4Ad,
        b.Barcode                           AS Barkod
    FROM cdItem i
    JOIN cdItemDesc d
         ON d.ItemTypeCode = i.ItemTypeCode AND d.ItemCode = i.ItemCode AND d.LangCode = 'TR'
    JOIN prItemVariant v
         ON v.ItemTypeCode = i.ItemTypeCode AND v.ItemCode = i.ItemCode
    JOIN prItemBarcode b
         ON b.ItemTypeCode = v.ItemTypeCode AND b.ItemCode = v.ItemCode
        AND b.ColorCode = v.ColorCode
        AND b.ItemDim1Code = v.ItemDim1Code AND b.ItemDim2Code = v.ItemDim2Code
        AND b.ItemDim3Code = v.ItemDim3Code
    LEFT JOIN prItemAttribute p1 ON p1.ItemTypeCode = i.ItemTypeCode AND p1.ItemCode = i.ItemCode AND p1.AttributeTypeCode = 1
    LEFT JOIN ItemAttribute('TR') a1 ON a1.ItemTypeCode = p1.ItemTypeCode AND a1.AttributeTypeCode = p1.AttributeTypeCode AND a1.AttributeCode = p1.AttributeCode
    LEFT JOIN prItemAttribute p2 ON p2.ItemTypeCode = i.ItemTypeCode AND p2.ItemCode = i.ItemCode AND p2.AttributeTypeCode = 2
    LEFT JOIN ItemAttribute('TR') a2 ON a2.ItemTypeCode = p2.ItemTypeCode AND a2.AttributeTypeCode = p2.AttributeTypeCode AND a2.AttributeCode = p2.AttributeCode
    LEFT JOIN prItemAttribute p3 ON p3.ItemTypeCode = i.ItemTypeCode AND p3.ItemCode = i.ItemCode AND p3.AttributeTypeCode = 3
    LEFT JOIN ItemAttribute('TR') a3 ON a3.ItemTypeCode = p3.ItemTypeCode AND a3.AttributeTypeCode = p3.AttributeTypeCode AND a3.AttributeCode = p3.AttributeCode
    LEFT JOIN prItemAttribute p4 ON p4.ItemTypeCode = i.ItemTypeCode AND p4.ItemCode = i.ItemCode AND p4.AttributeTypeCode = 4
    LEFT JOIN ItemAttribute('TR') a4 ON a4.ItemTypeCode = p4.ItemTypeCode AND a4.AttributeTypeCode = p4.AttributeTypeCode AND a4.AttributeCode = p4.AttributeCode;
END
GO
''';
class DataPage extends StatefulWidget {
  const DataPage({super.key});
  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  bool busy = false;

  void msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 6)));

  Future<String> saveFile(String name, List<int> bytes) async {
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

  Future<void> downloadSp() async {
    final p = await saveFile('sp_SayimUrunVerisi.txt', [0xEF, 0xBB, 0xBF, ...utf8.encode(spScript)]);
    msg(p.isEmpty ? 'Dosya yazılamadı' : 'Kaydedildi: $p\nBilgisayara kopyalayıp SSMS ile açın.');
  }

  String cs(CellValue? v) {
    if (v == null) return '';
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is IntCellValue) return v.value.toString();
    if (v is TextCellValue) return v.value.toString();
    return v.toString();
  }

  Future<void> finishLoad(List<List<String>> rows) async {
    await (await dataFile()).writeAsString(const ListToCsvConverter(fieldDelimiter: ';').convert(rows));
    applyRows(rows);
    setState(() {});
    msg('${byBarcode.length} barkod yüklendi');
  }

  Future<void> fromFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv', 'txt']);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() => busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      List<List<String>> rows;
      if (path.toLowerCase().endsWith('.xlsx')) {
        final x = Excel.decodeBytes(bytes);
        rows = x.tables.values.first.rows.map((r) => r.map((c) => cs(c?.value)).toList()).toList();
      } else {
        var t = utf8.decode(bytes, allowMalformed: true).replaceAll('\uFEFF', '');
        final d = t.split('\n').first.contains(';') ? ';' : ',';
        rows = const CsvToListConverter(shouldParseNumbers: false)
            .convert(t, fieldDelimiter: d, eol: '\n')
            .map((r) => r.map((e) => e.toString()).toList())
            .toList();
      }
      await finishLoad(rows);
    } catch (e) {
      msg('Dosya okunamadı: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> fromDb() async {
    final keys = ['ip', 'port', 'db', 'user', 'pw'];
    final labels = {'ip': 'Sunucu IP', 'port': 'Port', 'db': 'Veritabanı adı', 'user': 'Kullanıcı', 'pw': 'Şifre'};
    final c = {for (final k in keys) k: TextEditingController(text: k == 'pw' ? '' : (prefs.getString('db_$k') ?? (k == 'port' ? '1433' : '')))};
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Veritabanı Bağlantısı'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final k in keys)
                  TextField(controller: c[k], obscureText: k == 'pw', decoration: InputDecoration(labelText: labels[k])),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Veriyi Çek')),
              ],
            ));
    if (ok != true) return;
    for (final k in ['ip', 'port', 'db', 'user']) {
      await prefs.setString('db_$k', c[k]!.text.trim());
    }
    setState(() => busy = true);
    try {
      final conn = MssqlConnection.getInstance();
      final connected = await conn.connect(
          ip: c['ip']!.text.trim(),
          port: c['port']!.text.trim(),
          databaseName: c['db']!.text.trim(),
          username: c['user']!.text.trim(),
          password: c['pw']!.text,
          timeoutInSeconds: 20);
      if (!connected) throw 'Bağlantı kurulamadı';
      final res = await conn.getData('EXEC $spName');
      await conn.disconnect();
      final list = jsonDecode(res) as List;
      if (list.isEmpty) throw 'Sorgu sonuç döndürmedi (SP oluşturuldu mu?)';
      final rows = [header, ...list.map((m) => header.map((h) => '${(m as Map)[h] ?? ''}').toList())];
      await finishLoad(rows);
    } catch (e) {
      msg('Hata: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget step(int n, String title, String text, [Widget? action]) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: teal, foregroundColor: Colors.white, radius: 14, child: Text('$n')),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text(text),
              if (action != null) ...[const SizedBox(height: 8), action],
            ])),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Veri Yükle')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.all(12), children: [
          Text('Yüklü veri: ${byBarcode.length} barkod', style: const TextStyle(fontWeight: FontWeight.bold, color: tealDark)),
          const SizedBox(height: 8),
          step(1, 'SP script\'ini indirin', 'Aşağıdaki düğme, veritabanında oluşturulacak stored procedure\'ü .txt olarak cihazın Download klasörüne kaydeder. Dosyayı bilgisayarınıza kopyalayın.',
              FilledButton.icon(onPressed: downloadSp, icon: const Icon(Icons.download), label: const Text('SP Script\'ini İndir (.txt)'))),
          step(2, 'SP\'yi veritabanında oluşturun', 'SQL Server Management Studio\'da Nebim V3 veritabanını seçin, .txt içeriğini yeni sorgu penceresine yapıştırıp çalıştırın (F5). Bu işlem bir kez yapılır.'),
          step(3, 'Veriyi alın', 'Seçenek A: SSMS\'te  EXEC $spName  çalıştırın, sonucu Excel veya CSV olarak kaydedip cihaza kopyalayın.\nSeçenek B: Cihaz sunucuyla aynı ağdaysa doğrudan veritabanından çekin.'),
          const SizedBox(height: 8),
          SizedBox(
              height: 56,
              child: FilledButton.icon(onPressed: busy ? null : fromFile, icon: const Icon(Icons.table_chart), label: const Text('Excel / CSV ile Veri Yükle'))),
          const SizedBox(height: 12),
          SizedBox(
              height: 56,
              child: FilledButton.tonalIcon(onPressed: busy ? null : fromDb, icon: const Icon(Icons.storage), label: const Text('Database\'den Veri Çek'))),
          const SizedBox(height: 12),
          const Text('Excel/CSV ilk satırı başlık olmalı; kolonlar sırayla: UrunKodu, UrunAdi, Renk, Beden, Ozellik1Kod … Ozellik4Ad, Barkod.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
        if (busy) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
      ]),
    );
  }
}
