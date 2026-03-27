# SeekerPay Bluetooth SDK

A specialized SDK for high-speed offline payment discovery and handoff via Bluetooth Low Energy (BLE) and Google Nearby Connections, optimized for P2P SeekerPay interactions.

## Features

- **Nearby Discovery**: High-speed discovery of other SeekerPay devices in the vicinity.
- **Offline Handoff**: Transfer payment requests and signed transactions between devices without internet.
- **Nearby Connections Protocol**: Robust, reliable P2P communication for multi-platform (Android/iOS) support.
- **Low Latency**: Optimized for fast, secure "Nearby" list generation.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  seekerpay_bluetooth:
    path: ../packages/seekerpay_bluetooth
```

## Usage

### Discovering Nearby Payers/Recipients

```dart
final nearby = NearbyService();
nearby.startDiscovery(onDeviceFound: (id, name) {
  print('Found device: $name (ID: $id)');
});
```

### Advertising for Payments

```dart
final nearby = NearbyService();
await nearby.startAdvertising(deviceName: 'Alice\'s Seeker');
```

### Sending a Payment Payload

```dart
await nearby.sendPayload(deviceId, PaymentPayload(
  recipient: 'vAceH...',
  amount: BigInt.from(1000000),
));
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
