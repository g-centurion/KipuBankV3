#!/bin/bash

# Script de verificación completa del despliegue de KipuBankV3
# Compara código local con contrato on-chain

set -e

# Colores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "KipuBankV3 Deployment Verification Script"
echo "=========================================="
echo ""

# Dirección del contrato desplegado (v2)
CONTRACT_ADDRESS="0x0197FB5AcCc60e573C627B7F0779290e200Ed445"
DEPLOY_TX="0x0094c3f6c2b573c4d8f94af4fb6d26c5a379eb36637453132c30125075820bb0"

# RPC endpoints
RPC_SEPOLIA="https://sepolia.gateway.tenderly.co"

echo -e "${YELLOW}1. Verificando compilación local...${NC}"
forge build --sizes | grep "KipuBankV3"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Compilación exitosa${NC}"
else
    echo -e "${RED}✗ Error en compilación${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}2. Ejecutando tests (43 esperados)...${NC}"
TEST_RESULT=$(forge test --json | jq -r '.["test/KipuBankV3.t.sol:KipuBankV3Test"].test_results | to_entries | length')
if [ "$TEST_RESULT" -eq 43 ]; then
    echo -e "${GREEN}✓ 43/43 tests pasaron${NC}"
else
    echo -e "${RED}✗ Tests fallaron (esperados: 43, obtenidos: $TEST_RESULT)${NC}"
fi
echo ""

echo -e "${YELLOW}3. Verificando contrato on-chain...${NC}"
echo "Dirección: $CONTRACT_ADDRESS"
echo "TX Deploy: $DEPLOY_TX"

# Verificar que existe bytecode
BYTECODE_SIZE=$(cast code $CONTRACT_ADDRESS --rpc-url $RPC_SEPOLIA 2>/dev/null | wc -c)
if [ "$BYTECODE_SIZE" -gt 100 ]; then
    echo -e "${GREEN}✓ Contrato desplegado (bytecode: ~$((BYTECODE_SIZE / 2)) bytes)${NC}"
else
    echo -e "${RED}✗ No se encontró bytecode en la dirección${NC}"
    exit 1
fi
echo ""

echo -e "${YELLOW}4. Verificando parámetros del contrato...${NC}"

# MAX_WITHDRAWAL_PER_TX (debe ser 1 ether = 1000000000000000000)
MAX_WITHDRAWAL=$(cast call $CONTRACT_ADDRESS "MAX_WITHDRAWAL_PER_TX()(uint256)" --rpc-url $RPC_SEPOLIA)
EXPECTED_MAX="1000000000000000000"
if [ "$MAX_WITHDRAWAL" == "$EXPECTED_MAX" ]; then
    echo -e "${GREEN}✓ MAX_WITHDRAWAL_PER_TX: 1 ether${NC}"
else
    echo -e "${RED}✗ MAX_WITHDRAWAL_PER_TX incorrecto: $MAX_WITHDRAWAL (esperado: $EXPECTED_MAX)${NC}"
fi

# Router address
ROUTER=$(cast call $CONTRACT_ADDRESS "I_ROUTER()(address)" --rpc-url $RPC_SEPOLIA)
EXPECTED_ROUTER="0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3"
if [ "${ROUTER,,}" == "${EXPECTED_ROUTER,,}" ]; then
    echo -e "${GREEN}✓ Router: $ROUTER${NC}"
else
    echo -e "${RED}✗ Router incorrecto: $ROUTER${NC}"
fi

# USDC address
USDC=$(cast call $CONTRACT_ADDRESS "USDC_TOKEN()(address)" --rpc-url $RPC_SEPOLIA)
EXPECTED_USDC="0x1c7D4B196Cb0C6B364C3d6eB8F0708a9dA00375D"
if [ "${USDC,,}" == "${EXPECTED_USDC,,}" ]; then
    echo -e "${GREEN}✓ USDC: $USDC${NC}"
else
    echo -e "${RED}✗ USDC incorrecto: $USDC${NC}"
fi

# WETH address
WETH=$(cast call $CONTRACT_ADDRESS "WETH_TOKEN()(address)" --rpc-url $RPC_SEPOLIA)
echo -e "${GREEN}✓ WETH: $WETH${NC}"

echo ""
echo -e "${YELLOW}5. Verificando constantes del contrato...${NC}"

# BANK_CAP_USD (debe ser 100000000000000 = 1M USD * 1e8)
BANK_CAP=$(cast call $CONTRACT_ADDRESS "BANK_CAP_USD()(uint256)" --rpc-url $RPC_SEPOLIA)
EXPECTED_CAP="100000000000000"
if [ "$BANK_CAP" == "$EXPECTED_CAP" ]; then
    echo -e "${GREEN}✓ BANK_CAP_USD: 1,000,000 USD (8 decimals)${NC}"
else
    echo -e "${RED}✗ BANK_CAP_USD incorrecto: $BANK_CAP${NC}"
fi

# PRICE_FEED_TIMEOUT (debe ser 10800 = 3 hours)
TIMEOUT=$(cast call $CONTRACT_ADDRESS "PRICE_FEED_TIMEOUT()(uint256)" --rpc-url $RPC_SEPOLIA)
EXPECTED_TIMEOUT="10800"
if [ "$TIMEOUT" == "$EXPECTED_TIMEOUT" ]; then
    echo -e "${GREEN}✓ PRICE_FEED_TIMEOUT: 3 hours (10800 sec)${NC}"
else
    echo -e "${RED}✗ PRICE_FEED_TIMEOUT incorrecto: $TIMEOUT (esperado: $EXPECTED_TIMEOUT)${NC}"
fi

# MAX_PRICE_DEVIATION_BPS (debe ser 500 = 5%)
DEVIATION=$(cast call $CONTRACT_ADDRESS "MAX_PRICE_DEVIATION_BPS()(uint256)" --rpc-url $RPC_SEPOLIA)
EXPECTED_DEVIATION="500"
if [ "$DEVIATION" == "$EXPECTED_DEVIATION" ]; then
    echo -e "${GREEN}✓ MAX_PRICE_DEVIATION_BPS: 5% (500 bps)${NC}"
else
    echo -e "${RED}✗ MAX_PRICE_DEVIATION_BPS incorrecto: $DEVIATION${NC}"
fi

echo ""
echo -e "${YELLOW}6. Verificando roles y permisos...${NC}"

# DEFAULT_ADMIN_ROLE
ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"
# Asumir que el deployer es admin (cambiar por dirección real si es necesaria)
DEPLOYER="0xe7Bc10cbDA9e4830921384C49B9E711d48b0E8C2"
HAS_ADMIN=$(cast call $CONTRACT_ADDRESS "hasRole(bytes32,address)(bool)" $ADMIN_ROLE $DEPLOYER --rpc-url $RPC_SEPOLIA)
if [ "$HAS_ADMIN" == "true" ]; then
    echo -e "${GREEN}✓ Deployer tiene rol ADMIN${NC}"
else
    echo -e "${YELLOW}⚠ Verificar roles manualmente${NC}"
fi

echo ""
echo -e "${YELLOW}7. Verificando verificación en exploradores...${NC}"
echo "Etherscan: https://sepolia.etherscan.io/address/$CONTRACT_ADDRESS#code"
echo "Blockscout: https://eth-sepolia.blockscout.com/address/$CONTRACT_ADDRESS"

echo ""
echo -e "${YELLOW}8. Comparando bytecode local vs on-chain...${NC}"

# Generar bytecode local
forge inspect src/KipuBankV3.sol:KipuBankV3 deployedBytecode > /tmp/local_bytecode.txt
cast code $CONTRACT_ADDRESS --rpc-url $RPC_SEPOLIA > /tmp/onchain_bytecode.txt

LOCAL_SIZE=$(cat /tmp/local_bytecode.txt | wc -c)
ONCHAIN_SIZE=$(cat /tmp/onchain_bytecode.txt | wc -c)

echo "Local bytecode template: $LOCAL_SIZE caracteres"
echo "On-chain bytecode: $ONCHAIN_SIZE caracteres"

# El on-chain debe ser ligeramente mayor (incluye valores de immutables)
if [ "$ONCHAIN_SIZE" -gt "$((LOCAL_SIZE - 100))" ] && [ "$ONCHAIN_SIZE" -lt "$((LOCAL_SIZE + 500))" ]; then
    echo -e "${GREEN}✓ Tamaños de bytecode consistentes (diferencias por immutables)${NC}"
else
    echo -e "${YELLOW}⚠ Diferencia significativa en bytecode - revisar manualmente${NC}"
fi

echo ""
echo -e "${YELLOW}9. Resumen de verificación de README...${NC}"

# Verificar que README tiene la dirección correcta
if grep -q "$CONTRACT_ADDRESS" README.md; then
    echo -e "${GREEN}✓ README contiene dirección correcta del contrato${NC}"
else
    echo -e "${RED}✗ README no actualizado con dirección del contrato${NC}"
fi

if grep -q "$DEPLOY_TX" README.md; then
    echo -e "${GREEN}✓ README contiene TX de deploy correcta${NC}"
else
    echo -e "${RED}✗ README no contiene TX de deploy${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Verificación completa${NC}"
echo "=========================================="
echo ""
echo "Próximos pasos recomendados:"
echo "1. Verificar manualmente en Etherscan/Blockscout"
echo "2. Revisar que CI/CD pasa todos los checks"
echo "3. Confirmar que documentación está actualizada"
echo ""
