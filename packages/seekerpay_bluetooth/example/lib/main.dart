import 'package:flutter/material.dart';
import 'package:seekerpay_bluetooth/seekerpay_bluetooth.dart';

void main() {
  runApp(const MaterialApp(home: BluetoothExample()));
}

class BluetoothExample extends StatefulWidget {
  const BluetoothExample({super.key});

  @override
  State<BluetoothExample> createState() => _BluetoothExampleState();
}

class _BluetoothExampleState extends State<BluetoothExample> {
  final _nearby = NearbyService();
  final List<String> _foundDevices = [];
  bool _isDiscovering = false;

  Future<void> _startDiscovery() async {
    setState(() {
      _foundDevices.clear();
      _isDiscovering = true;
    });

    _nearby.startDiscovery(onDeviceFound: (id, name) {
      setState(() {
        if (!_foundDevices.contains(name)) {
          _foundDevices.add(name);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SeekerPay Bluetooth Example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.bluetooth_searching_rounded, size: 64, color: Colors.blue),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isDiscovering ? null : _startDiscovery,
              child: Text(_isDiscovering ? 'Discovering...' : 'Search for Nearby Devices'),
            ),
            const SizedBox(height: 48),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Discovered Devices:', style: TextStyle(fontWeight: FontWeight.bold))),
            const Divider(),
            Expanded(
              child: _foundDevices.isEmpty 
                ? const Center(child: Text('No devices found yet.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _foundDevices.length,
                    itemBuilder: (context, index) => ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: Text(_foundDevices[index]),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
