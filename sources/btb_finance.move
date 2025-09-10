/// BTB Finance - Sui Token with SUI Backing
/// 
/// A bonding curve token implementation where:
/// - Users send SUI to mint BTB tokens
/// - Users burn BTB tokens to receive SUI back
/// - Contract maintains SUI reserves as backing
/// - Price follows bonding curve: tokens = (sui * supply) / backing
/// - Fee structure: 0.1% total (0.05% to fee collector, 0.05% increases backing)

module btb_finance::btb_finance {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::event;
    use sui::url;
    use std::option;

    /// Minimum trade amount to prevent spam (1000 MIST = 0.000001 SUI)
    const MIN_TRADE: u64 = 1000;
    
    /// Fee rate denominator (0.1% = 1/1000)
    const FEE_RATE_DENOMINATOR: u64 = 1000;
    
    /// Half of fee rate (0.05% = 1/2000)
    const HALF_FEE_RATE_DENOMINATOR: u64 = 2000;
    
    /// Initial price: 1 SUI per BTB (in MIST units)
    const INITIAL_PRICE: u64 = 1_000_000_000;

    /// Error codes
    const E_INSUFFICIENT_TRADE_AMOUNT: u64 = 1;
    const E_INSUFFICIENT_BACKING: u64 = 2;
    const E_INSUFFICIENT_TOKENS_TO_MINT: u64 = 3;
    const E_INVALID_TOKEN_AMOUNT: u64 = 4;
    const E_PRICE_CANNOT_DECREASE: u64 = 5;
    const E_INVALID_FEE_COLLECTOR: u64 = 6;
    const E_NOT_AUTHORIZED: u64 = 7;

    /// The BTB token type (one-time witness)
    public struct BTB_FINANCE has drop {}

    /// Configuration and state for the BTB Finance protocol
    public struct TokenConfig has key {
        id: UID,
        /// Treasury capability for minting/burning BTB tokens
        treasury_cap: TreasuryCap<BTB_FINANCE>,
        /// SUI backing reserves
        backing_balance: Balance<SUI>,
        /// Contract authority (deployer)
        authority: address,
        /// Fee collector address
        fee_collector: address,
        /// Total fees collected
        total_fees_collected: u64,
        /// Last recorded price (for safety check)
        last_price: u64,
    }

    /// System information struct for queries
    public struct SystemInfo has copy, drop {
        total_supply: u64,
        total_backing: u64,
        current_price: u64,
        last_price: u64,
        fee_collector: address,
        total_fees_collected: u64,
    }

    /// Events
    public struct TokensMinted has copy, drop {
        user: address,
        sui_amount: u64,
        tokens_minted: u64,
        backing_added: u64,
        fee_collected: u64,
        new_price: u64,
    }

    public struct TokensBurned has copy, drop {
        user: address,
        tokens_burned: u64,
        sui_returned: u64,
        fee_collected: u64,
        new_price: u64,
    }

    public struct FeeCollectorUpdated has copy, drop {
        old_fee_collector: address,
        new_fee_collector: address,
        authority: address,
    }

    public struct AuthorityTransferred has copy, drop {
        old_authority: address,
        new_authority: address,
    }

    /// Module initializer - creates the BTB token and initial configuration
    fun init(witness: BTB_FINANCE, ctx: &mut TxContext) {
        // Create the treasury cap and coin metadata
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9, // decimals
            b"BTB",
            b"BTB Finance",
            b"Bonding curve token backed by SUI reserves",
            option::some(url::new_unsafe_from_bytes(b"https://raw.githubusercontent.com/btb-finance/BTBFrontend/refs/heads/main/public/images/btblogo.jpg")), // BTB logo
            ctx
        );

        // Share the coin metadata
        transfer::public_freeze_object(metadata);

        // Create initial configuration (will be initialized properly via init_config)
        let config = TokenConfig {
            id: object::new(ctx),
            treasury_cap,
            backing_balance: balance::zero(),
            authority: tx_context::sender(ctx), // Set deployer as authority
            fee_collector: @0x0, // Will be set in init_config
            total_fees_collected: 0,
            last_price: INITIAL_PRICE,
        };

        // Share the configuration object
        transfer::share_object(config);
    }

    /// Initialize the protocol configuration with fee collector
    public entry fun init_config(
        config: &mut TokenConfig,
        fee_collector: address,
        _ctx: &mut TxContext,
    ) {
        // Only allow initialization if fee collector is not set
        assert!(config.fee_collector == @0x0, E_INVALID_FEE_COLLECTOR);
        assert!(fee_collector != @0x0, E_INVALID_FEE_COLLECTOR);
        
        config.fee_collector = fee_collector;
    }

    /// Update the fee collector address (only callable by authority)
    public entry fun set_fee_collector(
        config: &mut TokenConfig,
        new_fee_collector: address,
        ctx: &TxContext,
    ) {
        assert!(config.authority == tx_context::sender(ctx), E_NOT_AUTHORIZED);
        assert!(new_fee_collector != @0x0, E_INVALID_FEE_COLLECTOR);
        
        let old_fee_collector = config.fee_collector;
        config.fee_collector = new_fee_collector;

        // Emit event for fee collector change
        event::emit(FeeCollectorUpdated {
            old_fee_collector,
            new_fee_collector,
            authority: tx_context::sender(ctx),
        });
    }

    /// Transfer authority to a new address (only callable by current authority)
    public entry fun transfer_authority(
        config: &mut TokenConfig,
        new_authority: address,
        ctx: &TxContext,
    ) {
        assert!(config.authority == tx_context::sender(ctx), E_NOT_AUTHORIZED);
        assert!(new_authority != @0x0, E_INVALID_FEE_COLLECTOR); // Reusing error code
        
        let old_authority = config.authority;
        config.authority = new_authority;

        // Emit event for authority transfer
        event::emit(AuthorityTransferred {
            old_authority,
            new_authority,
        });
    }

    /// Mint BTB tokens by sending SUI to the backing reserves
    /// Implements bonding curve pricing: tokens = (sui * supply) / backing
    /// Fee: 0.1% total (0.05% to fee collector, 0.05% increases backing)
    public entry fun mint_with_backing(
        config: &mut TokenConfig,
        mut payment: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let sui_amount = coin::value(&payment);
        assert!(sui_amount >= MIN_TRADE, E_INSUFFICIENT_TRADE_AMOUNT);
        
        let current_supply = coin::total_supply(&config.treasury_cap);
        let backing_balance_amount = balance::value(&config.backing_balance);
        
        // Calculate fee structure: 0.1% total
        let fee_to_collector = sui_amount / HALF_FEE_RATE_DENOMINATOR; // 0.05%
        let fee_to_backing = sui_amount / HALF_FEE_RATE_DENOMINATOR; // 0.05%
        let net_sui_for_tokens = sui_amount - fee_to_collector - fee_to_backing;
        
        // Calculate tokens using bonding curve
        let tokens_to_mint = if (current_supply == 0) {
            // Initial mint: 1000 BTB per SUI (using net amount)
            net_sui_for_tokens * 1000
        } else {
            // Bonding curve: tokens = (net_sui * total_supply) / current_backing
            assert!(backing_balance_amount > 0, E_INSUFFICIENT_BACKING);
            ((net_sui_for_tokens as u128) * (current_supply as u128) / (backing_balance_amount as u128) as u64)
        };
        
        assert!(tokens_to_mint > 0, E_INSUFFICIENT_TOKENS_TO_MINT);

        // Split payment for fees and backing
        let fee_coin = coin::split(&mut payment, fee_to_collector, ctx);
        let backing_fee_coin = coin::split(&mut payment, fee_to_backing, ctx);
        
        // Add net SUI + backing fee to reserves
        let payment_balance = coin::into_balance(payment);
        let backing_fee_balance = coin::into_balance(backing_fee_coin);
        balance::join(&mut config.backing_balance, payment_balance);
        balance::join(&mut config.backing_balance, backing_fee_balance);
        
        // Send fee to collector
        transfer::public_transfer(fee_coin, config.fee_collector);
        
        // Mint BTB tokens to user
        let btb_tokens = coin::mint(&mut config.treasury_cap, tokens_to_mint, ctx);
        let user = tx_context::sender(ctx);
        
        // Update state and perform safety check
        config.total_fees_collected = config.total_fees_collected + fee_to_collector;
        let new_backing = backing_balance_amount + net_sui_for_tokens + fee_to_backing;
        let new_supply = current_supply + tokens_to_mint;
        
        // Calculate new price and perform safety check
        let new_price = if (new_supply > 0) {
            (new_backing * INITIAL_PRICE) / new_supply
        } else {
            INITIAL_PRICE
        };
        
        // Only enforce price increase after first transaction
        if (current_supply > 0) {
            assert!(config.last_price <= new_price, E_PRICE_CANNOT_DECREASE);
        };
        config.last_price = new_price;

        // Emit event
        event::emit(TokensMinted {
            user,
            sui_amount,
            tokens_minted: tokens_to_mint,
            backing_added: net_sui_for_tokens + fee_to_backing,
            fee_collected: fee_to_collector,
            new_price,
        });

        // Transfer BTB tokens to user
        transfer::public_transfer(btb_tokens, user);
    }

    /// Burn BTB tokens to receive SUI from backing reserves
    /// Implements bonding curve: sui = (tokens * backing) / supply
    /// Fee: 0.1% total (0.05% to fee collector, 0.05% stays in backing)
    public entry fun burn_for_backing(
        config: &mut TokenConfig,
        btb_tokens: Coin<BTB_FINANCE>,
        ctx: &mut TxContext,
    ) {
        let token_amount = coin::value(&btb_tokens);
        assert!(token_amount > 0, E_INVALID_TOKEN_AMOUNT);
        
        let current_supply = coin::total_supply(&config.treasury_cap);
        let backing_balance_amount = balance::value(&config.backing_balance);
        
        assert!(current_supply > 0 && backing_balance_amount > 0, E_INSUFFICIENT_BACKING);
        
        // Calculate SUI to return using bonding curve
        let sui_to_return = ((token_amount as u128) * (backing_balance_amount as u128) / (current_supply as u128) as u64);
        assert!(sui_to_return >= MIN_TRADE, E_INSUFFICIENT_TRADE_AMOUNT);
        
        // Calculate fee structure: 0.1% total
        let fee_to_collector = sui_to_return / HALF_FEE_RATE_DENOMINATOR; // 0.05%
        let fee_stays_in_backing = sui_to_return / HALF_FEE_RATE_DENOMINATOR; // 0.05%
        let user_amount = sui_to_return - fee_to_collector - fee_stays_in_backing;

        // Burn BTB tokens
        coin::burn(&mut config.treasury_cap, btb_tokens);
        
        // Take SUI from backing for user and fee collector
        let user_balance = balance::split(&mut config.backing_balance, user_amount);
        let fee_balance = balance::split(&mut config.backing_balance, fee_to_collector);
        
        // Convert to coins and transfer
        let user_coin = coin::from_balance(user_balance, ctx);
        let fee_coin = coin::from_balance(fee_balance, ctx);
        
        let user = tx_context::sender(ctx);
        transfer::public_transfer(user_coin, user);
        transfer::public_transfer(fee_coin, config.fee_collector);
        
        // Update state and perform safety check
        config.total_fees_collected = config.total_fees_collected + fee_to_collector;
        let new_backing = backing_balance_amount - user_amount - fee_to_collector; // fee_stays_in_backing remains
        let new_supply = current_supply - token_amount;
        
        // Calculate new price and perform safety check
        let new_price = if (new_supply > 0) {
            (new_backing * INITIAL_PRICE) / new_supply
        } else {
            INITIAL_PRICE
        };
        
        // Only enforce price increase if there are remaining tokens
        if (new_supply > 0) {
            assert!(config.last_price <= new_price, E_PRICE_CANNOT_DECREASE);
        };
        config.last_price = new_price;

        // Emit event
        event::emit(TokensBurned {
            user,
            tokens_burned: token_amount,
            sui_returned: user_amount,
            fee_collected: fee_to_collector,
            new_price,
        });
    }

    /// Get current system information including price, supply, and backing
    public fun get_system_info(config: &TokenConfig): SystemInfo {
        let total_supply = coin::total_supply(&config.treasury_cap);
        let total_backing = balance::value(&config.backing_balance);
        
        let current_price = if (total_supply > 0) {
            (total_backing * INITIAL_PRICE) / total_supply
        } else {
            INITIAL_PRICE
        };

        SystemInfo {
            total_supply,
            total_backing,
            current_price,
            last_price: config.last_price,
            fee_collector: config.fee_collector,
            total_fees_collected: config.total_fees_collected,
        }
    }

    /// Public accessor for total supply
    public fun total_supply(config: &TokenConfig): u64 {
        coin::total_supply(&config.treasury_cap)
    }

    /// Public accessor for total backing
    public fun total_backing(config: &TokenConfig): u64 {
        balance::value(&config.backing_balance)
    }

    /// Public accessor for current price
    public fun current_price(config: &TokenConfig): u64 {
        let total_supply = coin::total_supply(&config.treasury_cap);
        let total_backing = balance::value(&config.backing_balance);
        
        if (total_supply > 0) {
            (total_backing * INITIAL_PRICE) / total_supply
        } else {
            INITIAL_PRICE
        }
    }

    /// Public accessor for fee collector
    public fun fee_collector(config: &TokenConfig): address {
        config.fee_collector
    }

    /// Public accessor for total fees collected
    public fun total_fees_collected(config: &TokenConfig): u64 {
        config.total_fees_collected
    }

    /// Public accessor for contract authority
    public fun authority(config: &TokenConfig): address {
        config.authority
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(BTB_FINANCE {}, ctx)
    }
}