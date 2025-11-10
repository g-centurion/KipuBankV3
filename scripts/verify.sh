#!/bin/bash

# KipuBankV3 Contract Verification Script for Etherscan
# This script verifies the contract on Etherscan/Blockscout after deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NETWORK="${1:-sepolia}"
CONTRACT_ADDRESS="${2}"
ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY}"
BLOCK_EXPLORER_URL=""

# Validate inputs
if [ -z "$CONTRACT_ADDRESS" ]; then
    echo -e "${RED}Error: Contract address required${NC}"
    echo "Usage: ./verify.sh [network] [contract_address]"
    echo "Example: ./verify.sh sepolia 0x..."
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo -e "${RED}Error: ETHERSCAN_API_KEY environment variable not set${NC}"
    exit 1
fi

# Set block explorer URL based on network
case $NETWORK in
    sepolia)
        BLOCK_EXPLORER_URL="https://sepolia.etherscan.io/api"
        SCAN_URL="https://sepolia.etherscan.io"
        CHAIN_ID="11155111"
        ;;
    mainnet)
        BLOCK_EXPLORER_URL="https://api.etherscan.io"
        SCAN_URL="https://etherscan.io"
        CHAIN_ID="1"
        ;;
    *)
        echo -e "${RED}Error: Unknown network '$NETWORK'${NC}"
        exit 1
        ;;
esac

echo -e "${YELLOW}Verifying contract on $NETWORK...${NC}"
echo "Contract Address: $CONTRACT_ADDRESS"
echo "Block Explorer: $SCAN_URL"

# Flatten the contract
echo -e "${YELLOW}Step 1: Flattening contract...${NC}"
forge flatten src/KipuBankV3_TP4.sol > KipuBankV3_Flat.sol

# Extract constructor arguments
echo -e "${YELLOW}Step 2: Extracting constructor arguments...${NC}"
# Note: You need to fill in your actual constructor arguments
CONSTRUCTOR_ARGS="0x694AA1769357215DE4FAC081bf1f309adC325306000000000000000000000000000000000000000000000000056bc75e2d6310000000000000000000000000000ee567fe1712faf6149d80da1e6934e354b40a0540000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c7238"

# Verify on block explorer
echo -e "${YELLOW}Step 3: Submitting verification to Etherscan...${NC}"

curl -X POST "$BLOCK_EXPLORER_URL" \
    -d "apikey=$ETHERSCAN_API_KEY" \
    -d "module=contract" \
    -d "action=verifysourcecode" \
    -d "contractaddress=$CONTRACT_ADDRESS" \
    -d "sourceCode=$(cat KipuBankV3_Flat.sol | jq -Rs .)" \
    -d "codeformat=solidity-single-file" \
    -d "contractname=KipuBankV3" \
    -d "compilerversion=v0.8.30+commit.c0eba766" \
    -d "optimizationUsed=1" \
    -d "runs=200" \
    -d "constructorArguements=$CONSTRUCTOR_ARGS" \
    -d "licenseType=3" \
    > verification_response.json

echo -e "${GREEN}Verification submitted!${NC}"
echo ""

# Display response
echo "Response:"
cat verification_response.json | jq .

# Extract verification status
STATUS=$(cat verification_response.json | jq -r '.status')
MESSAGE=$(cat verification_response.json | jq -r '.message')

if [ "$STATUS" == "1" ]; then
    GUID=$(cat verification_response.json | jq -r '.result')
    echo -e "${GREEN}✓ Verification submitted successfully!${NC}"
    echo "GUID: $GUID"
    echo ""
    echo "Check verification status at:"
    echo "$SCAN_URL/address/$CONTRACT_ADDRESS#code"
    
    # Cleanup
    rm KipuBankV3_Flat.sol
else
    echo -e "${RED}✗ Verification failed${NC}"
    echo "Message: $MESSAGE"
    exit 1
fi

echo ""
echo -e "${GREEN}Done!${NC}"
