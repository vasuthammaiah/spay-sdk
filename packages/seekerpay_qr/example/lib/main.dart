/// seekerpay_qr — example app.
///
/// Demonstrates encoding a Solana Pay URL and rendering it as a QR code,
/// then decoding a URL back into its component fields.
library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:seekerpay_core/seekerpay_core.dart';
import 'package:seekerpay_qr/seekerpay_qr.dart';

void main() {
  runApp(const MaterialApp(
    title: 'seekerpay_qr example',
    home: _HomeScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();
  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  // Replace with a real Solana wallet address for testing.
  static const _recipient = 'RECIPIENT_WALLET_ADDRESS';

  final _amountController = TextEditingController(text: '2.5');
  String? _encodedUrl;
  SolanaPayUrl? _decoded;

  void _generate() {
    final parsed = double.tryParse(_amountController.text.trim());
    if (parsed == null || parsed <= 0) return;

    final url = SolanaPayUrl(
      recipient: _recipient,
      amount: BigInt.from((parsed * 1000000).toInt()), // convert to base units
      splToken: SKRToken.mintAddress,
      label: 'QR Example',
    ).encode();

    setState(() {
      _encodedUrl = url;
      _decoded = SolanaPayUrl.decode(url); // round-trip decode
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('seekerpay_qr')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (SKR)',
                border: OutlineInputBorder(),
                suffixText: 'SKR',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _generate, child: const Text('Generate QR')),
            const SizedBox(height: 24),

            if (_encodedUrl != null) ...[
              // QR code
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                    data: _encodedUrl!,
                    version: QrVersions.auto,
                    size: 200,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                    dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Encoded URL
              const Text('Encoded URL:', style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 4),
              SelectableText(_encodedUrl!, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)),
              const SizedBox(height: 16),

              // Decoded fields
              if (_decoded != null) ...[
                const Text('Decoded fields:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 4),
                _Field('recipient', _decoded!.recipient),
                _Field('amount (base units)', _decoded!.amount.toString()),
                _Field('display amount', '${(_decoded!.amount!.toDouble() / 1e6).toStringAsFixed(6)} SKR'),
                _Field('spl-token', _decoded!.splToken ?? '—'),
                _Field('label', _decoded!.label ?? '—'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 130,
            child: Text('$label:', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          Expanded(child: SelectableText(value, style: const TextStyle(fontFamily: 'Courier', fontSize: 11))),
        ]),
      );
}
