# Merkle Tree Reward Distribution (Move)

> ⚠️ **Status: Work in Progress.** This module is under development. A **root challenge period** is planned, allowing challengers to dispute a submitted root within a configurable window. 

A minimal, production‑oriented reward distributor using **Merkle proofs**. Admins publish a Merkle root that commits to each user’s **cumulative** entitlement. Users claim by submitting a proof, the contract pays out the delta since their last claim and prevents double‑spends. 

> Module: `reward_distribution::merkle_tree_distribution`

---

## Table of Contents
- [Overview](#overview)
- [Design & Data Model](#design--data-model)
- [Events](#events)
- [Error Codes](#error-codes)
- [Lifecycle & How It Works](#lifecycle--how-it-works)
- [Admin Functions](#admin-functions)
- [User Function](#user-function)
- [View Functions](#view-functions)
- [Merkle Tree Spec (Off‑chain)](#merkle-tree-spec-off-chain)
- [Security Considerations](#security-considerations)
- [Gas & Complexity](#gas--complexity)
- [Integration Checklist](#integration-checklist)
- [License](#license)

---

## Overview
This module implements distribution of deposited assets to beneficiaries:

- Anyone can deposit tokens into a **vault resource account** controlled by the module.
- For each cycle/epoch, admin uploads a **Merkle root** committing to users’ **cumulative** entitlements.
- A user claims with `(user, entitled_cumulative, proof)`. The module checks the proof against the current root and pays `entitled_cumulative − previously_claimed`.
- Claimed totals are recorded on‑chain to prevent double claims.

---

## Design & Data Model

### Resources
- `State { current_root: vector<u8>, claimed_tokens: Table<address, u64>, admin: address, total_claimed_tokens: u64 }`
  - Stores the active Merkle root, per‑address **claimed total** (cumulative claimed to date), admin address and total tokens claimed from the vault.
- `RewardDistributorController { extend_ref: ExtendRef, vault_signer_cap: SignerCapability, vault_address: address }`
  - Holds capability to operate the **vault resource account** that actually holds funds.

### Vault & Storage Addresses
- **Owner**: `const OWNER: address = @reward_distribution`
- **Vault resource account seed**: `"RewardDistributorResourceAccount"`
- **Storage address seed**: `"RewardDistributorStorageAddress"`
- The vault is a resource account created in `init`, registered for `SupraCoin`, and is the source of payouts.

---

## Events
- `RootUpdated { new_root: vector<u8> }`
- `Deposit { account: address, amount: u64 }`
- `Withdrawal { to: address, amount: u64 }`
- `Claimed { to: address, amount: u64 }`
- `AdminUpdated { new_admin: address }

---

## Error Codes
- `E_NOT_OWNER = 1` — Caller is not the module owner.
- `E_ROOT_EXISTS = 2` — (Reserved; not currently used.)
- `E_ROOT_NOT_FOUND = 3` — (Reserved; not currently used.)
- `E_INVALID_MERKLE_PROOF = 4` — Submitted proof does not reconstruct the active root.
- `E_NOTHING_TO_CLAIM = 5` — User’s `entitled_cumulative` ≤ `claimed_total`.
- `E_INSUFFICIENT_VAULT_FUNDS = 6` — Vault balance < payout.
- `E_INSUFFICIENT_FUNDS = 7` — Depositor balance < requested deposit amount.

---

## Lifecycle & How It Works
1. **Init**: Owner calls `init(&signer)`
   - Creates storage object & resource account (vault), registers `SupraCoin` in vault.
   - Moves `RewardDistributorController` under the object signer.
   - Stores empty `State` under `OWNER` with empty root and table.
   - Registers 
2. **Fund**: Any account can `deposit(&signer, amount)` to send Supra to the vault.
3. **Publish Root**: Owner calls `update_root(&signer, new_root)` for each distribution cycle.
4. **Claim**: User (or any caller on their behalf) calls `claim_rewards(_caller, user, entitled_cumulative, proof)`:
   - Recreates the leaf from `(user, entitled_cumulative)` and verifies proof against `current_root`.
   - Reads `claimed_total[user]` and pays out the **delta**.
   - Updates `claimed_total[user] = entitled_cumulative` and emits `Withdrawal`.
5. **Withdraw Leftovers**: Owner can `withdraw(&owner, amount)` to recover unused funds from the vault.

---

## Admin Functions

### `init(owner: &signer)`
Initializes module state, creates the vault resource account, and registers `SupraCoin` for it. Must be called by `OWNER`.

### `update_root(owner: &signer, new_root: vector<u8>)` (acquires `State`)
Sets the **active** Merkle root. Emits `RootUpdated`.

### `deposit(account: &signer, amount: u64)` (acquires `RewardDistributorController`)
Transfers `amount` of `SupraCoin` from the caller to the **vault**. Emits `Deposit`.

### `withdraw(owner: &signer, amount: u64)` (acquires `RewardDistributorController`)
Transfers `amount` from the **vault** back to the owner. Emits `Withdrawal`.

### `update_admin(owner: &signer, new_admin: address) (acquires State)
Sets a new admin. Emits AdminUpdated { new_admin }

---

## User Function

### `claim_rewards(_caller: &signer, user: address, entitled_cumulative: u64, proof: vector<vector<u8>>)`
- Computes `leaf = sha2_256( bcs(user) || bcs(entitled_cumulative) )`.
- Verifies `proof` against `get_root_value()` via `merkle_tree::verify_merkle_tree`.
- Computes `payout = entitled_cumulative − get_claimed_total(user)`; aborts if ≤ 0.
- Transfers `payout` from **vault** to `user` and updates `claimed_total[user] = entitled_cumulative`.

> **Note:** Anyone can submit the transaction; funds are **always** sent to `user`.

---

## View Functions
- `get_root_value(): vector<u8>` — Current Merkle root.
- `get_claimed_total(user: address): u64` — Cumulative already claimed by `user`.
- `get_vault_balance(): u64` — Vault’s current `SupraCoin` balance.

---

## Merkle Tree Spec (Off‑chain)

### Leaf Encoding
```text
leaf = sha2_256( bcs::to_bytes(user) || bcs::to_bytes(entitled_cumulative) )
```
- `user`: Move `address` serialized with BCS
- `entitled_cumulative`: `u64` serialized with BCS

### Internal Nodes & Proof Order
This module defers verification to `reward_distribution::merkle_tree::verify_merkle_tree(leaf, proof, root)`. Your **off‑chain builder must match the exact concatenation and ordering rules** used by that verifier (e.g., whether pairs are sorted lexicographically before hashing, or whether left/right order is preserved in the proof). To avoid mismatches, build proofs with the same library/logic used by the on‑chain `merkle_tree` module.

### Cumulative Model
Each distribution cycle must include **the total (to‑date) entitlement** for every recipient, not just the increment. This allows late claimers to catch up with a single proof and simplifies replay safety.

---

## Security Considerations
- **Owner gating**: Only `OWNER` can `init`, `update_root`, and `withdraw`.
- **Vault isolation**: Payouts come from a **resource account** controlled by a signer capability held inside `RewardDistributorController`.
- **Double‑claim prevention**: Contract stores `claimed_total[user]`; each claim pays only the delta.
- **Proof integrity**: Incorrect proof or stale cumulative values revert.
- **Funding checks**: Claims revert if the vault is under‑funded.
- **Serialization**: Leaf construction uses **BCS**; any off‑chain code must serialize identically.

Operational suggestions:
- Treat Merkle root publication like releasing a payroll: generate from a reviewed CSV, sign the artifact off‑chain, then post on‑chain.
- Consider independent re‑builders/verifiers in CI to catch tree mismatches before publishing.

---

## Gas & Complexity
- **Claim** is `O(log N)` in the number of recipients (proof length), plus table access and a `transfer`.
- Storage: one table entry per claiming address.

---

## Integration Checklist
- [ ] Call `init` once from `OWNER`.
- [ ] Deposit sufficient `SupraCoin` to cover expected claims.
- [ ] Generate CSV: `(user_address, entitled_cumulative_u64)` for all eligible users.
- [ ] Build Merkle tree using *exactly* the same hashing/ordering logic as the on‑chain verifier.
- [ ] Publish `update_root(new_root)`.
- [ ] Expose a simple claim UI that: (1) fetches `get_root_value`, (2) derives the user’s leaf/proof from your API, (3) submits `claim_rewards`.
- [ ] Monitor `Deposit`, `Withdrawal`, and `RootUpdated` events.

---

## License
Add a license file to the repo root (e.g., `LICENSE`). If you intend broad reuse, **MIT** is a common permissive choice:
```text
MIT License © 2025 Supra Labs
```
(Ensure this aligns with your legal guidance.)
