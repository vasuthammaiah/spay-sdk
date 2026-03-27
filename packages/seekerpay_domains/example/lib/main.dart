import 'package:flutter/material.dart';
import 'package:seekerpay_domains/seekerpay_domains.dart';
import 'package:seekerpay_core/seekerpay_core.dart';

void main() {
  runApp(const MaterialApp(home: DomainExample()));
}

class DomainExample extends StatefulWidget {
  const DomainExample({super.key});

  @override
  State<DomainExample> createState() => _DomainExampleState();
}

class _DomainExampleState extends State<DomainExample> {
  final _rpc = RpcClient(rpcUrl: 'https://api.mainnet-beta.solana.com');
  late final SnsResolver _resolver;
  final _controller = TextEditingController(text: 'solana.sol');
  String _address = 'Not resolved';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _resolver = SnsResolver(_rpc);
  }

  Future<void> _resolve() async {
    setState(() => _isLoading = true);
    try {
      final addr = await _resolver.resolve(_controller.text);
      setState(() => _address = addr ?? 'Not found');
    } catch (e) {
      setState(() => _address = 'Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SeekerPay Domain Example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Enter Domain (.sol or .skr)')),
            const SizedBox(height: 24),
            _isLoading 
              ? const CircularProgressIndicator()
              : ElevatedButton(onPressed: _resolve, child: const Text('Resolve Domain')),
            const SizedBox(height: 48),
            const Text('Resolved Address:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            SelectableText(_address, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Courier')),
          ],
        ),
      ),
    );
  }
}
