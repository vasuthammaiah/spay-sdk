import 'package:seekerpay_core/seekerpay_core.dart';

/// Verifies whether a wallet holds a recognised SeekerPay genesis token.
///
/// Two token types grant verified status:
///
///   1. **Seeker Genesis Token (SGT)** — each Seeker device generates its own
///      unique, non-transferable mint, so verification is done by collection
///      membership rather than a shared mint address.
///      Collection group:    GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te
///      Mint authority:      GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4
///
///   2. **Chapter 2 Preorder Token** — a fungible Token-2022 token with a
///      single shared mint address issued to all Chapter 2 pre-order holders.
///      Mint: 2DMMamkkxQ6zDMBtkFp8KH7FoWzBMBA1CGTYwom4QH6Z
///
/// Verification strategy (two layers):
///   • Primary   — Helius DAS `getAssetsByOwner`: checks `grouping` field for
///                 the SGT collection address and `id` for the Chapter 2 mint.
///   • Fallback  — Standard Solana RPC: checks Token-2022 program accounts
///                 directly, inspecting mint account extensions for group
///                 membership (SGT) and exact mint match (Chapter 2).
class GenesisChecker {
  final RpcClient _rpc;

  /// Official Seeker Genesis Token collection / group address.
  /// Every per-device SGT mint has this as its Token-2022 group.
  static const _sgtGroupAddress = 'GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te';

  /// Mint authority used when creating SGT mints.
  /// Used as a lightweight indicator in the standard-RPC fallback path.
  static const _sgtMintAuthority = 'GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4';

  /// Chapter 2 Preorder Token — shared mint, all holders have the same address.
  static const _chapter2Mint = '2DMMamkkxQ6zDMBtkFp8KH7FoWzBMBA1CGTYwom4QH6Z';

  GenesisChecker(this._rpc);

  /// Returns `true` when [address] holds at least one verified genesis token.
  Future<bool> hasGenesisToken(String address) async {
    // ── Layer 1: Helius DAS ────────────────────────────────────────────────
    // getAssetsByOwner returns full asset metadata including the `grouping`
    // field, which is the reliable way to identify per-device SGT mints as
    // belonging to the official Seeker Genesis Token collection.
    try {
      final assets = await _rpc.getAssetsByOwner(address, showFungible: true);
      for (final asset in assets) {
        // Chapter 2 Preorder Token — check by shared mint address.
        if (asset['id'] == _chapter2Mint) return true;

        // SGT — check by collection group membership.
        final groupings = (asset['grouping'] as List?) ?? [];
        for (final g in groupings) {
          if (g['group_key'] == 'collection' &&
              g['group_value'] == _sgtGroupAddress) {
            return true;
          }
        }
      }
    } catch (_) {}

    // ── Layer 2: Standard RPC fallback (no Helius required) ───────────────
    // Chapter 2: direct Token-2022 balance check by shared mint.
    try {
      final balance = await _rpc.getToken22BalanceByMint(address, _chapter2Mint);
      if (balance > BigInt.zero) return true;
    } catch (_) {}

    // SGT: inspect Token-2022 mint accounts for group extension / authority.
    try {
      final verified = await _rpc.hasToken22InGroup(
        address,
        groupAddress: _sgtGroupAddress,
        mintAuthority: _sgtMintAuthority,
      );
      if (verified) return true;
    } catch (_) {}

    return false;
  }
}
