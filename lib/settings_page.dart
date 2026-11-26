import 'package:flutter/material.dart';
import 'main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String get modeText => countMode() == 'merge' ? 'Aynı barkodları tek satırda birleştir' : 'Her okutma yeni bir satır';

  Future<void> changeUser() async {
    final c = TextEditingController(text: user);
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Kullanıcı Adı Değiştir'),
              content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Yeni kullanıcı adı')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tamam')),
              ],
            ));
    if (ok == true && c.text.trim().isNotEmpty) setState(() => user = c.text.trim());
  }

  Future<void> changeMode() async {
    String sel = countMode();
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
                  title: const Text('Sayım Şekli'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    CheckboxListTile(
                        value: sel == 'merge',
                        title: const Text('Aynı barkodları tek satırda birleştir'),
                        onChanged: (_) => setS(() => sel = 'merge')),
                    CheckboxListTile(
                        value: sel == 'each', title: const Text('Her okutma yeni bir satır'), onChanged: (_) => setS(() => sel = 'each')),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tamam')),
                  ],
                )));
    if (ok == true) {
      await prefs.setString('mode', sel);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.person, color: teal), title: const Text('Kullanıcı Adı Değiştir'), subtitle: Text(user), onTap: changeUser),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.tune, color: teal), title: const Text('Sayım Şekli'), subtitle: Text(modeText), onTap: changeMode),
        const Divider(height: 1),
        ListTile(
            leading: const Icon(Icons.warehouse, color: teal),
            title: const Text('Depo Kodları'),
            subtitle: Text('${getDepots().length} depo'),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const DepotPage()));
              setState(() {});
            }),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(16), child: Text('$appName  •  Cihaz: $device', style: const TextStyle(color: Colors.black54))),
      ]),
    );
  }
}

class DepotPage extends StatefulWidget {
  const DepotPage({super.key});
  @override
  State<DepotPage> createState() => _DepotPageState();
}

class _DepotPageState extends State<DepotPage> {
  List<String> d = getDepots();
  final Set<String> sel = {};

  Future<void> addDepot() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Depo Kodu Ekle'),
              content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Depo kodu (örn. 0722)')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ekle')),
              ],
            ));
    final v = c.text.trim();
    if (ok != true || v.isEmpty) return;
    if (d.contains(v)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu depo kodu zaten var')));
      return;
    }
    d = [...d, v];
    await setDepots(d);
    setState(() {});
  }

  Future<void> deleteSelected() async {
    d = d.where((e) => !sel.contains(e)).toList();
    sel.clear();
    await setDepots(d);
    setState(() {});
  }

  Future<void> deleteAll() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Tüm depo kodları silinsin mi?'),
              content: const Text('Tüm depo kodları silinecek. Emin misiniz?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet')),
              ],
            ));
    if (ok != true) return;
    d = [];
    sel.clear();
    await setDepots(d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Depo Kodları')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: addDepot, icon: const Icon(Icons.add), label: const Text('Depo Kodu Ekle')),
            OutlinedButton.icon(onPressed: sel.isEmpty ? null : deleteSelected, icon: const Icon(Icons.delete_outline), label: Text('Seçileni Sil (${sel.length})')),
            OutlinedButton.icon(onPressed: d.isEmpty ? null : deleteAll, icon: const Icon(Icons.delete_forever), label: const Text('Tümünü Sil')),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: d.isEmpty
              ? const Center(child: Text('Depo kodu yok. "Depo Kodu Ekle" ile ekleyin.'))
              : ListView.builder(
                  itemCount: d.length,
                  itemBuilder: (_, i) => CheckboxListTile(
                    value: sel.contains(d[i]),
                    title: Text(d[i]),
                    onChanged: (v) => setState(() => v == true ? sel.add(d[i]) : sel.remove(d[i])),
                  ),
                ),
        ),
      ]),
    );
  }
}
