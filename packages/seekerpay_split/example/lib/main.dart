import 'package:flutter/material.dart';
import 'package:seekerpay_split/seekerpay_split.dart';
import 'package:seekerpay_core/seekerpay_core.dart';

void main() {
  runApp(const MaterialApp(home: SplitExample()));
}

class SplitExample extends StatefulWidget {
  const SplitExample({super.key});

  @override
  State<SplitExample> createState() => _SplitExampleState();
}

class _SplitExampleState extends State<SplitExample> {
  final _rpc = RpcClient(rpcUrl: 'https://api.mainnet-beta.solana.com');
  late final SplitBillManager _manager;
  SplitBill? _activeBill;

  @override
  void initState() {
    super.initState();
    _manager = SplitBillManager(_rpc);
    
    // Create a mock active bill for demonstration
    _activeBill = SplitBill(
      id: 'demo-split',
      label: 'Demo Split Bill',
      totalAmount: BigInt.from(2000000), // 2 SKR
      participants: [
        SplitParticipant(address: 'vAceH...', share: 0.5), // 1 SKR
        SplitParticipant(address: 'HeliusG...', share: 0.5), // 1 SKR
      ],
    );
  }

  Future<void> _refreshStatus() async {
    if (_activeBill == null) return;
    try {
      final updated = await _manager.refreshSplitStatus(_activeBill!.id, 'vAceH...');
      setState(() => _activeBill = updated);
    } catch (e) {
      print('Status Refresh Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeBill == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('SeekerPay Split Example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_rounded, size: 64, color: Colors.green),
            const SizedBox(height: 24),
            Text(_activeBill!.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('TOTAL: ${(_activeBill!.totalAmount.toDouble() / 1e6).toStringAsFixed(2)} SKR'),
            const SizedBox(height: 32),
            const Align(alignment: Alignment.centerLeft, child: Text('PARTICIPANTS:', style: TextStyle(fontWeight: FontWeight.bold))),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _activeBill!.participants.length,
                itemBuilder: (context, index) {
                  final p = _activeBill!.participants[index];
                  return ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: Text(p.address.substring(0, 8) + '...'),
                    subtitle: Text('${p.share * 100}% Share'),
                    trailing: p.hasPaid 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.pending_outlined, color: Colors.orange),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: _refreshStatus,
              child: const Text('Check Payment Status (On-Chain)'),
            ),
          ],
        ),
      ),
    );
  }
}
