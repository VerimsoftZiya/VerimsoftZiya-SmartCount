import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'main.dart';

Future<List<Map>> loadRecords() async {
  final d = Directory('${(await getApplicationDocumentsDirectory()).path}/sayimlar');
  if (!await d.exists()) return [];
  final out = <Map>[];
  for (final f in d.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    try {
      final m = jsonDecode(await f.readAsString()) as Map;
      m['_file'] = f.path;
      out.add(m);
    } catch (_) {}
  }
  out.sort((a, b) => '${b['ts']}'.compareTo('${a['ts']}'));
  return out;
}

String dateOf(Map r) => '${r['ts']}'.substring(0, 16).replaceAll('T', ' ');
int totalOf(Map r) => (r['lines'] as List).fold<int>(0, (s, l) => s + (l['q'] as int));

Future<bool> deleteRecord(BuildContext context, Map r) async {
  final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
            title: const Text('Sayım silinsin mi?'),
            content: Text('${dateOf(r)} tarihli sayım ve cihazdaki Excel dosyası silinecek. Bu işlem geri alınamaz.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
            ],
          ));
  if (ok != true) return false;
  try {
    await File(r['_file']).delete();
  } catch (_) {}
  try {
    final x = File('${r['xlsx']}');
    if (await x.exists()) await x.delete();
  } catch (_) {}
  return true;
}

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});
  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  List<Map>? recs;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final r = await loadRecords();
    if (mounted) setState(() => recs = r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kaydedilen Sayımlar')),
      body: recs == null
          ? const Center(child: CircularProgressIndicator())
          : recs!.isEmpty
              ? const Center(child: Text('Henüz kaydedilmiş sayım yok'))
              : ListView.separated(
                  itemCount: recs!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = recs![i];
                    return ListTile(
                      leading: const Icon(Icons.fact_check, color: teal),
                      title: Text('${dateOf(r)}  •  Depo ${r['deps']}'),
                      subtitle: Text('${(r['lines'] as List).length} satır  •  ${totalOf(r)} adet  •  ${r['user']}'),
                      trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            if (await deleteRecord(context, r)) reload();
                          }),
                      onTap: () async {
                        final deleted = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SavedDetail(r)));
                        if (deleted == true) reload();
                      },
                    );
                  },
                ),
    );
  }
}

class SavedDetail extends StatelessWidget {
  final Map r;
  const SavedDetail(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    final lines = r['lines'] as List;
    return Scaffold(
      appBar: AppBar(
        title: Text(dateOf(r), style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await deleteRecord(context, r) && context.mounted) Navigator.pop(context, true);
              }),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFE6F7F7),
          padding: const EdgeInsets.all(12),
          child: Text('Kullanıcı: ${r['user']}   Cihaz: ${r['device']}\nDepo: ${r['deps']}   Toplam: ${totalOf(r)} adet\nExcel: ${r['xlsx']}', style: const TextStyle(fontSize: 12)),
        ),
        Container(
          color: teal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('Barkod', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Expanded(flex: 4, child: Text('Ürün / Lokasyon', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Text('Miktar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = lines[i] as Map;
              final undef = l['u'] == true;
              final c = undef ? Colors.red.shade900 : Colors.black87;
              return Container(
                color: undef ? const Color(0xFFFFC7CE) : (i.isEven ? const Color(0xFFE6F7F7) : Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Expanded(flex: 3, child: Text('${l['bc']}', style: TextStyle(color: c, fontSize: 13))),
                  Expanded(
                      flex: 4,
                      child: Text('${undef ? 'TANIMSIZ' : l['n']}\n${l['dep']} / ${l['loc']}', style: TextStyle(color: c, fontSize: 12))),
                  SizedBox(width: 48, child: Text('${l['q']}', textAlign: TextAlign.right, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 16))),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
