import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'main.dart';

const spName = 'dbo.sp_SayimUrunVerisi';

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
  String status = '';
  final sw = Stopwatch();
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void startBusy(String s) {
    status = s;
    sw
      ..reset()
      ..start();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() => busy = true);
  }

  void stopBusy() {
    timer?.cancel();
    sw.stop();
    if (mounted) setState(() => busy = false);
  }

  void msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 6)));

  Future<void> info(String title, String text) => showDialog(
      context: context,
      builder: (_) => AlertDialog(title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))]));

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

  // 1) Verileri Temizle
  Future<void> clearData() async {
    if (byBarcode.isEmpty) return msg('Silinecek veri yok');
    final y = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Verileri Temizle'),
              content: Text('Yüklenmiş tüm ürün bilgileri (${byBarcode.length} barkod) silinecek.\n\nSilmek istediğinize emin misiniz?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır')),
                FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Evet')),
              ],
            ));
    if (y != true) return; // Hayır: bu ekranda kal
    final c = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Son Onay'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Silmek için SİL yazın ve Tamam'a basın."),
                TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tamam')),
              ],
            ));
    if (ok != true) return;
    final t = c.text.trim().toUpperCase();
    if (t != 'SİL' && t != 'SIL') return msg('Yanlış yazdınız, veriler silinmedi');
    try {
      final f = File(dataPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    byBarcode = {};
    setState(() {});
    msg('Tüm ürün verileri silindi');
  }

  // 2) Verileri Yükle (update=false)  /  3) Verileri Güncelle (update=true)
  Future<void> importData(bool update) async {
    if (!update && byBarcode.isNotEmpty) {
      return info('Veri zaten yüklü',
          'Verileri Yükle mevcut veriyi güncellemez.\n\nMevcut ürünleri güncellemek için "Verileri Güncelle" düğmesini kullanın ya da önce "Verileri Temizle" ile silin.');
    }
    if (update && byBarcode.isEmpty) return info('Güncellenecek veri yok', 'Önce "Verileri Yükle" ile ürün verisini yükleyin.');
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv', 'txt']);
    final path = r?.files.single.path;
    if (path == null) return;
    final isX = path.toLowerCase().endsWith('.xlsx');
    startBusy(isX
        ? 'Excel dosyası okunuyor...\nBüyük dosyalarda (100 bin+ satır) bu işlem dakikalar sürebilir. CSV çok daha hızlıdır.'
        : 'Dosya okunuyor ve kaydediliyor...');
    try {
      final st = await importAsync(path, update);
      status = 'Veriler belleğe alınıyor...';
      if (mounted) setState(() {});
      byBarcode = await loadDataAsync();
      stopBusy();
      await info(update ? 'Güncelleme tamamlandı' : 'Yükleme tamamlandı',
          'Dosyadaki geçerli satır: ${st[0]}\nEklenen: ${st[1]}\nGüncellenen: ${st[2]}\nTekrar eden barkod: ${st[3]}${update ? ' (son satır geçerli)' : ' (ilk satır geçerli)'}\nHatalı/boş barkodlu satır: ${st[4]}\n\nToplam barkod: ${st[5]}');
    } catch (e) {
      stopBusy();
      msg('Hata: $e');
    }
  }

  Widget step(int n, String title, String text, Widget action) => Card(
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
              const SizedBox(height: 8),
              action,
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
          Text('Yüklü veri: ${byBarcode.length} barkod', style: const TextStyle(fontWeight: FontWeight.bold, color: tealDark, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFE6F7F7),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Hazırlık: Excel/CSV dosyasını oluşturma', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('1) Aşağıdaki düğmeyle SP script\'ini (.txt) indirip bilgisayara kopyalayın.\n2) SSMS\'te Nebim V3 veritabanında çalıştırın (bir kez).\n3) EXEC dbo.sp_SayimUrunVerisi sonucunu CSV (önerilir) veya Excel olarak kaydedip cihaza kopyalayın.'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(onPressed: downloadSp, icon: const Icon(Icons.download), label: const Text('SP Script\'ini İndir (.txt)')),
              ]),
            ),
          ),
          step(1, 'Verileri Temizle', 'Yüklenmiş tüm ürün bilgilerini siler. İki aşamalı onay istenir.',
              OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: busy ? null : clearData,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Verileri Temizle'))),
          step(2, 'Verileri Yükle', 'Excel/CSV ile ilk yüklemeyi yapar. Daha önce veri yüklendiyse güncellemez. Bir barkod iki kez tanımlanamaz.',
              FilledButton.icon(onPressed: busy ? null : () => importData(false), icon: const Icon(Icons.table_chart), label: const Text('Verileri Yükle'))),
          step(3, 'Verileri Güncelle', 'Var olan ürün bilgilerini günceller, dosyadaki yeni barkodları ekler. Bir barkod asla iki satırda bulunmaz.',
              FilledButton.tonalIcon(onPressed: busy ? null : () => importData(true), icon: const Icon(Icons.sync), label: const Text('Verileri Güncelle'))),
          const SizedBox(height: 8),
          const Text('Dosya ilk satırı başlık olmalı; kolonlar sırayla: UrunKodu, UrunAdi, Renk, Beden, Ozellik1Kod … Ozellik4Ad, Barkod.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
        if (busy)
          Container(
            color: Colors.black45,
            child: Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(status, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Geçen süre: ${sw.elapsed.inSeconds} sn', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 4),
                    const Text('Lütfen uygulamayı kapatmayın.', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
