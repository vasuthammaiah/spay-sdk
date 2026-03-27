import 'package:flutter/material.dart';
import 'package:seekerpay_qr/seekerpay_qr.dart';

void main() {
  runApp(const MaterialApp(home: QrExample()));
}

class QrExample extends StatelessWidget {
  const QrExample({super.key});

  @override
  Widget build(BuildContext context) {
    // A test recipient address
    const recipient = 'HeliusG9277M7yF6Y8L6fV8Y7G9H7G9H7G9H7G9H7G9';
    final amount = BigInt.from(5000000); // 5.00 SKR

    return Scaffold(
      appBar: AppBar(title: const Text('SeekerPay QR Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Payment QR (5.00 SKR):', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            // We use the generated QR data directly
            QrGenerator.generate(
              recipient: recipient,
              amount: amount,
              label: 'Example Payment',
            ),
            const SizedBox(height: 24),
            const Text('Scan this with any Solana Pay wallet', 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
