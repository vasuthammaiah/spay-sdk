# SeekerPay Domains SDK

A specialized SDK for resolving Solana Name Service (SNS) domains, including standard `.sol` domains and Seeker-specific `.skr` domains.

## Features

- **SNS Resolution**: Resolve any `.sol` or `.skr` domain to a Solana wallet address.
- **Multi-API Support**: Fallback logic across TLD House, Bonfida, and on-chain RPC calls.
- **Local Caching**: Integrated SQLite caching for fast resolution of previously seen domains.
- **Genesis Verification**: Identify wallets holding "Genesis" tokens for premium features.
- **Reverse Resolution**: Find associated domains for a given wallet address from cache.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  seekerpay_domains:
    path: ../packages/seekerpay_domains
```

## Usage

### Simple Resolution

```dart
final resolver = SnsResolver(rpcClient);
final address = await resolver.resolve('alice.skr');
print('Resolved Address: $address');
```

### With Persistence

```dart
final cache = DomainCache();
final resolver = SnsResolver(rpcClient, cache);
// Results will be automatically cached locally
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
