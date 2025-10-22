#!/bin/bash

# GoalPledgeEscrow Deployment Script
# This script deploys the updated contract with Community Challenges feature

echo "🚀 Deploying GoalPledgeEscrow with Community Challenges..."
echo ""

# Check if private key is provided
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY environment variable is not set"
    echo ""
    echo "Please set your private key:"
    echo "export PRIVATE_KEY=your_private_key_here"
    echo ""
    echo "Then run this script again: ./deploy.sh"
    exit 1
fi

# Configuration
export TREASURY_ADDRESS=0x712774a5db28c895B5877105ca81eAeCF01884CB
export MIN_DEADLINE_BUFFER=3600
export USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b1566469c3d

echo "📋 Deployment Configuration:"
echo "  Network: Base Mainnet"
echo "  USDC Address: $USDC_ADDRESS"
echo "  Treasury Address: $TREASURY_ADDRESS"
echo "  Min Deadline Buffer: $MIN_DEADLINE_BUFFER seconds (1 hour)"
echo ""

# Build the contract first
echo "🔨 Building contract..."
forge build

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""

# Deploy the contract
echo "🚀 Deploying to Base Mainnet..."
forge script script/Deploy.s.sol:Deploy \
    --rpc-url https://mainnet.base.org \
    --broadcast \
    --verify \
    --private-key $PRIVATE_KEY

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Deployment successful!"
    echo ""
    echo "📝 Next steps:"
    echo "1. Update the frontend ABI file with the new contract functions"
    echo "2. Update the contract address in your frontend configuration"
    echo "3. Test the new Community Challenges features"
    echo ""
    echo "🔗 Check your deployment on BaseScan:"
    echo "https://basescan.io/"
else
    echo ""
    echo "❌ Deployment failed!"
    echo "Please check the error messages above and try again."
fi
