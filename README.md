# BTB Finance - Sui Implementation

A bonding curve token implementation on Sui where users can mint BTB tokens by depositing SUI and burn BTB tokens to receive SUI back. The contract maintains SUI reserves as backing for the tokens.

## Features

- **Bonding Curve Pricing**: Token price follows the formula `tokens = (sui * supply) / backing`
- **SUI Backing**: All BTB tokens are backed by SUI reserves held by the contract
- **Fee Structure**: 0.1% total fee (0.05% to fee collector, 0.05% increases backing)
- **Price Safety**: Enforces that token price can only increase (anti-manipulation)
- **Real-time Queries**: Get current price, supply, and backing information

## Core Mechanics

### Minting (Buy BTB with SUI)
```
tokens_to_mint = (net_sui * current_supply) / current_backing
```
- Users send SUI to mint BTB tokens
- 0.05% fee goes to fee collector
- 0.05% fee stays in backing (increases reserves)
- Remaining SUI goes to backing reserves

### Burning (Sell BTB for SUI)
```
sui_to_return = (tokens * current_backing) / current_supply
```
- Users burn BTB tokens to receive SUI
- 0.05% fee goes to fee collector  
- 0.05% fee stays in backing reserves
- User receives remaining SUI

## Project Structure

```
├── sources/
│   └── btb_finance.move       # Main contract implementation
├── tests/
│   └── btb_finance_tests.move # Comprehensive test suite
├── scripts/
│   ├── deploy.sh              # Deployment script
│   └── test.sh                # Testing script
├── Move.toml                  # Package manifest
└── README.md                  # This file
```

## Setup and Installation

### Prerequisites
- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install)
- Git

### Installation
```bash
# Clone the repository
git clone <your-repo-url>
cd btb_finance

# Install Sui CLI (if not already installed)
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch mainnet sui
```

## Building and Testing

### Run Tests
```bash
# Run the test script
./scripts/test.sh

# Or run tests directly
sui move test
```

### Build Package
```bash
sui move build
```

## Deployment

### Deploy to Testnet
```bash
# Make sure you have a Sui wallet configured for testnet
sui client switch --env testnet

# Run deployment script
./scripts/deploy.sh
```

### Initialize Configuration
After deployment, initialize the configuration with a fee collector address:
```bash
sui client call \
  --function init_config \
  --module btb_finance \
  --package <PACKAGE_ID> \
  --args <CONFIG_OBJECT_ID> <FEE_COLLECTOR_ADDRESS>
```

## Usage Examples

### Mint BTB Tokens
```bash
# Mint BTB tokens by sending 1 SUI (1,000,000,000 MIST)
sui client call \
  --function mint_with_backing \
  --module btb_finance \
  --package <PACKAGE_ID> \
  --args <CONFIG_OBJECT_ID> \
  --coin <SUI_COIN_ID> \
  --gas-budget 10000000
```

### Burn BTB Tokens
```bash
# Burn BTB tokens to receive SUI back
sui client call \
  --function burn_for_backing \
  --module btb_finance \
  --package <PACKAGE_ID> \
  --args <CONFIG_OBJECT_ID> <BTB_COIN_ID> \
  --gas-budget 10000000
```

### Query System Information
```bash
# Get current system state (price, supply, backing)
sui client call \
  --function get_system_info \
  --module btb_finance \
  --package <PACKAGE_ID> \
  --args <CONFIG_OBJECT_ID>
```

## Smart Contract Functions

### Entry Functions (for users)
- `init_config(config, fee_collector)` - Initialize protocol configuration
- `mint_with_backing(config, payment)` - Mint BTB tokens with SUI
- `burn_for_backing(config, btb_tokens)` - Burn BTB tokens for SUI

### View Functions (for queries)
- `get_system_info(config)` - Get complete system information
- `total_supply(config)` - Get total BTB token supply
- `total_backing(config)` - Get total SUI backing amount
- `current_price(config)` - Get current token price
- `fee_collector(config)` - Get fee collector address
- `total_fees_collected(config)` - Get total fees collected

## Key Differences from Solana Version

1. **Token Management**: Uses Sui's `Coin<T>` and `TreasuryCap<T>` instead of SPL tokens
2. **State Storage**: Uses shared objects instead of PDAs
3. **Native Currency**: Uses SUI instead of SOL
4. **Entry Functions**: Direct function calls instead of instruction-based architecture
5. **Error Handling**: Move's built-in assertion system instead of custom error codes

## Security Features

- **Minimum Trade Amount**: Prevents spam with 1000 MIST minimum
- **Price Safety Check**: Ensures price can only increase
- **Input Validation**: Comprehensive validation of all inputs
- **Overflow Protection**: Safe arithmetic operations
- **Access Control**: Proper permission checks for administrative functions

## Fee Structure

| Action | Total Fee | Fee Collector | Backing Increase |
|--------|-----------|---------------|------------------|
| Mint   | 0.1%      | 0.05%         | 0.05%           |
| Burn   | 0.1%      | 0.05%         | 0.05%           |

## Events

The contract emits the following events:

- `TokensMinted` - When BTB tokens are minted
- `TokensBurned` - When BTB tokens are burned

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]