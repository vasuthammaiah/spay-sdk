import 'dart:typed_data';
import 'package:solana_web3/solana_web3.dart' as web3;

/// Constants for the SKR SPL token on Solana mainnet.
class SKRToken {
  /// The SPL mint address for the SKR token.
  static const String mintAddress = 'SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3';

  /// Number of decimal places used by the SKR token (1 SKR = 10^6 base units).
  static const int decimals = 6;
}

/// Builds serialised SPL token transfer transactions.
class SplTokenTransfer {
  /// Builds a single-recipient SPL token transfer transaction.
  ///
  /// Delegates to [buildMulti] with one [MultiTransfer] entry.
  /// Set [createRecipientATA] to `true` to prepend an ATA-creation instruction
  /// when the recipient's associated token account does not yet exist.
  static Future<Uint8List> build({
    required String payer,
    required String recipient,
    required String mint,
    required BigInt amount,
    required String blockhash,
    bool createRecipientATA = false,
  }) async {
    return buildMulti(
      payer: payer,
      transfers: [
        MultiTransfer(recipient: recipient, amount: amount, needsATA: createRecipientATA)
      ],
      mint: mint,
      blockhash: blockhash,
    );
  }

  /// Builds a versioned (v0) SPL token transfer transaction for one or more
  /// [transfers] from [payer]'s associated token account.
  ///
  /// For each transfer marked with [MultiTransfer.needsATA], an
  /// `AssociatedTokenAccount` creation instruction is prepended.
  static Future<Uint8List> buildMulti({
    required String payer,
    required List<MultiTransfer> transfers,
    required String mint,
    required String blockhash,
  }) async {
    final payerPubkey = web3.Pubkey.fromBase58(payer.trim());
    final mintPubkey = web3.Pubkey.fromBase58(mint.trim());
    final payerATA = _findATA(payerPubkey, mintPubkey);

    final List<web3.TransactionInstruction> instructions = [];

    for (final t in transfers) {
      final recipientPubkey = web3.Pubkey.fromBase58(t.recipient.trim());
      final recipientATA = _findATA(recipientPubkey, mintPubkey);

      if (t.needsATA) {
        instructions.add(web3.TransactionInstruction(
          keys: [
            web3.AccountMeta(payerPubkey, isWritable: true, isSigner: true),
            web3.AccountMeta(recipientATA, isWritable: true, isSigner: false),
            web3.AccountMeta(recipientPubkey, isWritable: false, isSigner: false),
            web3.AccountMeta(mintPubkey, isWritable: false, isSigner: false),
            web3.AccountMeta(web3.Pubkey.fromBase58('11111111111111111111111111111111'), isWritable: false, isSigner: false),
            web3.AccountMeta(web3.Pubkey.fromBase58('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'), isWritable: false, isSigner: false),
          ],
          programId: web3.Pubkey.fromBase58('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL'),
          data: Uint8List(0),
        ));
      }

      final data = ByteData(9);
      data.setUint8(0, 3); // index for transfer
      data.setUint64(1, t.amount.toInt(), Endian.little);

      instructions.add(web3.TransactionInstruction(
        keys: [
          web3.AccountMeta(payerATA, isWritable: true, isSigner: false),
          web3.AccountMeta(recipientATA, isWritable: true, isSigner: false),
          web3.AccountMeta(payerPubkey, isWritable: false, isSigner: true),
        ],
        programId: web3.Pubkey.fromBase58('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
        data: data.buffer.asUint8List(),
      ));
    }

    final transaction = web3.Transaction.v0(
      payer: payerPubkey,
      instructions: instructions,
      recentBlockhash: blockhash,
    );
    
    return transaction.serialize().asUint8List();
  }

  static web3.Pubkey _findATA(web3.Pubkey owner, web3.Pubkey mint) {
    final List<List<int>> seeds = [
      owner.toBytes(),
      web3.Pubkey.fromBase58('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA').toBytes(),
      mint.toBytes(),
    ];
    return web3.Pubkey.findProgramAddress(
      seeds, 
      web3.Pubkey.fromBase58('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL')
    ).pubkey;
  }
}

/// Describes a single transfer leg within a multi-recipient transaction.
class MultiTransfer {
  /// Base58 public key of the token recipient.
  final String recipient;

  /// Transfer amount in token base units.
  final BigInt amount;

  /// Whether an Associated Token Account creation instruction should be
  /// included for this recipient.
  final bool needsATA;

  MultiTransfer({
    required this.recipient,
    required this.amount,
    this.needsATA = false,
  });
}
