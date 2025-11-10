## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

---

# KipuBank V3 - DeFi Bank con Integración Uniswap V2

## Descripción General

KipuBank V3 es una evolución del KipuBank V2 que integra capacidades DeFi mediante la integración con Uniswap V2. Esta versión permite a los usuarios depositar cualquier token soportado por Uniswap V2, realiza el swap automático a USDC y mantiene un control estricto sobre el límite máximo del banco (bank cap).

### Características Principales

1. **Soporte Multi-Token**
   - Depósito de token nativo (ETH)
   - Depósito directo de USDC
   - Soporte para cualquier token ERC20 con par USDC en Uniswap V2

2. **Swaps Automáticos**
   - Integración con Uniswap V2 Router
   - Conversión automática de tokens a USDC
   - Gestión eficiente de slippage y deadlines

3. **Control de Límites**
   - Respeto estricto del bank cap
   - Validación previa al swap
   - Protección contra overflow

4. **Seguridad**
   - Control de ownership
   - Protección contra reentrancy
   - Validaciones de cantidad mínima recibida
   - Manejo seguro de aprobaciones

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

## Instrucciones de Despliegue

### Configuración Inicial

1. **Clonar el repositorio**
```bash
git clone [URL_DEL_REPO]
cd KipuBankV3_TP4
```

2. **Instalar dependencias**
```bash
forge install
```

3. **Configurar variables de entorno**
Crear archivo `.env` en la raíz del proyecto:
```bash
# Clave privada del deployer (SIN el prefijo 0x)
PRIVATE_KEY=your_private_key_here

# URL RPC para Sepolia testnet
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY

# O para Mainnet (solo después de auditoría)
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
```

### Desarrollo Local

4. **Compilar contratos**
```bash
forge build
```

5. **Ejecutar tests**
```bash
# Todas las pruebas
forge test

# Pruebas con salida detallada
forge test -vv

# Pruebas específicas
forge test --match testDepositEth -vv

# Cobertura de pruebas
forge coverage
```

6. **Análisis estático (opcional)**
```bash
# Con slither (requiere instalación previa)
slither src/KipuBankV3_TP4.sol
```

### Despliegue en Sepolia Testnet

7. **Desplegar en Sepolia**
```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

**Nota:** Después del despliegue, guardará la dirección del contrato. Guardala para verificación posterior.

### Verificación en Etherscan/Blockscout

8. **Verificar contrato en Etherscan**
```bash
forge verify-contract \
  <CONTRACT_ADDRESS> \
  src/KipuBankV3_TP4.sol:KipuBankV3 \
  --chain-id 11155111 \
  --compiler-version v0.8.30 \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Configuración Post-Despliegue

Después del despliegue, es recomendable registrar tokens adicionales en el catálogo del banco:

```solidity
// Ejemplo: Registrar un token ERC20 adicional
function addOrUpdateToken(
    address tokenAddress,    // Dirección del token ERC20
    address priceFeedAddress, // Dirección del oráculo Chainlink (si es necesario)
    uint8 decimals            // Decimales del token (ej: 18 para USDC, 6 para DAI)
) external onlyRole(TOKEN_MANAGER_ROLE)
```

### Despliegue en Mainnet (SOLO después de auditoría)

**IMPORTANTE:** Solo usar este script después de:
- ✅ Auditoría de seguridad completa
- ✅ Testing exhaustivo en testnet
- ✅ Revisión de código por pares

```bash
forge script script/Deploy.s.sol:DeployMainnetScript \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify
```

## Interacción con el Contrato

### Funciones Principales

1. **Depósito de ETH**
```solidity
function deposit() external payable
```
**Descripción:** Permite a usuarios depositar ETH nativo. El monto se valida contra el límite del banco.
**Eventos:** `DepositSuccessful(user, address(0), amount)`

2. **Depósito de Tokens ERC20 con Swap Automático**
```solidity
function depositAndSwapERC20(
    address tokenIn,
    uint256 amountIn,
    uint256 amountOutMin,
    uint48 deadline
) external
```
**Descripción:** Deposita un token ERC20, realiza swap automático a USDC mediante Uniswap V2.
- `tokenIn`: Dirección del token a depositar
- `amountIn`: Cantidad de tokens a depositar
- `amountOutMin`: Cantidad mínima de USDC a recibir (protección slippage)
- `deadline`: Timestamp máximo para la ejecución

**Eventos:** `DepositSuccessful(user, USDC_TOKEN, usdcReceived)`

3. **Retiro de Tokens**
```solidity
function withdrawToken(
    address tokenAddress,
    uint256 amountToWithdraw
) external
```
**Descripción:** Permite retirar ETH o USDC del balance del usuario.
- `tokenAddress`: `address(0)` para ETH, dirección USDC para stablecoin
- `amountToWithdraw`: Cantidad a retirar (máximo `MAX_WITHDRAWAL_PER_TX`)

**Eventos:** `WithdrawalSuccessful(user, tokenAddress, amount)`

### Funciones Administrativas

1. **Pausa/Reanudación del Contrato**
```solidity
function pause() external onlyRole(PAUSE_MANAGER_ROLE)
function unpause() external onlyRole(PAUSE_MANAGER_ROLE)
```

2. **Actualizar Feed de Precios**
```solidity
function setEthPriceFeedAddress(address newAddress) 
    external 
    onlyRole(CAP_MANAGER_ROLE)
```

3. **Registrar/Actualizar Tokens**
```solidity
function addOrUpdateToken(
    address token,
    address priceFeed,
    uint8 decimals
) external onlyRole(TOKEN_MANAGER_ROLE)
```

### Funciones de Consulta (View)

```solidity
// Obtener balance de un usuario para un token específico
function balances(address user, address token) public view returns (uint256)

// Obtener número total de depósitos
function getDepositCount() external view returns (uint256)

// Obtener dirección WETH usada en rutas de swap
function getWethAddress() external view returns (address)

// Constantes públicas
BANK_CAP_USD                  // Límite del banco en USD (8 decimales)
MAX_WITHDRAWAL_PER_TX         // Límite por retiro
USDC_TOKEN                    // Dirección de USDC
WETH_TOKEN                    // Dirección de WETH
```

### Ejemplos de Interacción (JavaScript/Ethers.js)

#### Depósito de ETH
```javascript
const amount = ethers.utils.parseEther("1.0"); // 1 ETH
const tx = await kipuBank.deposit({ value: amount });
await tx.wait();
console.log("Depósito exitoso!");
```

#### Depósito con Swap de Token
```javascript
const tokenAddress = "0x..."; // Token ERC20 a depositar
const amountIn = ethers.utils.parseUnits("100", 18);
const minUSDCOut = ethers.utils.parseUnits("95", 6); // Min 95 USDC
const deadline = Math.floor(Date.now() / 1000) + 300; // 5 minutos

// Aprobar primero
const tokenContract = new ethers.Contract(tokenAddress, erc20ABI, signer);
const approveTx = await tokenContract.approve(kipuBank.address, amountIn);
await approveTx.wait();

// Luego depositar y hacer swap
const tx = await kipuBank.depositAndSwapERC20(
    tokenAddress,
    amountIn,
    minUSDCOut,
    deadline
);
await tx.wait();
```

#### Retiro de USDC
```javascript
const usdcAmount = ethers.utils.parseUnits("50", 6); // 50 USDC
const tx = await kipuBank.withdrawToken(USDC_ADDRESS, usdcAmount);
await tx.wait();
```

#### Consultar Balance
```javascript
const userBalance = await kipuBank.balances(userAddress, USDC_ADDRESS);
console.log("Balance en USDC:", ethers.utils.formatUnits(userBalance, 6));
```

---

## Análisis de Amenazas

### Riesgos Identificados

1. **Riesgo de Manipulación de Precios**
   - Impacto: Alto
   - Mitigación: Implementación de checks de slippage y deadlines

2. **Riesgo de Reentrancy**
   - Impacto: Alto
   - Mitigación: Uso de ReentrancyGuard y patrón checks-effects-interactions

3. **Riesgo de Overflow/Underflow**
   - Impacto: Alto
   - Mitigación: Uso de SafeMath y validaciones de límites

4. **Riesgo de Token Malicioso**
   - Impacto: Medio
   - Mitigación: Validaciones de transferencia y balance

### Pasos para Madurez del Protocolo

1. Auditoría externa profesional
2. Implementación de pausabilidad
3. Sistema de governanza
4. Pruebas de integración exhaustivas
5. Simulaciones de ataque en testnet

## Cobertura de Pruebas

La cobertura actual del protocolo supera el 50% requerido, incluyendo:

1. Pruebas unitarias de funciones core
2. Pruebas de integración con Uniswap
3. Pruebas de casos límite
4. Fuzzing tests para funciones críticas

### Métodos de Prueba

1. **Pruebas Unitarias**
   - Depósitos y retiros
   - Manejo de límites
   - Control de ownership

2. **Pruebas de Integración**
   - Swaps con Uniswap
   - Manejo de tokens
   - Flujos completos de operación

3. **Fuzzing**
   - Inputs aleatorios
   - Casos extremos
   - Secuencias de operaciones

## Decisiones de Diseño y Trade-offs

1. **Almacenamiento en USDC**
   - Pros: Estabilidad, facilidad de contabilidad
   - Cons: Costos de gas en swaps

2. **Swaps Directos**
   - Pros: Eficiencia en gas
   - Cons: Limitado a pares directos con USDC

3. **Validaciones Previas**
   - Pros: Seguridad, prevención de fallos
   - Cons: Costos de gas adicionales

## Stack Tecnológico

- Solidity ^0.8.20
- Foundry (Forge, Cast, Anvil)
- OpenZeppelin Contracts
- Uniswap V2 Protocol

## Licencia

[Especificar licencia]
