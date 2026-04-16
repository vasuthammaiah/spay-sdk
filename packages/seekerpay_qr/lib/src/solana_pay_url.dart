/// Represents a Solana Pay transfer request URL (`solana:<recipient>?...`).
///
/// Provides [encode] to produce a URI string and [decode] to parse one.
class SolanaPayUrl {
  /// Base58 public key of the payment recipient.
  final String recipient;

  /// Transfer amount in token base units (amount × 10^6 for 6-decimal tokens).
  final BigInt? amount;

  /// SPL token mint address. When omitted, the request is for native SOL.
  final String? splToken;

  /// Optional human-readable label for the payment.
  final String? label;

  /// Optional message to display to the user.
  final String? message;
  SolanaPayUrl({required this.recipient, this.amount, this.splToken, this.label, this.message});
  /// Encodes this object as a `solana:` URI string suitable for embedding in a QR code.
  ///
  /// Uses RFC 3986 percent-encoding (spaces → `%20`) rather than
  /// Dart's `Uri.queryParameters` form-encoding (spaces → `+`), which
  /// some Solana Pay parsers do not handle correctly.
  String encode() {
    final buffer = StringBuffer('solana:');
    buffer.write(recipient); // Base58 — no encoding needed (alphanumeric only)

    final params = <String>[];
    if (amount != null) {
      final decimal = amount!.toDouble() / 1000000;
      // Avoid trailing ".0" for whole numbers (e.g. 1.0 → "1")
      final amountStr = decimal == decimal.truncateToDouble()
          ? decimal.toInt().toString()
          : decimal.toString();
      params.add('amount=$amountStr');
    }
    if (splToken != null) params.add('spl-token=${Uri.encodeComponent(splToken!)}');
    if (label != null)    params.add('label=${Uri.encodeComponent(label!)}');
    if (message != null)  params.add('message=${Uri.encodeComponent(message!)}');

    if (params.isNotEmpty) {
      buffer.write('?');
      buffer.write(params.join('&'));
    }
    return buffer.toString();
  }
  /// Parses a `solana:` URI string into a [SolanaPayUrl].
  ///
  /// Throws [FormatException] if [url] does not start with `solana:`.
  static SolanaPayUrl decode(String url) {
    if (!url.startsWith('solana:')) throw const FormatException('Not a valid Solana Pay URL');
    
    // uri.parse might lowercase the host part if // is used, but Base58 is case sensitive.
    // We'll extract the recipient from the string manually before using Uri.parse for parameters.
    final uri = Uri.parse(url);
    final amountStr = uri.queryParameters['amount'];
    
    // Everything between 'solana:' and '?' or end of string
    final queryStart = url.indexOf('?');
    String recipient = queryStart == -1 
        ? url.substring('solana:'.length) 
        : url.substring('solana:'.length, queryStart);
    
    // Clean up slashes
    while (recipient.startsWith('/')) {
      recipient = recipient.substring(1);
    }
    // Slashes can also be trailing if it was solana://addr/
    while (recipient.endsWith('/')) {
      recipient = recipient.substring(0, recipient.length - 1);
    }

    return SolanaPayUrl(
      recipient: recipient,
      amount: amountStr != null ? BigInt.from((double.parse(amountStr.replaceAll(',', '')) * 1000000).toInt()) : null,
      splToken: uri.queryParameters['spl-token'],
      label: uri.queryParameters['label'],
      message: uri.queryParameters['message'],
    );
  }
}
