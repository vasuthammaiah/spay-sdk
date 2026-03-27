import 'package:flutter/material.dart';
import 'package:seekerpay_ui/seekerpay_ui.dart';

void main() {
  runApp(const MaterialApp(
    home: UiExample(),
    debugShowCheckedModeBanner: false,
  ));
}

class UiExample extends StatefulWidget {
  const UiExample({super.key});

  @override
  State<UiExample> createState() => _UiExampleState();
}

class _UiExampleState extends State<UiExample> {
  bool _isAnimating = true;

  @override
  Widget build(BuildContext context) {
    // We apply our theme manually for the example
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        appBar: AppBar(title: const Text('SeekerPay UI Example')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('NFC Pulse Animation:', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 32),
                NfcPulseAnimation(
                  isScanning: _isAnimating,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.sensors_rounded, size: 48, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 64),
                ElevatedButton(
                  onPressed: () => setState(() => _isAnimating = !_isAnimating),
                  child: Text(_isAnimating ? 'Stop Animation' : 'Start Animation'),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Sample Outlined Button'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
