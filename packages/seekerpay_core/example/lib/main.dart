import 'package:flutter/material.dart';
import 'package:seekerpay_core/seekerpay_core.dart';

void main() {
  runApp(const MaterialApp(home: CoreExample()));
}

class CoreExample extends StatefulWidget {
  const CoreExample({super.key});

  @override
  State<CoreExample> createState() => _CoreExampleState();
}

class _CoreExampleState extends State<CoreExample> {
  final _rpc = RpcClient(rpcUrl: 'https://api.mainnet-beta.solana.com');
  String _balance = 'Unknown';

  Future<void> _fetchBalance() async {
    try {
      // Example address (a known Solana wallet)
      const testAddress = 'HeliusG9277M7yF6Y8L6fV8Y7G9H7G9H7G9H7G9H7G9';
      final balance = await _rpc.getBalance(testAddress);
      setState(() {
        _balance = '${(balance.toDouble() / 1e9).toStringAsFixed(4)} SOL';
      });
    } catch (e) {
      setState(() => _balance = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SeekerPay Core Example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Wallet Balance:', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(_balance, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchBalance,
              child: const Text('Check Balance'),
            ),
          ],
        ),
      ),
    );
  }
}
