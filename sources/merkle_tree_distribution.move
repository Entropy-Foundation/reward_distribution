/// SPDX-License-Identifier: MIT
/// Copyright (C) Supra -- 2025

module reward_distribution::merkle_tree_distribution {
    use std::signer;
    use std::vector;
    use std::error;

    use supra_framework::bcs;
    use supra_framework::hash;
    use supra_framework::table;
    use supra_framework::coin;
    use supra_framework::event;
    use supra_framework::supra_coin::SupraCoin;
    use supra_framework::account;
    use supra_framework::object::{Self, ExtendRef};

    use reward_distribution::merkle_tree;


    /***********************
     * Constants
    ***********************/
    const OWNER: address = @reward_distribution;
    const REWARD_DISTRIBUTOR_RESOURCE_ACCOUNT_SEED: vector<u8> = b"RewardDistributorResourceAccount";
    const REWARD_DISTRIBUTOR_STORAGE_ADDRESS_SEED: vector<u8> = b"RewardDistributorStorageAddress";

    /***********************
     * Errors
    ***********************/
    const E_NOT_OWNER: u64 = 1;
    const E_ROOT_EXISTS: u64 = 2;
    const E_ROOT_NOT_FOUND: u64 = 3;
    const E_INVALID_MERKLE_PROOF: u64 = 4;
    const E_NOTHING_TO_CLAIM: u64 = 5;
    const E_INSUFFICIENT_VAULT_FUNDS: u64 = 6;
    const E_INSUFFICIENT_FUNDS: u64 = 7;
    const E_SUPRA_COIN_NOT_REGISTERED: u64 = 7;

    /***********************
     * Resources
    ***********************/

    #[resource_group_member(group = supra_framework::object::ObjectGroup)]
    struct State has key {
        current_root: vector<u8>,
        claimed_tokens: table::Table<address, u64>,
        admin: address,
        total_claimed_tokens: u64
    }

    #[resource_group_member(group = supra_framework::object::ObjectGroup)]
    struct RewardDistributorController has key {
        extend_ref: ExtendRef,
        vault_signer_cap: account::SignerCapability,
    }

    /***********************
     * Events
    ***********************/

    #[event]
    struct RootUpdated has copy, drop, store {
      new_root: vector<u8>,
    }

    #[event]
    struct AdminUpdated has copy, drop, store {
      new_admin: address,
    }

    #[event]
    struct Deposit has copy, drop, store {
        account: address,
        amount: u64,
    }

    #[event]
    struct Withdrawal has copy, drop, store {
        to: address,
        amount: u64,
    }

    /***************
     * Init Module
    ***************/

    /// Inits the module with relevant info.
    /// Creates object signer, initializes the resources.
    ///
    /// # Arguments
    /// - `owner`: Signer of the owner of this module.
    ///
    ///
    /// # Aborts
    /// - `E_NOT_OWNER` if not the owner of this module
    public entry fun init(owner: &signer) {
        assert!(signer::address_of(owner) == OWNER, error::permission_denied(E_NOT_OWNER));

        let constructor_ref = &object::create_named_object(owner, REWARD_DISTRIBUTOR_STORAGE_ADDRESS_SEED);
        let obj_signer = &object::generate_signer(constructor_ref);
        let extend_ref = object::generate_extend_ref(constructor_ref);

        let (vault_signer, vault_signer_cap) = account::create_resource_account(owner, REWARD_DISTRIBUTOR_RESOURCE_ACCOUNT_SEED);
        coin::register<SupraCoin>(&vault_signer);

        move_to(obj_signer, RewardDistributorController {
            extend_ref: extend_ref,
            vault_signer_cap : vault_signer_cap,
        });

        move_to(obj_signer, State { current_root: vector::empty(), claimed_tokens: table::new<address, u64>(), admin: OWNER, total_claimed_tokens: 0 });
    }

    /***************
     * Entry Admin
    ***************/

    /// Updates the current root in the system.
    ///
    /// # Arguments
    /// - `owner`: Signer of the owner of this module.
    /// - `new_root`: The new root hash that is submitted to the system.
    ///
    /// # Emits
    /// - `RootUpdated`
    ///
    /// # Aborts
    /// - `E_NOT_OWNER` if not the owner of this module
    public entry fun update_root(owner: &signer, new_root: vector<u8>) acquires State, RewardDistributorController {
        assert_owner(owner);
        let state = borrow_global_mut<State>(get_obj_address());

        state.current_root = new_root;

        event::emit<RootUpdated>(
            RootUpdated { new_root }
        );
    }

    /// Updates the current admin of the system.
    ///
    /// # Arguments
    /// - `owner`: Signer of the current owner of this module.
    /// - `new_admin`: The new admin address that is submitted to the system.
    ///
    /// # Emits
    /// - `AdminUpdated`
    ///
    /// # Aborts
    /// - `E_NOT_OWNER` if not the owner of this module
    public entry fun update_admin(owner: &signer, new_admin: address) acquires State, RewardDistributorController {
        assert_owner(owner);
        let state = borrow_global_mut<State>(get_obj_address());

        state.admin = new_admin;

        event::emit<AdminUpdated>(
            AdminUpdated { new_admin }
        );
    }


    /// Updates the current root in the system.
    ///
    /// # Arguments
    /// - `account`: Signer of the account who will deposit Supra.
    /// - `amount`: Amount of Supra being deposited.
    ///
    /// # Emits
    /// - `Deposit`
    ///
    /// # Aborts
    /// - `E_INSUFFICIENT_FUNDS` if account does not have enough Supra
    public entry fun deposit(account: &signer, amount: u64) acquires RewardDistributorController {
        let addr = signer::address_of(account);
        let balance = coin::balance<SupraCoin>(addr);
        assert!(balance >= amount, error::invalid_state(E_INSUFFICIENT_FUNDS));
        coin::transfer<SupraCoin>(account, get_vault_address(), amount);
        event::emit<Deposit>(Deposit { amount, account: addr });
    }

    /// Withdraw the leftover rewards by the admin.
    ///
    /// # Arguments
    /// - `account`: Signer of the account who will with Supra.
    /// - `amount`: Amount of Supra being deposited.
    ///
    /// # Emits
    /// - `Withdrawal`
    ///
    /// # Aborts
    /// - `E_INSUFFICIENT_VAULT_FUNDS` if vault does not have enough Supra
    public entry fun withdraw(owner: &signer, amount: u64) acquires State, RewardDistributorController {
        assert_owner(owner);
        let addr = signer::address_of(owner);
        assert!(get_vault_balance() >= amount, error::invalid_state(E_INSUFFICIENT_VAULT_FUNDS));
        coin::transfer<SupraCoin>(&get_vault_signer(), addr, amount);
        event::emit<Withdrawal>(Withdrawal { amount, to: addr });
    }

    // /***************
    //  * Entry User (CUMULATIVE)
    // ***************/

    /// Claim the rewards awarded to the user.
    ///
    /// # Arguments
    /// - `caller`: Signer of the caller account calling .
    /// - `user`: Account address entitled to reward.
    /// - `entitled_cumulative`: Total Rewards awarded to the user till date.
    /// - `proof`: Vector of proof hash that recreates the merkle root registered by the system.
    ///
    /// # Emits
    /// - `Withdrawal`
    ///
    /// # Aborts
    /// - `E_INVALID_MERKLE_PROOF` if proof is inavlid respective of the system root hash
    /// - `E_NOTHING_TO_CLAIM` if user has already exhausted their rewards
    /// - `E_INSUFFICIENT_VAULT_FUNDS` if the vault does not have sufficient balance to send
    public entry fun claim_rewards(
        _caller: &signer,
        user: address,
        entitled_cumulative: u64,
        proof: vector<vector<u8>>,
    ) acquires State, RewardDistributorController {
        let root = get_root_value();

        let leaf = hash_leaf(user, entitled_cumulative);
        let ok = verify_merkle(root, leaf, proof);
        assert!(ok, error::invalid_argument(E_INVALID_MERKLE_PROOF));

        let claimed_total = get_claimed_total(user);
        assert!(entitled_cumulative > claimed_total, error::invalid_state(E_NOTHING_TO_CLAIM));
        let payout = entitled_cumulative - claimed_total;

        assert!(coin::is_account_registered<SupraCoin>(user), error::invalid_state(E_SUPRA_COIN_NOT_REGISTERED));

        let vault_signer = get_vault_signer();
        let vault_bal = (coin::balance<SupraCoin>(signer::address_of(&vault_signer)));
        assert!(vault_bal >= payout, error::invalid_state(E_INSUFFICIENT_VAULT_FUNDS));

        coin::transfer<SupraCoin>(&vault_signer, user, payout);

        internal_set_claimed_total(user, entitled_cumulative, payout);

        event::emit<Withdrawal>(
            Withdrawal {
                amount: payout,
                to: user,
            }
        );
    }

    /**********************
     * Private Functions
    **********************/

    // Asserts if the signer is the owner of this module
    fun assert_owner(s: &signer) acquires State, RewardDistributorController {
        assert!(signer::address_of(s) == get_admin_address(), error::permission_denied(E_NOT_OWNER));
    }

    // Return the vault signer
    fun get_vault_signer(): signer acquires RewardDistributorController {
        let controller = borrow_global<RewardDistributorController>(get_storage_address());
        account::create_signer_with_capability(&controller.vault_signer_cap)
    }

    // Return the Storage Address
    fun get_storage_address(): address {
        object::create_object_address(&OWNER, REWARD_DISTRIBUTOR_STORAGE_ADDRESS_SEED)
    }

    fun get_obj_signer(): signer acquires RewardDistributorController {
        let controller = borrow_global<RewardDistributorController>(get_storage_address());
        object::generate_signer_for_extending(&controller.extend_ref)
    }

    fun get_obj_address(): address acquires RewardDistributorController {
        signer::address_of(&get_obj_signer())
    }

    // Create a leaf hash out of `user` and `cumulative_amount`
    fun hash_leaf(user: address, cumulative_amount: u64): vector<u8> {
        let bytes = vector::empty<u8>();
        vector::append(&mut bytes, bcs::to_bytes(&user));
        vector::append(&mut bytes, bcs::to_bytes(&cumulative_amount));
        hash::sha2_256(bytes)
    }

    // Verifies the merkle tree based upon `root`, the `leaf` and the `proof`
    fun verify_merkle(
        root: vector<u8>,
        leaf: vector<u8>,
        proof: vector<vector<u8>>,
    ): bool {
        merkle_tree::verify_merkle_tree(leaf, proof, root)
    }

    // Set the total claimed by the `user`
    fun internal_set_claimed_total(user: address, new_total: u64, pay: u64) acquires State, RewardDistributorController {
        let state = borrow_global_mut<State>(get_obj_address());
        table::upsert(&mut state.claimed_tokens, user, new_total);
        state.total_claimed_tokens = state.total_claimed_tokens + pay;
    }

    // /*****************
    //  * View functions
    // *****************/

    // Returns the current root value
    #[view]
    public fun get_root_value(): vector<u8> acquires State, RewardDistributorController {
        borrow_global<State>(get_obj_address()).current_root
    }

    // Returns total claimed of the `user`
    #[view]
    public fun get_claimed_total(user: address): u64 acquires State, RewardDistributorController {
        let state = borrow_global<State>(get_obj_address());
        *table::borrow_with_default(&state.claimed_tokens, user, &0u64)
    }

    // Returns total balance of the vault
    #[view]
    public fun get_vault_balance(): u64 acquires RewardDistributorController {
        coin::balance<SupraCoin>(get_vault_address())
    }

    // Returns total balance of the vault
    #[view]
    public fun get_admin_address(): address acquires State, RewardDistributorController {
        borrow_global<State>(get_obj_address()).admin
    }

    // Returns the total supra claimed by the users
    #[view]
    public fun get_total_claimed(): u64 acquires State, RewardDistributorController {
        borrow_global<State>(get_obj_address()).total_claimed_tokens
    }

    // Returns the vault signer address
    #[view]
    public fun get_vault_address(): address acquires RewardDistributorController {
        signer::address_of(&get_vault_signer())
    }
}
