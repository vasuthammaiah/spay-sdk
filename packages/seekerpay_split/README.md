# SeekerPay Split SDK

A specialized SDK for managing group payments and bill splitting using SKR tokens on Solana.

## Features

- **Split Bill Management**: Create, track, and settle bills across multiple participants.
- **On-Chain Tracking**: Automatic verification of participant payments via RPC lookups.
- **Progress Monitoring**: Real-time updates on which participants have paid.
- **Multi-Payer Support**: Optimized for one-to-many and many-to-one payment flows.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  seekerpay_split:
    path: ../packages/seekerpay_split
```

## Usage

### Creating a Split Bill

```dart
final manager = SplitBillManager(rpcClient);
final bill = SplitBill(
  id: 'lunch-123',
  label: 'Lunch at Seeker Cafe',
  totalAmount: BigInt.from(5000000), // 5 SKR
  participants: [
    SplitParticipant(address: 'vAceH...', share: 0.5),
    SplitParticipant(address: 'HeliusG...', share: 0.5),
  ],
);
await manager.create(bill);
```

### Checking Payment Status

```dart
final updatedBill = await manager.refreshSplitStatus('lunch-123');
print('Paid Count: ${updatedBill.paidCount}');
print('Fully Paid: ${updatedBill.isFullyPaid}');
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
