import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'main.dart';

/// Kamerayla barkod okur.
/// onCode == null : tek okuma, ilk barkodu döndürüp kapanır (lokasyon için)
/// onCode != null : ürün okutma. Otomatik açıkken kameranın gördüğü her barkod sayılır,
///                  kapalıyken her barkod için ortadaki +/- düğmesine basılır.
class ScanPage extends StatefulWidget {
  final String title;
  final Future<void> Function(String)? onCode;
  final String Function()? feedback;
  final bool Function()? isAdd;
  const ScanPage({super.key, required this.title, this.onCode, this.feedback, this.isAdd});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final ctrl = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  String? lastCode, current;
  DateTime lastSeen = DateTime(2000);
  bool busy = false;
  bool auto = prefs.getBool('auto') ?? false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // Elle modda barkod kameradan çıkınca "Okunan" bilgisini temizle
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (current != null && DateTime.now().difference(lastSeen) > const Duration(milliseconds: 1500)) {
        if (mounted) setState(() => current = null);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  Future<void> onDetect(BarcodeCapture cap) async {
    final code = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    final now = DateTime.now();
    final same = code == lastCode && now.difference(lastSeen) < const Duration(milliseconds: 1500);
    lastSeen = now;
    lastCode = code;
    if (widget.onCode == null) {
      if (busy) return;
      busy = true;
      Navigator.pop(context, code);
      return;
    }
    if (!auto) {
      if (current != code) setState(() => current = code);
      return;
    }
    // Otomatik: sabit duran barkod tekrar sayılmaz; 1.5 sn görünmeyip tekrar gelirse sayılır
    if (same || busy) return;
    busy = true;
    await widget.onCode!(code);
    if (mounted) setState(() {});
    busy = false;
  }

  Future<void> press() async {
    if (busy) return;
    final c = current;
    if (c == null) return;
    busy = true;
    await widget.onCode!(c);
    current = null;
    if (mounted) setState(() {});
    busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final counting = widget.onCode != null;
    final add = widget.isAdd?.call() ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [IconButton(icon: const Icon(Icons.flash_on), onPressed: () => ctrl.toggleTorch())],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: ctrl,
          onDetect: onDetect,
          errorBuilder: (context, error, child) {
            final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
            return Container(
              color: Colors.black,
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                    denied
                        ? 'Kamera izni verilmemiş.\n\nTelefon Ayarları > Uygulamalar > FastCount > İzinler > Kamera > "Uygulama kullanılırken izin ver"'
                        : 'Kamera açılamadı\nKod: ${error.errorCode.name}\n${error.errorDetails?.message ?? ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => ctrl.start(), child: const Text('Tekrar Dene')),
              ]),
            );
          },
        ),
        Center(
          child: Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF00E5E5), width: 3), borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (counting)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(12),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Expanded(
                        child: Text(auto ? 'Otomatik Okutma Açık' : 'Otomatik Okutma Kapalı',
                            style: TextStyle(color: auto ? const Color(0xFF00E5E5) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 16))),
                    Switch(
                        value: auto,
                        onChanged: (v) {
                          setState(() {
                            auto = v;
                            current = null;
                          });
                          prefs.setBool('auto', v);
                        }),
                  ]),
                  if (widget.feedback != null) Text(widget.feedback!(), style: const TextStyle(color: Colors.white, fontSize: 15)),
                  if (!auto) ...[
                    const SizedBox(height: 6),
                    Text(current == null ? 'Barkodu kameraya gösterin' : 'Okunan: $current', style: const TextStyle(color: Color(0xFF00E5E5), fontSize: 16)),
                    const SizedBox(height: 8),
                    FloatingActionButton.large(
                      backgroundColor: current == null ? Colors.grey : teal,
                      foregroundColor: Colors.white,
                      onPressed: current == null ? null : press,
                      child: Icon(add ? Icons.add : Icons.remove, size: 48),
                    ),
                  ],
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
