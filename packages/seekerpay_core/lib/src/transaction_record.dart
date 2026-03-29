/// Direction of a parsed transaction relative to the viewing wallet.
enum TransactionType { send, receive, unknown }

/// A normalised record representing a single on-chain transaction as seen
/// from a specific wallet address.
class TransactionRecord {
  /// Base58-encoded transaction signature.
  final String signature;

  /// Block time of the transaction.
  final DateTime timestamp;

  /// Transfer amount in token base units (e.g. lamports or token smallest unit).
  final BigInt amount; // in base units (e.g. lamports or token base units)

  /// Whether this transaction is a send, receive, or unknown from the wallet's perspective.
  final TransactionType type;

  /// Address of the other party in the transfer.
  final String counterparty;

  /// Human-readable token symbol (defaults to `'SKR'`).
  final String symbol;

  /// Number of decimal places for the token (defaults to `6`).
  final int decimals;

  /// SPL mint address associated with this transfer, if applicable.
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

  /// Serialises this record to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'signature': signature,
    'timestamp': timestamp.toIso8601String(),
    'amount': amount.toString(),
    'type': type.name,
    'counterparty': counterparty,
    'symbol': symbol,
    'decimals': decimals,
    'mint': mint,
  };

  /// Deserialises a [TransactionRecord] from a JSON map produced by [toJson].
  factory TransactionRecord.fromJson(Map<String, dynamic> json) => TransactionRecord(
    signature: json['signature'],
    timestamp: DateTime.parse(json['timestamp']),
    amount: BigInt.parse(json['amount']),
    type: TransactionType.values.byName(json['type']),
    counterparty: json['counterparty'],
    symbol: json['symbol'] ?? 'SKR',
    decimals: json['decimals'] ?? 6,
    mint: json['mint'],
  );
}
