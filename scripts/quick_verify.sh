#!/bin/bash
# Quick verification script

CONTRACT="0x0197FB5AcCc60e573C627B7F0779290e200Ed445"
RPC="https://sepolia.gateway.tenderly.co"
CAST="/home/sonic/.foundry/bin/cast"

echo "=== KipuBankV3 Quick Verification ==="
echo ""
echo "Contract: $CONTRACT"
echo ""

echo "1. MAX_WITHDRAWAL_PER_TX:"
$CAST call $CONTRACT 'MAX_WITHDRAWAL_PER_TX()(uint256)' --rpc-url $RPC
echo "(Expected: 1000000000000000000 = 1 ether)"
echo ""

echo "2. PRICE_FEED_TIMEOUT:"
$CAST call $CONTRACT 'PRICE_FEED_TIMEOUT()(uint256)' --rpc-url $RPC
echo "(Expected: 10800 = 3 hours)"
echo ""

echo "3. BANK_CAP_USD:"
$CAST call $CONTRACT 'BANK_CAP_USD()(uint256)' --rpc-url $RPC
echo "(Expected: 100000000000000 = 1M USD * 1e8)"
echo ""

echo "4. MAX_PRICE_DEVIATION_BPS:"
$CAST call $CONTRACT 'MAX_PRICE_DEVIATION_BPS()(uint256)' --rpc-url $RPC
echo "(Expected: 500 = 5%)"
echo ""

echo "5. I_ROUTER:"
$CAST call $CONTRACT 'I_ROUTER()(address)' --rpc-url $RPC
echo "(Expected: 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3)"
echo ""

echo "6. USDC_TOKEN:"
$CAST call $CONTRACT 'USDC_TOKEN()(address)' --rpc-url $RPC
echo "(Expected: 0x1c7D4B196Cb0C6B364C3d6eB8F0708a9dA00375D)"
echo ""

echo "7. WETH_TOKEN:"
$CAST call $CONTRACT 'WETH_TOKEN()(address)' --rpc-url $RPC
echo ""

echo "=== Verification Complete ==="
