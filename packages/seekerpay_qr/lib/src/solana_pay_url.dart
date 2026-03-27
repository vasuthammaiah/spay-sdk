class SolanaPayUrl {
  final String recipient;
  final BigInt? amount;
  final String? splToken;
  final String? label;
  final String? message;
  SolanaPayUrl({required this.recipient, this.amount, this.splToken, this.label, this.message});
  String encode() {
    final uri = Uri(scheme: 'solana', path: recipient, queryParameters: {
      if (amount != null) 'amount': (amount!.toDouble() / 1000000).toString(),
      if (splToken != null) 'spl-token': splToken,
      if (label != null) 'label': label,
      if (message != null) 'message': message,
    });
    return uri.toString();
  }
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
