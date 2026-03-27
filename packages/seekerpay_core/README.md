# SeekerPay Core SDK

The foundational SDK for SeekerPay, providing essential Solana blockchain interactions, payment processing, and wallet state management for the SeekerPay ecosystem.

## Features

- **Solana RPC Client**: Simplified JSON-RPC calls for balance, token accounts, and transaction status.
- **Payment Service**: High-level API for building, signing, and sending SKR token transfers.
- **Offline Payments**: Support for queuing signed transactions when offline for later submission.
- **Token Price Service**: Real-time SOL and SKR price fetching via CoinGecko.
- **Activity Tracking**: Comprehensive parsing and tracking of user transaction history.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  seekerpay_core:
    path: ../packages/seekerpay_core
```

## Usage

### RPC Client

```dart
final rpc = RpcClient(rpcUrl: 'https://api.mainnet-beta.solana.com');
final balance = await rpc.getBalance('your_wallet_address');
print('Balance: ${balance.toDouble() / 1e9} SOL');
```

### Payment Service (with Riverpod)

```dart
final paymentService = ref.read(paymentServiceProvider.notifier);
await paymentService.pay(PaymentRequest(
  recipient: 'recipient_address',
  amount: BigInt.from(1000000), // 1 SKR
));
```

### Offline Support

```dart
// The PaymentService automatically handles offline queuing if enabled
await paymentService.pay(request, offlineReady: true);
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
