# 🚀 Guía de Despliegue - KipuBankV3

## 📋 Pre-requisitos

- Foundry instalado (`forge`, `cast`)
- Cuenta con fondos en Sepolia testnet
- RPC URL (recomendado: Alchemy o Infura)
- API Key de Etherscan para verificación (opcional)

## 🔧 Configuración Inicial

### 1. Crear archivo `.env`

Crear un archivo `.env` en la raíz del proyecto con las siguientes variables:

```bash
# Clave privada (sin el prefijo 0x)
PRIVATE_KEY=0xTU_CLAVE_PRIVADA_AQUI

# RPC URL de Sepolia
RPC_URL_SEPOLIA=https://eth-sepolia.g.alchemy.com/v2/TU_API_KEY

# API Key de Etherscan (opcional, para verificación)
ETHERSCAN_API_KEY=TU_ETHERSCAN_API_KEY

# Dirección del deployer (calculada desde PRIVATE_KEY)
DEPLOYER_ADDRESS=0xTU_DIRECCION_AQUI
```

> ⚠️ **IMPORTANTE**: Nunca commitear el archivo `.env` al repositorio.

### 2. Verificar Fondos

Asegurarse de tener al menos **0.1 ETH** en Sepolia para cubrir el gas del despliegue.

```bash
# Verificar balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL_SEPOLIA
```

## 📦 Método 1: Despliegue con Script (Recomendado)

### Compilar el contrato

```bash
forge build
```

### Ejecutar script de despliegue

```bash
# Cargar variables de entorno
source .env

# Desplegar (usar --legacy para evitar problemas de tipo de transacción en Sepolia)
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url sepolia \
  --broadcast \
  --legacy \
  -vvv

# Guardar la dirección del contrato que aparece en los logs:
# "KipuBankV3 Contract Address: 0x..."
```

> **Nota**: Usamos `--rpc-url sepolia` (alias de Foundry) en lugar de `$RPC_URL_SEPOLIA` para mayor simplicidad. El flag `--legacy` asegura compatibilidad con nodos RPC que no soportan EIP-1559.

### Parámetros del Constructor

El script `Deploy.s.sol` despliega el contrato con los siguientes parámetros pre-configurados para Sepolia:

```solidity
// Chainlink ETH/USD Price Feed (Sepolia)
address ethPriceFeedAddress = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

// Límite máximo de retiro por transacción (1 ETH)
uint256 maxWithdrawalAmount = 1 ether;

// Uniswap V2 Router (Sepolia)
address routerAddress = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;

// USDC Token (Sepolia)
address usdcAddress = 0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D;
```

## 📦 Método 2: Despliegue Manual con `forge create`

Si preferís desplegar manualmente sin script:

```bash
source .env

forge create src/KipuBankV3.sol:KipuBankV3 \
  --rpc-url $RPC_URL_SEPOLIA \
  --private-key $PRIVATE_KEY \
  --constructor-args \
    0x694AA1769357215DE4FAC081bf1f309aDC325306 \
    1000000000000000000 \
    0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3 \
    0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## ✅ Verificación Post-Despliegue

### 1. Obtener dirección del contrato

El comando de despliegue mostrará en los logs:
```
========== KipuBankV3 Deployment Complete ==========
KipuBankV3 Contract Address: 0x...
```

### 2. Verificar código en exploradores

#### Etherscan (recomendado - método automático)

```bash
# Auto-detecta constructor args
forge verify-contract <DIRECCION_CONTRATO> \
  src/KipuBankV3.sol:KipuBankV3 \
  --chain sepolia \
  --watch
```

Verificar en: `https://sepolia.etherscan.io/address/<DIRECCION>#code`

#### Blockscout

```bash
forge verify-contract <DIRECCION_CONTRATO> \
  src/KipuBankV3.sol:KipuBankV3 \
  --verifier blockscout \
  --verifier-url https://eth-sepolia.blockscout.com/api
```

Verificar en: `https://eth-sepolia.blockscout.com/address/<DIRECCION>`

### 3. Verificar parámetros del contrato

```bash
# Verificar MAX_WITHDRAWAL_PER_TX (debe ser 1000000000000000000 = 1 ETH)
cast call <DIRECCION> "MAX_WITHDRAWAL_PER_TX()(uint256)" --rpc-url sepolia

# Verificar BANK_CAP_USD (debe ser 10000000000 = $100 con 8 decimales)
cast call <DIRECCION> "BANK_CAP_USD()(uint256)" --rpc-url sepolia

# Verificar PRICE_FEED_TIMEOUT (debe ser 10800 = 3 horas)
cast call <DIRECCION> "PRICE_FEED_TIMEOUT()(uint256)" --rpc-url sepolia

# Verificar Router
cast call <DIRECCION> "I_ROUTER()(address)" --rpc-url sepolia

# Verificar USDC
cast call <DIRECCION> "USDC_TOKEN()(address)" --rpc-url sepolia
```

### 4. Verificar roles (RBAC)

```bash
# DEFAULT_ADMIN_ROLE (bytes32(0))
cast call <DIRECCION> "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  <TU_DIRECCION> \
  --rpc-url sepolia
```

## 🧪 Interacción Post-Despliegue

### Script de interacción educativo

```bash
# Ejecutar script de interacción en modo dry-run (sin gastar gas)
forge script script/Interact.s.sol:InteractScript \
  --rpc-url $RPC_URL_SEPOLIA \
  -vvvv \
  --dry-run
```

### Depósito de ETH (ejemplo)

```bash
# Depositar 0.01 ETH
cast send 0xDIRECCION_DEL_CONTRATO "deposit()" \
  --value 0.01ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL_SEPOLIA
```

### Consultar balance interno

```bash
# Balance de ETH (address(0))
cast call 0xDIRECCION_DEL_CONTRATO "balances(address,address)(uint256)" \
  $DEPLOYER_ADDRESS \
  0x0000000000000000000000000000000000000000 \
  --rpc-url $RPC_URL_SEPOLIA
```

## 📊 Direcciones de Referencia en Sepolia

| Componente | Dirección |
|------------|-----------|
| Chainlink ETH/USD Feed | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |
| Uniswap V2 Router | `0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3` |
| USDC Token | `0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D` |
| WETH Token | `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14` |

## 🔐 Seguridad

- ✅ Nunca compartir el archivo `.env`
- ✅ Usar cuentas de testnet exclusivas (no reutilizar claves de mainnet)
- ✅ Verificar direcciones de contratos externos antes de desplegar
- ✅ Revisar gas estimado antes de confirmar transacciones

## 🐛 Troubleshooting

### Error: "Dry run enabled, not broadcasting transaction"

**Causa**: Falta el flag `--broadcast` o hay un problema con la `PRIVATE_KEY`.

**Solución**:
```bash
# Verificar formato de PRIVATE_KEY (debe tener prefijo 0x)
echo $PRIVATE_KEY

# Asegurar que el script tiene --broadcast
forge script ... --broadcast --verify
```

### Error: "Constructor revert"

**Causa**: Alguna dirección de constructor es inválida (no existe en Sepolia).

**Solución**:
```bash
# Verificar que el router existe
cast code 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3 --rpc-url $RPC_URL_SEPOLIA

# Verificar USDC
cast code 0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D --rpc-url $RPC_URL_SEPOLIA
```

### Error: "Insufficient funds"

**Causa**: Balance insuficiente para cubrir el gas.

**Solución**:
```bash
# Obtener fondos de testnet en:
# https://sepoliafaucet.com/
# https://faucet.quicknode.com/ethereum/sepolia
```

## 📚 Recursos Adicionales

- [Documentación de Foundry](https://book.getfoundry.sh/)
- [Chainlink Price Feeds](https://docs.chain.link/data-feeds/price-feeds/addresses)
- [Uniswap V2 Docs](https://docs.uniswap.org/contracts/v2/overview)
- [Sepolia Faucets](https://sepoliafaucet.com/)

---

**Última actualización:** 28 de Noviembre 2025 (v2 - con correcciones de atomicidad y NatSpec)
