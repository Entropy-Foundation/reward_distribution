#[test_only]
module reward_distribution::merkle_tree_distribution_tests {
    use std::signer;
    use std::vector;

    use supra_framework::account;
    use supra_framework::coin;
    use supra_framework::hash;
    use supra_framework::bcs;

    use supra_framework::supra_coin::SupraCoin;

    use reward_distribution::merkle_tree_distribution;

    /***********************
     * Test Addresses
    ***********************/
    const OWNER: address  = @reward_distribution;
    const ALICE: address  = @0xA11CE;
    const BOB: address    = @0xB0B;
    const ADMIN: address  = @supra_framework;

    /***********************
     * Helpers
    ***********************/
    fun ensure_accounts() {
        account::create_account_for_test(OWNER);
        account::create_account_for_test(ALICE);
        account::create_account_for_test(BOB);
        account::create_account_for_test(ADMIN);
    }

    fun register(who: &signer) {
        coin::register<SupraCoin>(who);
    }

    fun init_supra(admin: &signer): (coin::BurnCapability<SupraCoin>, coin::MintCapability<SupraCoin>) {
        supra_framework::supra_coin::initialize_for_test(admin)
    }

    fun mint_to(mint_cap: &coin::MintCapability<SupraCoin>, to_addr: address, amount: u64) {
        let c = coin::mint<SupraCoin>(amount, mint_cap);
        coin::deposit<SupraCoin>(to_addr, c);
    }

    fun bal(addr: address): u64 {
        coin::balance<SupraCoin>(addr)
    }

    fun make_leaf(user: address, cumulative_amount: u64): vector<u8> {
        let bytes = vector::empty<u8>();
        vector::append(&mut bytes, bcs::to_bytes(&user));
        vector::append(&mut bytes, bcs::to_bytes(&cumulative_amount));
        hash::sha2_256(bytes)
    }

    fun empty_proof(): vector<vector<u8>> {
        vector::empty<vector<u8>>()
    }

    /***********************
     * init()
    ***********************/

    #[test(supra = @0x1, admin = @supra_framework, owner = @reward_distribution)]
    fun test_init_by_owner_succeeds(supra: &signer, admin: &signer, owner: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        merkle_tree_distribution::init(owner);

        let root = merkle_tree_distribution::get_root_value();
        assert!(vector::length(&root) == 0, 0);
        let vb = merkle_tree_distribution::get_vault_balance();
        assert!(vb == 0, 0);
        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @supra_framework, admin = @0x1, alice = @0xA11CE)]
    #[expected_failure] // E_NOT_OWNER
    fun test_init_by_non_owner_fails(supra: &signer, admin: &signer,alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(alice);
        clean_up(burn_cap, mint_cap);
    }

    /***********************
     * update_root()
    ***********************/
    #[test(supra = @0x1, admin = @supra_framework, owner = @reward_distribution)]
    fun test_update_root_by_owner_succeeds(supra: &signer, admin: &signer, owner: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        let new_root = make_leaf(ALICE, 500);
        merkle_tree_distribution::update_root(owner, new_root);
        let got = merkle_tree_distribution::get_root_value();
        assert!(got == new_root, 0);
        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, alice = @0xA11CE)]
    #[expected_failure] // E_NOT_OWNER
    fun test_update_root_by_non_owner_fails(supra: &signer,owner: &signer, alice: &signer) {
        ensure_accounts();
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);
        let new_root = make_leaf(ALICE, 123);
        merkle_tree_distribution::update_root(alice, new_root);
    }

    /***********************
     * update_admin()
    ***********************/
    #[test(supra = @0x1, admin = @supra_framework, new_admin = @0xDEAD, owner = @reward_distribution)]
    fun test_update_admin_by_owner_succeeds(supra: &signer, admin: &signer, new_admin: &signer, owner: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);
        assert!(merkle_tree_distribution::get_admin_address() == signer::address_of(owner), 123);
        merkle_tree_distribution::update_admin(owner, signer::address_of(new_admin));
        assert!(merkle_tree_distribution::get_admin_address() == signer::address_of(new_admin), 123);

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, alice = @0xA11CE)]
    #[expected_failure(abort_code = 327681)] // E_NOT_OWNER
    fun test_update_admin_by_non_owner_fails(supra: &signer,owner: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(supra);

        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);
        merkle_tree_distribution::update_admin(alice, signer::address_of(alice));

        clean_up(burn_cap, mint_cap);
    }

    /***********************
     * deposit()
    ***********************/
    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework)]
    fun test_deposit_transfers_to_vault(supra: &signer,owner: &signer, admin: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);
        register(owner);

        mint_to(&mint_cap, signer::address_of(owner), 1_000);

        let owner_before = bal(signer::address_of(owner));
        let vault_before = merkle_tree_distribution::get_vault_balance();

        merkle_tree_distribution::deposit(owner, 800);

        let owner_after = bal(signer::address_of(owner));
        let vault_after = merkle_tree_distribution::get_vault_balance();

        assert!(owner_after == owner_before - 800, 0);
        assert!(vault_after == vault_before + 800, 0);

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, alice = @0xA11CE, owner = @reward_distribution, admin = @supra_framework)]
    fun test_deposit_by_non_owner_is_allowed(supra: &signer,alice: &signer, owner: &signer, admin: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(alice);

        mint_to(&mint_cap, signer::address_of(alice), 300);

        let alice_before = bal(signer::address_of(alice));
        let vault_before = merkle_tree_distribution::get_vault_balance();

        merkle_tree_distribution::deposit(alice, 200);

        assert!(bal(signer::address_of(alice)) == alice_before - 200, 0);
        assert!(merkle_tree_distribution::get_vault_balance() == vault_before + 200, 0);

        clean_up(burn_cap, mint_cap);
    }

    /***********************
     * withdraw()
    ***********************/
    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework)]
    fun test_withdraw_moves_owner_funds_to_vault(supra: &signer, owner: &signer, admin: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);

        merkle_tree_distribution::init(owner);

        register(owner);

        mint_to(&mint_cap, signer::address_of(owner), 500);

        merkle_tree_distribution::deposit(owner, 500);

        let owner_before = bal(signer::address_of(owner));
        let vault_before = merkle_tree_distribution::get_vault_balance();

        merkle_tree_distribution::withdraw(owner, 120);

        assert!(bal(signer::address_of(owner)) == owner_before + 120, 0);
        assert!(merkle_tree_distribution::get_vault_balance() == vault_before - 120, 0);

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, bob = @0xB0B, admin = @supra_framework)]
    #[expected_failure(abort_code = 327681)] // E_NOT_OWNER
    fun test_withdraw_by_non_owner_fails(supra: &signer,owner: &signer, bob: &signer, admin: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(bob);

        merkle_tree_distribution::withdraw(bob, 1);

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework)]
    #[expected_failure(abort_code = 65539)] // E_INSUFFICIENT_VAULT_FUNDS
    fun test_withdraw_owner_insufficient_balance_fails(supra: &signer,owner: &signer, admin: &signer) {
        ensure_accounts();
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);
        let (burn_cap, mint_cap) = init_supra(admin);
        register(owner);

        merkle_tree_distribution::withdraw(owner, 1);

        clean_up(burn_cap, mint_cap);
    }

    /***********************
     * claim_rewards()  - happy paths
    ***********************/

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    fun test_claim_single_happy(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        register(alice);


        mint_to(&mint_cap, signer::address_of(owner), 1_000);
        merkle_tree_distribution::deposit(owner, 800);


        let root = make_leaf(ALICE, 500);
        merkle_tree_distribution::update_root(owner, root);

        let alice_before = bal(ALICE);
        let vault_before = merkle_tree_distribution::get_vault_balance();

         assert!(merkle_tree_distribution::get_total_claimed() == 0, 123);

        merkle_tree_distribution::claim_rewards(alice, ALICE, 500, empty_proof());

        assert!(merkle_tree_distribution::get_total_claimed() == 500, 123);

        assert!(bal(ALICE) == alice_before + 500, 0);
        assert!(merkle_tree_distribution::get_vault_balance() == vault_before - 500, 0);
        assert!(merkle_tree_distribution::get_claimed_total(ALICE) == 500, 0);

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    fun test_claim_cumulative_delta(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(supra);
        account::create_account_for_test(signer::address_of(supra));
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        register(alice);

        mint_to(&mint_cap, signer::address_of(owner), 1_000);
        merkle_tree_distribution::deposit(owner, 1_000);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 100));
        merkle_tree_distribution::claim_rewards(alice, ALICE, 100, empty_proof());
        assert!(merkle_tree_distribution::get_claimed_total(ALICE) == 100, 0);

        let alice_before = bal(ALICE);
        let vault_before = merkle_tree_distribution::get_vault_balance();
        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 300));
        merkle_tree_distribution::claim_rewards(alice, ALICE, 300, empty_proof());

        assert!(bal(ALICE) == alice_before + 200, 0);
        assert!(merkle_tree_distribution::get_vault_balance() == vault_before - 200, 0);
        assert!(merkle_tree_distribution::get_claimed_total(ALICE) == 300, 0);

        clean_up(burn_cap, mint_cap);
    }


    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, bob = @0xB0B)]
    fun test_third_party_can_claim_for_user(supra: &signer, owner: &signer, admin: &signer, bob: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        account::create_account_for_test(ALICE);
        register(bob);
        coin::register<SupraCoin>(&account::create_signer_for_test(ALICE)); // register ALICE CoinStore

        mint_to(&mint_cap, signer::address_of(owner), 600);
        merkle_tree_distribution::deposit(owner, 600);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 400));

        let alice_before = bal(ALICE);
        let vault_before = merkle_tree_distribution::get_vault_balance();

        merkle_tree_distribution::claim_rewards(bob, ALICE, 400, empty_proof());

        assert!(bal(ALICE) == alice_before + 400, 0);
        assert!(merkle_tree_distribution::get_vault_balance() == vault_before - 400, 0);
        assert!(merkle_tree_distribution::get_claimed_total(ALICE) == 400, 0);

        clean_up(burn_cap, mint_cap);
    }

    /***********************
     * claim_rewards()  - error paths
    ***********************/

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    #[expected_failure(abort_code = 65540)] // E_INVALID_MERKLE_PROOF
    fun test_claim_invalid_proof_user_mismatch(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        register(alice);

        mint_to(&mint_cap, signer::address_of(owner), 1_000);
        merkle_tree_distribution::deposit(owner, 1_000);

        merkle_tree_distribution::update_root(owner, make_leaf(BOB, 500));

        merkle_tree_distribution::claim_rewards(alice, ALICE, 500, empty_proof());

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    #[expected_failure(abort_code = 196613)] // E_NOTHING_TO_CLAIM
    fun test_claim_again_same_cumulative_fails(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        register(alice);

        mint_to(&mint_cap, signer::address_of(owner), 1_000);
        merkle_tree_distribution::deposit(owner, 1_000);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 500));
        merkle_tree_distribution::claim_rewards(alice, ALICE, 500, empty_proof());

        merkle_tree_distribution::claim_rewards(alice, ALICE, 500, empty_proof());

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    #[expected_failure(abort_code = 196613)] // E_NOTHING_TO_CLAIM
    fun test_claim_with_lower_cumulative_than_claimed_fails(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        register(alice);

        mint_to(&mint_cap, signer::address_of(owner), 1_000);
        merkle_tree_distribution::deposit(owner, 1_000);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 200));
        merkle_tree_distribution::claim_rewards(alice, ALICE, 200, empty_proof());
        assert!(merkle_tree_distribution::get_claimed_total(ALICE) == 200, 0);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 150));
        merkle_tree_distribution::claim_rewards(alice, ALICE, 150, empty_proof());

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    #[expected_failure(abort_code = 196614)] // E_INSUFFICIENT_VAULT_FUNDS
    fun test_claim_insufficient_vault_funds(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        register(alice);

        mint_to(&mint_cap, signer::address_of(owner), 200);
        merkle_tree_distribution::deposit(owner, 200);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 1_000));

        merkle_tree_distribution::claim_rewards(alice, ALICE, 1_000, empty_proof());

        clean_up(burn_cap, mint_cap);
    }

    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    #[expected_failure(abort_code = 196613)] // second call hits E_NOTHING_TO_CLAIM
    fun test_two_half_attempts_without_root_bump_fails(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();

        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);
        register(owner);
        register(alice);
        mint_to(&mint_cap, signer::address_of(owner), 1_000);


        merkle_tree_distribution::deposit(owner, 1_000);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 50));

        merkle_tree_distribution::claim_rewards(alice, ALICE, 50, empty_proof());

        merkle_tree_distribution::claim_rewards(alice, ALICE, 50, empty_proof());

        clean_up(burn_cap, mint_cap);
    }

    /***********************
     * Views
    ***********************/
    #[test(supra = @0x1, owner = @reward_distribution, admin = @supra_framework, alice = @0xA11CE)]
    fun test_views_after_claim(supra: &signer,owner: &signer, admin: &signer, alice: &signer) {
        ensure_accounts();
        let (burn_cap, mint_cap) = init_supra(admin);
        coin::register<SupraCoin>(supra);
        merkle_tree_distribution::init(owner);

        register(owner);
        register(alice);

        mint_to(&mint_cap, signer::address_of(owner), 600);
        merkle_tree_distribution::deposit(owner, 600);

        merkle_tree_distribution::update_root(owner, make_leaf(ALICE, 250));
        merkle_tree_distribution::claim_rewards(alice, ALICE, 250, empty_proof());

        assert!(merkle_tree_distribution::get_claimed_total(ALICE) == 250, 0);
        let root_now = merkle_tree_distribution::get_root_value();
        assert!(root_now == make_leaf(ALICE, 250), 0);

        let view_bal = merkle_tree_distribution::get_vault_balance();

        assert!(view_bal == 600 - 250, 0);

        clean_up(burn_cap, mint_cap);
    }

    public fun clean_up(
      burn_cap : coin::BurnCapability<SupraCoin>,
      mint_cap : coin::MintCapability<SupraCoin>
    ) {
      coin::destroy_burn_cap(burn_cap); coin::destroy_mint_cap(mint_cap);
    }
}
