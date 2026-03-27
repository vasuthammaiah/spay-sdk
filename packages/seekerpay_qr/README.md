# SeekerPay QR SDK

A specialized SDK for generating and parsing Solana Pay-compatible QR codes, featuring a built-in scanner overlay for SeekerPay apps.

## Features

- **Solana Pay Compliance**: Fully compatible with the standard Solana Pay URL scheme.
- **QR Generation**: Create high-quality QR codes for payments with amounts, recipients, and labels.
- **Custom Scanner Overlay**: Modern, "Matrix-style" scanner UI for Flutter apps.
- **URL Encoding/Decoding**: Effortless handling of payment requests via `solana:address?amount=...` URLs.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  seekerpay_qr:
    path: ../packages/seekerpay_qr
```

## Usage

### Decoding a Solana Pay URL

```dart
final url = 'solana:vAceH...';
final request = SolanaPayUrl.decode(url);
print('Recipient: ${request.recipient}');
```

### Displaying a Payment QR

```dart
QrPaymentWidget(
  address: 'vAceH...',
  amount: BigInt.from(1000000), // 1 SKR
  label: 'Lunch Bill',
)
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
