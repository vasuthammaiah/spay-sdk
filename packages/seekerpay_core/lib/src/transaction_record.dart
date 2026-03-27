enum TransactionType { send, receive, unknown }

class TransactionRecord {
  final String signature;
  final DateTime timestamp;
  final BigInt amount; // in base units (e.g. lamports or token base units)
  final TransactionType type;
  final String counterparty;
  final String symbol;
  final int decimals;
  final String? mint;

  TransactionRecord({
    required this.signature,
    required this.timestamp,
    required this.amount,
    required this.type,
    required this.counterparty,
    this.symbol = 'SKR',
    this.decimals = 6,
    this.mint,
  });
}
