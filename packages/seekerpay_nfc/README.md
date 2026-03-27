# SeekerPay NFC SDK

A specialized SDK for facilitating contactless Solana payments via NFC (Near Field Communication), enabling "Tap-to-Pay" functionality for SKR tokens.

## Features

- **NFC Transfer Payload**: Compact NDEF record encoding for Solana Pay requests.
- **Bi-Directional Support**: Read payment requests from tags/devices and write requests for others to scan.
- **Secure Handoff**: Optimized for fast, secure transmission of transaction metadata.
- **Cross-Platform**: Unified API for iOS and Android NFC interactions.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  seekerpay_nfc:
    path: ../packages/seekerpay_nfc
```

## Usage

### Reading a Payment Request

```dart
final nfcService = NfcService();
nfcService.startSession(onPayloadRead: (payload) {
  print('Recipient from NFC: ${payload.recipient}');
  print('Amount from NFC: ${payload.amount}');
});
```

### Writing a Payment Request (Tag Mode)

```dart
final payload = NfcTransferPayload(
  recipient: 'vAceH...',
  amount: BigInt.from(1000000), // 1 SKR
  label: 'NFC Coffee',
);
await nfcService.writePayload(payload);
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
