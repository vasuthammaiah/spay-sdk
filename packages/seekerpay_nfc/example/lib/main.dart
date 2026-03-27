import 'package:flutter/material.dart';
import 'package:seekerpay_nfc/seekerpay_nfc.dart';

void main() {
  runApp(const MaterialApp(home: NfcExample()));
}

class NfcExample extends StatefulWidget {
  const NfcExample({super.key});

  @override
  State<NfcExample> createState() => _NfcExampleState();
}

class _NfcExampleState extends State<NfcExample> {
  final _nfc = NfcService();
  String _status = 'Ready to Scan';
  bool _isScanning = false;

  Future<void> _startNfcScan() async {
    setState(() {
      _isScanning = true;
      _status = 'Hold your device near an NFC tag or another phone...';
    });

    try {
      final payload = await _nfc.readSinglePayload(); // Simplified helper
      setState(() {
        _status = payload != null 
          ? 'Read Success: ${payload.recipient} for ${(payload.amount!.toDouble() / 1e6).toStringAsFixed(2)} SKR'
          : 'No valid SeekerPay payload found.';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SeekerPay NFC Example')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sensors_rounded, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 48),
              if (!_isScanning)
                ElevatedButton(
                  onPressed: _startNfcScan,
                  child: const Text('Start NFC Scan'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
