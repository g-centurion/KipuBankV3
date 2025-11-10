# Guía de Integración - KipuBankV3 para Frontend

## Tabla de Contenidos
1. [Configuración Inicial](#configuración-inicial)
2. [Conexión al Contrato](#conexión-al-contrato)
3. [Interface ABI](#interface-abi)
4. [Funciones Disponibles](#funciones-disponibles)
5. [Eventos](#eventos)
6. [Ejemplos Completos](#ejemplos-completos)
7. [Manejo de Errores](#manejo-de-errores)
8. [Best Practices](#best-practices)

---

## Configuración Inicial

### Instalación de Dependencias

```bash
npm install ethers viem wagmi @rainbow-me/rainbowkit

# O si prefieres usar ethers v6
npm install ethers@^6.0.0
```

### Configuración de Variables de Entorno

```.env.local
REACT_APP_CONTRACT_ADDRESS=0x...  # Dirección del contrato desplegado
REACT_APP_NETWORK_ID=11155111     # Sepolia testnet
REACT_APP_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
REACT_APP_ETHERSCAN_URL=https://sepolia.etherscan.io
```

### Redes Soportadas

| Red | Chain ID | Estado |
|-----|----------|--------|
| Sepolia | 11155111 | ✅ Testnet |
| Ethereum Mainnet | 1 | 🚫 Requiere auditoría |

---

## Conexión al Contrato

### Con Ethers.js v6

```javascript
import { ethers } from 'ethers';
import KipuBankV3_ABI from './abis/KipuBankV3.json';

// Conectar a Sepolia
const provider = new ethers.JsonRpcProvider(
  'https://sepolia.infura.io/v3/YOUR_KEY'
);

// Con wallet (si el usuario está conectado)
const signer = provider.getSigner();

// Instancia del contrato
const kipuBank = new ethers.Contract(
  process.env.REACT_APP_CONTRACT_ADDRESS,
  KipuBankV3_ABI,
  signer
);
```

### Con Wagmi + RainbowKit (Recomendado para dApps)

```javascript
import { useContractRead, useContractWrite } from 'wagmi';
import { useAccount } from 'wagmi';

export function KipuBankComponent() {
  const { address } = useAccount();
  
  // Leer balance
  const { data: balance } = useContractRead({
    address: process.env.REACT_APP_CONTRACT_ADDRESS,
    abi: KipuBankV3_ABI,
    functionName: 'balances',
    args: [address, USDC_ADDRESS],
  });

  return (
    <div>
      <p>Balance USDC: {balance}</p>
    </div>
  );
}
```

---

## Interface ABI

### Contrato Principal

```typescript
interface KipuBankV3 {
  // DEPOSIT FUNCTIONS
  function deposit() external payable
  function depositAndSwapERC20(
    address tokenIn,
    uint256 amountIn,
    uint256 amountOutMin,
    uint48 deadline
  ) external

  // WITHDRAWAL FUNCTIONS
  function withdrawToken(
    address tokenAddress,
    uint256 amountToWithdraw
  ) external

  // ADMIN FUNCTIONS
  function pause() external onlyRole(PAUSE_MANAGER_ROLE)
  function unpause() external onlyRole(PAUSE_MANAGER_ROLE)
  function setEthPriceFeedAddress(
    address newAddress
  ) external onlyRole(CAP_MANAGER_ROLE)
  function addOrUpdateToken(
    address token,
    address priceFeed,
    uint8 decimals
  ) external onlyRole(TOKEN_MANAGER_ROLE)

  // VIEW FUNCTIONS
  function balances(
    address user,
    address token
  ) external view returns (uint256)
  function getDepositCount() external view returns (uint256)
  function getWethAddress() external view returns (address)

  // CONSTANTS
  function BANK_CAP_USD() external view returns (uint256)
  function MAX_WITHDRAWAL_PER_TX() external view returns (uint256)
  function USDC_TOKEN() external view returns (address)
  function WETH_TOKEN() external view returns (address)
}
```

---

## Funciones Disponibles

### 1. deposit() - Depositar ETH

```javascript
// Descripción: Deposita ETH nativo en el banco
// Gas estimado: 25,000 - 30,000

async function depositETH(amountInEther) {
  try {
    const amountInWei = ethers.parseEther(amountInEther);
    
    const tx = await kipuBank.deposit({
      value: amountInWei,
      gasLimit: 50000
    });

    const receipt = await tx.wait();
    console.log('Depósito exitoso:', receipt.hash);
    
    return receipt;
  } catch (error) {
    console.error('Error en depósito:', error);
    handleError(error);
  }
}
```

**Parámetros:**
- Valor en Wei (ETH nativo)

**Retorna:**
- Transacción confirmada
- Eventos: `DepositSuccessful(user, address(0), amount)`

**Errores Posibles:**
- `Bank__ZeroAmount`: Si el monto es 0
- `Bank__DepositExceedsCap`: Si excede el límite
- `EnforcedPause`: Si el contrato está pausado

---

### 2. depositAndSwapERC20() - Depositar Token y Hacer Swap

```javascript
// Descripción: Deposita un token ERC20 y lo convierte a USDC automáticamente
// Gas estimado: 150,000 - 200,000

async function depositAndSwap(
  tokenAddress,
  amountInTokenUnits,
  minUSDCOut,
  deadlineInSeconds = 300
) {
  try {
    // 1. Obtener información del token
    const tokenABI = ['function approve(address spender, uint256 amount) returns (bool)'];
    const tokenContract = new ethers.Contract(
      tokenAddress,
      tokenABI,
      signer
    );

    // 2. Validar balance del usuario
    const userBalance = await tokenContract.balanceOf(signer.address);
    if (userBalance < amountInTokenUnits) {
      throw new Error('Insufficient balance');
    }

    // 3. Aprobar el contrato
    const approveTx = await tokenContract.approve(
      kipuBank.address,
      amountInTokenUnits
    );
    await approveTx.wait();
    console.log('Aprobación exitosa');

    // 4. Calcular deadline
    const deadline = Math.floor(Date.now() / 1000) + deadlineInSeconds;

    // 5. Ejecutar swap
    const tx = await kipuBank.depositAndSwapERC20(
      tokenAddress,
      amountInTokenUnits,
      minUSDCOut,
      deadline,
      {
        gasLimit: 250000
      }
    );

    const receipt = await tx.wait();
    console.log('Swap exitoso:', receipt.hash);

    return receipt;
  } catch (error) {
    console.error('Error en swap:', error);
    handleError(error);
  }
}
```

**Parámetros:**
- `tokenIn` (address): Dirección del token ERC20
- `amountIn` (uint256): Cantidad en unidades del token
- `amountOutMin` (uint256): Mínimo USDC a recibir
- `deadline` (uint48): Timestamp máximo (unix)

**Retorna:**
- Transacción confirmada
- USDC acreditado en balance del usuario
- Eventos: `DepositSuccessful(user, USDC_ADDRESS, usdcReceived)`

**Errores Posibles:**
- `Bank__TokenNotSupported`: Token no permitido
- `Bank__SlippageTooHigh`: Slippage mayor al esperado
- `Bank__DepositExceedsCap`: Excede límite del banco

---

### 3. withdrawToken() - Retirar Tokens

```javascript
// Descripción: Retira ETH o USDC del balance del usuario
// Gas estimado: 50,000 - 70,000

async function withdrawTokens(tokenAddress, amountToWithdraw) {
  try {
    // Validar token
    const USDC_ADDRESS = process.env.REACT_APP_USDC_ADDRESS;
    const ETH_ADDRESS = '0x0000000000000000000000000000000000000000';

    if (tokenAddress !== ETH_ADDRESS && tokenAddress !== USDC_ADDRESS) {
      throw new Error('Token no soportado');
    }

    // Validar cantidad
    if (amountToWithdraw <= 0) {
      throw new Error('Cantidad debe ser mayor a 0');
    }

    // Ejecutar retiro
    const tx = await kipuBank.withdrawToken(
      tokenAddress,
      amountToWithdraw,
      {
        gasLimit: 100000
      }
    );

    const receipt = await tx.wait();
    console.log('Retiro exitoso:', receipt.hash);

    return receipt;
  } catch (error) {
    console.error('Error en retiro:', error);
    handleError(error);
  }
}
```

**Parámetros:**
- `tokenAddress` (address): `0x0...0` para ETH, dirección USDC para USDC
- `amountToWithdraw` (uint256): Cantidad en unidades

**Retorna:**
- Transacción confirmada
- Tokens transferidos al usuario
- Eventos: `WithdrawalSuccessful(user, tokenAddress, amount)`

**Errores Posibles:**
- `Bank__ZeroAmount`: Si el monto es 0
- `Bank__WithdrawalExceedsLimit`: Excede límite por transacción
- `Bank__InsufficientBalance`: Balance insuficiente
- `Bank__TokenNotSupported`: Token no soportado

---

### 4. balances() - Consultar Balance

```javascript
// Descripción: Obtiene el balance de un usuario para un token específico
// Gas: 0 (view function)

async function getBalance(userAddress, tokenAddress) {
  try {
    const balance = await kipuBank.balances(userAddress, tokenAddress);
    return balance;
  } catch (error) {
    console.error('Error al obtener balance:', error);
    return 0n;
  }
}

// Uso:
const ethBalance = await getBalance(userAddress, ETH_ADDRESS);
const usdcBalance = await getBalance(userAddress, USDC_ADDRESS);

console.log('ETH:', ethers.formatEther(ethBalance));
console.log('USDC:', ethers.formatUnits(usdcBalance, 6));
```

---

### 5. Obtener Información de Constantes

```javascript
async function getContractInfo() {
  const [bankCapUSD, maxWithdrawal, usdcToken, wethToken] = 
    await Promise.all([
      kipuBank.BANK_CAP_USD(),
      kipuBank.MAX_WITHDRAWAL_PER_TX(),
      kipuBank.USDC_TOKEN(),
      kipuBank.WETH_TOKEN()
    ]);

  return {
    bankCapUSD: ethers.formatUnits(bankCapUSD, 8),
    maxWithdrawal: ethers.formatEther(maxWithdrawal),
    usdcToken,
    wethToken
  };
}
```

---

## Eventos

### Event: DepositSuccessful

```solidity
event DepositSuccessful(
  address indexed user,
  address indexed token,
  uint256 amount
);
```

**Escuchar evento:**
```javascript
kipuBank.on('DepositSuccessful', (user, token, amount, event) => {
  console.log(`Depósito exitoso:
    Usuario: ${user}
    Token: ${token}
    Cantidad: ${amount}
  `);
});

// Remover listener
kipuBank.off('DepositSuccessful');
```

---

### Event: WithdrawalSuccessful

```solidity
event WithdrawalSuccessful(
  address indexed user,
  address indexed token,
  uint256 amount
);
```

**Escuchar evento:**
```javascript
kipuBank.on('WithdrawalSuccessful', (user, token, amount, event) => {
  console.log(`Retiro exitoso:
    Usuario: ${user}
    Token: ${token}
    Cantidad: ${amount}
  `);
});
```

---

## Ejemplos Completos

### Ejemplo 1: React Hook para Depositar ETH

```javascript
import { useState } from 'react';
import { useAccount, useContractWrite } from 'wagmi';
import { ethers } from 'ethers';

export function DepositETHForm() {
  const { address } = useAccount();
  const [amount, setAmount] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const { write: deposit } = useContractWrite({
    address: process.env.REACT_APP_CONTRACT_ADDRESS,
    abi: KipuBankV3_ABI,
    functionName: 'deposit',
  });

  const handleDeposit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      if (!amount || parseFloat(amount) <= 0) {
        throw new Error('Ingrese una cantidad válida');
      }

      const amountWei = ethers.parseEther(amount);

      deposit({
        value: amountWei,
        onSuccess: (hash) => {
          console.log('Depósito exitoso:', hash);
          setAmount('');
          // Mostrar notificación de éxito
        },
        onError: (err) => {
          setError(err.message);
        },
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleDeposit}>
      <input
        type="number"
        placeholder="Cantidad en ETH"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        step="0.01"
        min="0"
      />
      <button type="submit" disabled={loading || !address}>
        {loading ? 'Depositando...' : 'Depositar'}
      </button>
      {error && <p style={{ color: 'red' }}>{error}</p>}
    </form>
  );
}
```

---

### Ejemplo 2: Servicio de Swap con Cálculo de Mínimo

```javascript
import { ethers } from 'ethers';

class KipuBankService {
  constructor(contractAddress, provider) {
    this.contractAddress = contractAddress;
    this.provider = provider;
    this.contract = new ethers.Contract(
      contractAddress,
      KipuBankV3_ABI,
      provider
    );
  }

  /**
   * Calcula el mínimo USDC a recibir con slippage tolerance
   */
  async calculateMinOutput(
    tokenAddress,
    amountIn,
    slippagePercent = 2 // 2% por defecto
  ) {
    try {
      // Ruta de swap
      const path = this.getSwapPath(tokenAddress);

      // Obtener amounts esperados
      const amounts = await this.contract.I_ROUTER.getAmountsOut(
        amountIn,
        path
      );

      const expectedOutput = amounts[amounts.length - 1];

      // Aplicar slippage
      const minOutput = 
        (expectedOutput * (100 - slippagePercent)) / 100;

      return {
        expectedOutput: expectedOutput.toString(),
        minOutput: minOutput.toString(),
        slippage: slippagePercent
      };
    } catch (error) {
      console.error('Error calculando output mínimo:', error);
      throw error;
    }
  }

  /**
   * Obtiene la ruta de swap para un token
   */
  getSwapPath(tokenAddress) {
    const WETH = process.env.REACT_APP_WETH_ADDRESS;
    const USDC = process.env.REACT_APP_USDC_ADDRESS;

    if (tokenAddress === WETH) {
      return [WETH, USDC];
    }
    return [tokenAddress, WETH, USDC];
  }

  /**
   * Deposita y hace swap
   */
  async depositAndSwap(
    signer,
    tokenAddress,
    amountIn,
    slippagePercent = 2
  ) {
    try {
      // 1. Calcular mínimo output
      const { minOutput } = await this.calculateMinOutput(
        tokenAddress,
        amountIn,
        slippagePercent
      );

      // 2. Aprobar token
      const tokenContract = new ethers.Contract(
        tokenAddress,
        ['function approve(address spender, uint256 amount) returns (bool)'],
        signer
      );

      const approveTx = await tokenContract.approve(
        this.contractAddress,
        amountIn
      );
      await approveTx.wait();

      // 3. Ejecutar swap
      const deadline = Math.floor(Date.now() / 1000) + 300;
      const contract = new ethers.Contract(
        this.contractAddress,
        KipuBankV3_ABI,
        signer
      );

      const tx = await contract.depositAndSwapERC20(
        tokenAddress,
        amountIn,
        minOutput,
        deadline,
        { gasLimit: 250000 }
      );

      const receipt = await tx.wait();
      return receipt;
    } catch (error) {
      console.error('Error en swap:', error);
      throw error;
    }
  }
}

export default KipuBankService;
```

---

## Manejo de Errores

### Custom Errors

```javascript
const ERROR_MESSAGES = {
  Bank__DepositExceedsCap: 'El depósito excede el límite del banco',
  Bank__WithdrawalExceedsLimit: 'El retiro excede el límite por transacción',
  Bank__InsufficientBalance: 'Balance insuficiente',
  Bank__TransferFailed: 'Error en la transferencia',
  Bank__InvalidTokenAddress: 'Dirección de token inválida',
  Bank__SlippageTooHigh: 'Slippage demasiado alto',
  Bank__ZeroAmount: 'La cantidad no puede ser cero',
  Bank__TokenNotSupported: 'Token no soportado',
  EnforcedPause: 'El contrato está pausado',
  AccessControlUnauthorizedAccount: 'No tienes permisos para esta acción',
};

function getErrorMessage(error) {
  // Buscar en custom errors
  for (const [errorName, message] of Object.entries(ERROR_MESSAGES)) {
    if (error.message?.includes(errorName)) {
      return message;
    }
  }

  // Errores de red
  if (error.code === 'NETWORK_ERROR') {
    return 'Error de conexión de red';
  }

  // Transacción rechazada por usuario
  if (error.code === 'ACTION_REJECTED') {
    return 'Transacción rechazada por el usuario';
  }

  return error.message || 'Error desconocido';
}
```

---

## Best Practices

### 1. Validación de Entrada

```javascript
function validateDepositAmount(amount, maxAllowed) {
  if (!amount || parseFloat(amount) <= 0) {
    throw new Error('Cantidad debe ser mayor a 0');
  }

  if (parseFloat(amount) > maxAllowed) {
    throw new Error(`Cantidad máxima: ${maxAllowed}`);
  }

  // Validar decimales
  const decimalPlaces = (amount.toString().split('.')[1] || '').length;
  if (decimalPlaces > 18) {
    throw new Error('Máximo 18 decimales permitidos');
  }
}
```

### 2. Cálculo Seguro de Deadlines

```javascript
function getDeadline(minutesFromNow = 5) {
  const now = Math.floor(Date.now() / 1000);
  const deadline = now + (minutesFromNow * 60);
  
  if (deadline > now + (24 * 60 * 60)) {
    throw new Error('Deadline máximo: 24 horas');
  }
  
  return deadline;
}
```

### 3. Reintentos con Exponential Backoff

```javascript
async function retryTransaction(fn, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      
      const delay = Math.pow(2, i) * 1000; // 1s, 2s, 4s
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}
```

### 4. Monitoreo de Transacciones

```javascript
async function waitForTransaction(
  provider,
  txHash,
  confirmations = 1,
  timeout = 60000
) {
  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    const receipt = await provider.getTransactionReceipt(txHash);

    if (receipt && receipt.confirmations >= confirmations) {
      if (receipt.status === 1) {
        return receipt;
      } else {
        throw new Error('Transaction failed');
      }
    }

    await new Promise(resolve => setTimeout(resolve, 1000));
  }

  throw new Error('Transaction timeout');
}
```

### 5. Gestión de Allowance

```javascript
async function ensureAllowance(
  tokenContract,
  spenderAddress,
  requiredAmount,
  signer
) {
  const currentAllowance = await tokenContract.allowance(
    signer.address,
    spenderAddress
  );

  if (currentAllowance >= requiredAmount) {
    return; // Ya tiene allowance suficiente
  }

  // Incrementar allowance
  const tx = await tokenContract.increaseAllowance(
    spenderAddress,
    requiredAmount - currentAllowance
  );

  await tx.wait();
}
```

---

## Recursos Útiles

- [Ethers.js Documentación](https://docs.ethers.org/)
- [Wagmi Documentación](https://wagmi.sh/)
- [RainbowKit](https://www.rainbowkit.com/)
- [Uniswap V2 Docs](https://docs.uniswap.org/sdk/guides/protocol)
- [Sepolia Faucets](https://sepoliafaucet.com/)

---

**Última Actualización:** 10 de Noviembre de 2025  
**Versión:** 1.0  
**Para:** Desarrolladores de Frontend
