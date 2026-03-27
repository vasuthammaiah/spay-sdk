# SeekerPay UI SDK

The official UI component library for the SeekerPay ecosystem, featuring high-performance, "Matrix-inspired" dark theme components and custom Solana-centric animations.

## Features

- **Matrix Dark Theme**: A high-contrast, performance-focused dark theme optimized for OLED mobile displays.
- **Custom Animations**: Ready-to-use animations like the `NfcPulseAnimation` for contactless payments.
- **Standardized Sheets**: Drop-in UI for common payment tasks, including the `PaymentPreviewSheet`.
- **Icon Set**: Curated icons and styles that match the SeekerPay aesthetic.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  seekerpay_ui:
    path: ../packages/seekerpay_ui
```

## Usage

### Applying the Theme

```dart
MaterialApp(
  theme: AppTheme.darkTheme,
  home: HomeScreen(),
)
```

### Using the NFC Animation

```dart
NfcPulseAnimation(
  isScanning: true,
  child: Icon(Icons.sensors),
)
```

### Displaying a Payment Preview

```dart
showModalBottomSheet(
  context: context,
  builder: (context) => PaymentPreviewSheet(
    request: paymentRequest,
    onConfirm: (isOfflineReady) => _handleConfirm(isOfflineReady),
  ),
);
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
