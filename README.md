# Merkle Reward Distribution (Move)

A minimal, production-oriented reward distributor that pays users based on a **Merkle root** of cumulative entitlements. Admins update the root; users claim the delta since their last claim. Includes a simple Merkle helper module and tests.

## Modules
- `reward_distribution::merkle_tree` — Merkle helpers (hashing, proof verification).
- `reward_distribution::merkle_tree_distribution` — Core distributor (vault, admin, claim logic). This module is under development. A root challenge period is planned, allowing challengers to dispute a submitted root within a configurable window.

## Key Entry Functions
- `update_root(admin, new_root)` — Set the active Merkle root.
- `deposit(account, amount)` — Fund the vault (SupraCoin).
- `withdraw(owner, withdrawal_address, amount)` — Owner withdraws vault funds.
- `claim_rewards(_caller, user, entitled_cumulative, proof)` — Pays `entitled_cumulative - already_claimed(user)`.

## Merkle Leaf Format
- leaf = sha2_256( bcs::to_bytes(user: address) || bcs::to_bytes(entitled_cumulative: u64) )

## Repo Layout
- `sources/` — Move modules
- `tests/` — Move tests
- `merkle_script/` — JS utilities (hashing/merkle helpers; see src/utils/*)

## Notes
- Coin type: `supra_framework::supra_coin::SupraCoin`.
- Configure the `reward_distribution address` in `Move.toml` before publishing.
- Access control: `owner` can set `admin`; only `admin` can update_root.

  
