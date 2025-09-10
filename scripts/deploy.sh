#!/bin/bash

# BTB Finance Deployment Script for Sui
# This script builds and deploys the BTB Finance bonding curve token

set -e

echo "🚀 Starting BTB Finance deployment on Sui..."

# Build the Move package
echo "📦 Building Move package..."
sui move build

# Deploy to devnet
echo "🌐 Deploying to Sui devnet..."
DEPLOY_RESULT=$(sui client publish --gas-budget 100000000 --json)

# Extract package ID from deployment result
PACKAGE_ID=$(echo $DEPLOY_RESULT | jq -r '.objectChanges[] | select(.type == "published") | .packageId')
echo "📋 Package deployed with ID: $PACKAGE_ID"

# Extract TokenConfig object ID
CONFIG_ID=$(echo $DEPLOY_RESULT | jq -r '.objectChanges[] | select(.objectType | contains("TokenConfig")) | .objectId')
echo "⚙️  TokenConfig object ID: $CONFIG_ID"

# Save deployment info
cat > deployment.json << EOF
{
  "packageId": "$PACKAGE_ID",
  "configId": "$CONFIG_ID",
  "network": "devnet",
  "deployedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "✅ Deployment complete! Configuration saved to deployment.json"
echo ""
echo "Next steps:"
echo "1. Initialize the configuration: sui client call --function init_config --module btb_finance --package $PACKAGE_ID --args $CONFIG_ID [FEE_COLLECTOR_ADDRESS]"
echo "2. Users can now mint BTB tokens: sui client call --function mint_with_backing --module btb_finance --package $PACKAGE_ID"
echo ""
echo "📊 Package ID: $PACKAGE_ID"
echo "📊 Config ID: $CONFIG_ID"