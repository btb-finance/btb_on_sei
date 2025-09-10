#[test_only]
module btb_finance::btb_finance_tests {
    use sui::test_scenario;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use btb_finance::btb_finance::{Self, TokenConfig, BTB_FINANCE};

    const ADMIN: address = @0xABCD;
    const FEE_COLLECTOR: address = @0xFEE;
    const USER1: address = @0x1111;
    const USER2: address = @0x2222;

    #[test]
    fun test_initialization() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the module (this would normally happen automatically)
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            btb_finance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // Initialize configuration
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            btb_finance::init_config(&mut config, FEE_COLLECTOR, test_scenario::ctx(&mut scenario));
            
            // Verify fee collector is set
            assert!(btb_finance::fee_collector(&config) == FEE_COLLECTOR, 0);
            assert!(btb_finance::total_supply(&config) == 0, 1);
            assert!(btb_finance::total_backing(&config) == 0, 2);
            
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_mint_initial_tokens() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            btb_finance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            btb_finance::init_config(&mut config, FEE_COLLECTOR, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(config);
        };

        // User mints tokens
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)); // 1 SUI
            
            btb_finance::mint_with_backing(&mut config, payment, test_scenario::ctx(&mut scenario));
            
            // Check that supply increased and backing is added
            assert!(btb_finance::total_supply(&config) > 0, 0);
            assert!(btb_finance::total_backing(&config) > 0, 1);
            
            test_scenario::return_shared(config);
        };

        // Check user received BTB tokens
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let btb_coin = test_scenario::take_from_sender<Coin<BTB_FINANCE>>(&scenario);
            assert!(coin::value(&btb_coin) > 0, 2);
            test_scenario::return_to_sender(&scenario, btb_coin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_burn_tokens() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            btb_finance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            btb_finance::init_config(&mut config, FEE_COLLECTOR, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(config);
        };

        // User mints tokens first
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));
            btb_finance::mint_with_backing(&mut config, payment, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(config);
        };

        // User burns half the tokens
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            let mut btb_coin = test_scenario::take_from_sender<Coin<BTB_FINANCE>>(&scenario);
            let initial_value = coin::value(&btb_coin);
            
            let burn_amount = initial_value / 2;
            let burn_coin = coin::split(&mut btb_coin, burn_amount, test_scenario::ctx(&mut scenario));
            
            btb_finance::burn_for_backing(&mut config, burn_coin, test_scenario::ctx(&mut scenario));
            
            test_scenario::return_to_sender(&scenario, btb_coin);
            test_scenario::return_shared(config);
        };

        // Check user received SUI back
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let sui_coins = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&sui_coins) > 0, 0);
            test_scenario::return_to_sender(&scenario, sui_coins);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_bonding_curve_price_increase() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            btb_finance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            btb_finance::init_config(&mut config, FEE_COLLECTOR, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(config);
        };

        let mut previous_price = 0;

        // First mint
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));
            btb_finance::mint_with_backing(&mut config, payment, test_scenario::ctx(&mut scenario));
            previous_price = btb_finance::current_price(&config);
            test_scenario::return_shared(config);
        };

        // Second mint should increase price
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));
            btb_finance::mint_with_backing(&mut config, payment, test_scenario::ctx(&mut scenario));
            
            let new_price = btb_finance::current_price(&config);
            assert!(new_price >= previous_price, 0); // Price should not decrease
            
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fee_collection() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            btb_finance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            btb_finance::init_config(&mut config, FEE_COLLECTOR, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(config);
        };

        // User mints tokens
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut config = test_scenario::take_shared<TokenConfig>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario)); // 1 SUI
            
            btb_finance::mint_with_backing(&mut config, payment, test_scenario::ctx(&mut scenario));
            
            // Check that fees were collected
            assert!(btb_finance::total_fees_collected(&config) > 0, 0);
            
            test_scenario::return_shared(config);
        };

        // Check fee collector received SUI
        test_scenario::next_tx(&mut scenario, FEE_COLLECTOR);
        {
            let fee_coins = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&fee_coins) > 0, 1);
            test_scenario::return_to_sender(&scenario, fee_coins);
        };

        test_scenario::end(scenario);
    }
}