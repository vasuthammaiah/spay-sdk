# SeekerPay SDK Monorepo

Welcome to the official SDK repository for SeekerPay, the high-performance, Solana-based mobile payment ecosystem designed for the Seeker mobile platform.

## Overview

This repository contains a suite of specialized SDKs (packages) that power the SeekerPay experience, from core blockchain interactions to contactless NFC/Bluetooth payments.

## Packages

| Package | Description |
|---------|-------------|
| [**seekerpay_core**](./packages/seekerpay_core) | Foundational Solana RPC, payment services, and wallet state. |
| [**seekerpay_domains**](./packages/seekerpay_domains) | SNS (.sol) and Seeker (.skr) domain resolution. |
| [**seekerpay_qr**](./packages/seekerpay_qr) | Solana Pay-compatible QR generation and scanning. |
| [**seekerpay_nfc**](./packages/seekerpay_nfc) | Contactless Tap-to-Pay via NFC NDEF payloads. |
| [**seekerpay_bluetooth**](./packages/seekerpay_bluetooth) | High-speed P2P discovery via BLE and Nearby Connections. |
| [**seekerpay_split**](./packages/seekerpay_split) | Group payment management and on-chain bill tracking. |
| [**seekerpay_ui**](./packages/seekerpay_ui) | Matrix-inspired dark theme and custom payment animations. |

## Quick Start

Most SeekerPay features rely on `seekerpay_core`. To get started, add it to your Flutter project:

```yaml
dependencies:
  seekerpay_core:
    path: ./seekerpay-sdk/packages/seekerpay_core
```

## Architecture

SeekerPay is built with a modular architecture, allowing developers to pick and choose only the components they need. All packages are written in pure Dart/Flutter and optimized for mobile performance on Solana.

## License

All SeekerPay SDKs are licensed under the MIT License.
