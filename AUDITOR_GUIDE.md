# Guía de Auditoría - KipuBankV3

## Tabla de Contenidos
1. [Introducción](#introducción)
2. [Arquitectura del Sistema](#arquitectura-del-sistema)
3. [Flujos Críticos](#flujos-críticos)
4. [Checklist de Seguridad](#checklist-de-seguridad)
5. [Pruebas Recomendadas](#pruebas-recomendadas)
6. [Consideraciones de Gas](#consideraciones-de-gas)
7. [Consideraciones de Privacidad](#consideraciones-de-privacidad)

---

## Introducción

Este documento está diseñado para **auditores de seguridad** que necesitan entender y verificar la implementación de KipuBankV3.

### Información General
- **Contrato Principal:** `KipuBankV3_TP4.sol` (Solidity 0.8.30)
- **Red de Prueba:** Sepolia Testnet
- **Dependencias Externas:** Uniswap V2, Chainlink, OpenZeppelin
- **Tipo de Auditoría:** Seguridad de smart contracts + Integración de protocolos

### Scope de Auditoría
```
✅ KipuBankV3_TP4.sol (Contrato Principal)
✅ Deploy.s.sol (Script de Despliegue)
✅ KipuBankV3Test.sol (Suite de Pruebas)
❌ Contratos de Terceros (Uniswap V2, Chainlink, OpenZeppelin)
```

---

## Arquitectura del Sistema

### 1. Componentes Principales

```
┌─────────────────────────────────────┐
│     KipuBankV3 (Contrato)           │
│  - Gestión de depósitos/retiros     │
│  - Control de roles (RBAC)          │
│  - Pausa de emergencia              │
│  - Swaps automáticos                │
└─────────────────────────────────────┘
        ↓                      ↓
    ┌───────────────┐    ┌─────────────┐
    │ Chainlink     │    │ Uniswap V2  │
    │ Price Feeds   │    │ Router      │
    └───────────────┘    └─────────────┘
        ETH/USD Price      Token Swaps
```

### 2. Flujo de Datos - Depósito de ETH

```
Usuario → deposit() 
  ↓
Validación de precio (Chainlink)
  ↓
Validación de BANK_CAP_USD
  ↓
Actualización de balance[usuario][ETH_TOKEN]
  ↓
Emisión de evento DepositSuccessful
```

### 3. Flujo de Datos - Depósito con Swap

```
Usuario → depositAndSwapERC20(token, amount, minOut, deadline)
  ↓
Validación de token permitido
  ↓
transferFrom(usuario, contrato, amount)
  ↓
Determinar ruta de swap (TOKEN → WETH → USDC)
  ↓
getAmountsOut() - Estimar USDC a recibir
  ↓
Validación de BANK_CAP_USD
  ↓
safeIncreaseAllowance() - Aprobar router
  ↓
swapExactTokensForTokens() - Ejecutar swap
  ↓
Validar USDC recibido >= minOut
  ↓
Actualizar balance[usuario][USDC_TOKEN]
  ↓
Emisión de evento DepositSuccessful
```

### 4. Variables de Estado Críticas

```solidity
// Balances por usuario y token
mapping(address => mapping(address => uint256)) public balances

// Catálogo de tokens permitidos
mapping(address => TokenData) private sTokenCatalog

// Contadores
uint256 private _depositCount
uint256 private _withdrawalCount
```

---

## Flujos Críticos

### Flujo 1: Depositar ETH

**Entrada:**
- ETH nativo

**Validaciones:**
- msg.value > 0
- ETH/USD price > 0
- (current_balance + new_deposit_value) <= BANK_CAP_USD

**Efectos:**
- balances[msg.sender][address(0)] += msg.value
- _depositCount++
- Emisión de evento

**Puntos de Riesgo:**
- Precio de Chainlink inválido
- BANK_CAP_USD puede ser excedido
- No hay protección directa de reentrancia (aunque improbable en receive)

---

### Flujo 2: Depositar Token con Swap

**Entrada:**
- Token ERC20, cantidad, minOut, deadline

**Validaciones:**
1. tokenIn != address(0) && tokenIn != USDC_TOKEN
2. amountIn > 0
3. sTokenCatalog[tokenIn].isAllowed == true
4. token.balanceOf(usuario) >= amountIn
5. token.allowance(usuario, contrato) >= amountIn
6. Ruta de swap válida
7. getAmountsOut >= amountOutMin
8. (current_balance + usdcReceived) <= BANK_CAP_USD
9. actualAmounts[last] >= amountOutMin (validación final)
10. deadline >= block.timestamp

**Transferencias Externas:**
1. safeTransferFrom(token, usuario, contrato, amountIn)
2. safeIncreaseAllowance(token, router, amountIn)
3. swapExactTokensForTokens (Uniswap V2)

**Efectos:**
- balances[msg.sender][USDC_TOKEN] += usdcReceived
- _depositCount++

**Puntos de Riesgo:**
- Token malicioso en transferencia
- Front-running en Uniswap
- Price oracle stale
- Reentrancia del token
- Overflow en balances

---

### Flujo 3: Retirar Tokens

**Entrada:**
- Token, cantidad

**Validaciones:**
1. amountToWithdraw > 0
2. tokenAddress in [address(0), USDC_TOKEN]
3. amountToWithdraw <= MAX_WITHDRAWAL_PER_TX
4. balances[msg.sender][tokenAddress] >= amountToWithdraw

**Transferencias Externas:**
1. Si token == address(0): call{value: amount}
2. Si token == USDC: safeTransfer(token, usuario, cantidad)

**Efectos:**
- balances[msg.sender][tokenAddress] -= amountToWithdraw
- _withdrawalCount++

**Puntos de Riesgo:**
- Reentrancia en ETH transfer (call)
- Token no transferible
- Overflow en balance

---

## Checklist de Seguridad

### ✅ Validaciones de Entrada

- [ ] `deposit()`: msg.value > 0
- [ ] `depositAndSwapERC20()`: tokenIn != address(0) && tokenIn != USDC
- [ ] `depositAndSwapERC20()`: amountIn > 0
- [ ] `withdrawToken()`: amountToWithdraw > 0
- [ ] `withdrawToken()`: tokenAddress in allowed list
- [ ] `setEthPriceFeedAddress()`: address != address(0)

### ✅ Control de Límites

- [ ] BANK_CAP_USD nunca excedido
- [ ] MAX_WITHDRAWAL_PER_TX respetado
- [ ] amountOutMin protege contra slippage excesivo
- [ ] Deadlines en swaps

### ✅ Seguridad de Transferencias

- [ ] SafeERC20 usado en todas las transferencias ERC20
- [ ] ETH transferido con `call{value:}`
- [ ] No hay re-entrada en withdrawToken
- [ ] Aprobaciones son mínimas y necesarias

### ✅ Protección de Reentrancia

- [ ] CEI (Checks-Effects-Interactions) pattern implementado
- [ ] Actualizaciones de estado ANTES de llamadas externas
- [ ] Sin delegatecall innecesario
- [ ] ReentrancyGuard NO implementado (considerar agregar)

### ✅ Control de Acceso

- [ ] `pause()`: Only PAUSE_MANAGER_ROLE
- [ ] `unpause()`: Only PAUSE_MANAGER_ROLE
- [ ] `setEthPriceFeedAddress()`: Only CAP_MANAGER_ROLE
- [ ] `addOrUpdateToken()`: Only TOKEN_MANAGER_ROLE
- [ ] Roles inicializados correctamente en constructor

### ✅ Manejo de Oráculos

- [ ] Chainlink feed validado para precios positivos
- [ ] Validación de Staleness: ❌ NO IMPLEMENTADO (CRÍTICO)
- [ ] Manejo de prices 0 o negativos
- [ ] Consideración de TWAP alternativo

### ✅ Eventos

- [ ] `DepositSuccessful` emitido en deposit()
- [ ] `DepositSuccessful` emitido en depositAndSwapERC20()
- [ ] `WithdrawalSuccessful` emitido en withdrawToken()
- [ ] Indexación correcta de eventos
- [ ] Parámetros correctos en eventos

### ✅ Manejo de Errores

- [ ] Custom errors definidos apropiadamente
- [ ] Mensajes de error descriptivos
- [ ] No hay require strings (optimización de gas)
- [ ] Errores específicos en cada caso

### ✅ Consideraciones de Gas

- [ ] `unchecked` usado conservadoramente
- [ ] Constantes marcadas como `constant` o `immutable`
- [ ] Storage optimizado (mappings vs arrays)
- [ ] Sin loops potencialmente infinitos

### ✅ Lógica de Negocio

- [ ] BANK_CAP_USD valor razonable (1M USD)
- [ ] MAX_WITHDRAWAL_PER_TX valor razonable (100 ETH)
- [ ] Ruta de swap correcta (TOKEN → WETH → USDC)
- [ ] Conversión de decimales correcta

---

## Pruebas Recomendadas

### Pruebas Unitarias

#### 1. Depósitos
```solidity
✅ Depósito de 0 ETH → Falla (ZeroAmount)
✅ Depósito de 1 ETH → Éxito
✅ Depósito que excede cap → Falla (DepositExceedsCap)
✅ Depósito token válido → Éxito
✅ Depósito token no permitido → Falla (TokenNotSupported)
```

#### 2. Retiros
```solidity
✅ Retiro de 0 → Falla (ZeroAmount)
✅ Retiro ETH exitoso → Éxito
✅ Retiro que excede limite → Falla (ExceedsLimit)
✅ Retiro sin balance → Falla (InsufficientBalance)
✅ Retiro de token no permitido → Falla (TokenNotSupported)
```

#### 3. Swaps
```solidity
✅ Swap normal → Éxito
✅ Swap con slippage alto → Falla (SlippageTooHigh)
✅ Swap con deadline expirado → Falla
✅ Swap de token no permitido → Falla
```

#### 4. Control de Acceso
```solidity
✅ Cambiar price feed como CAP_MANAGER → Éxito
✅ Cambiar price feed sin rol → Falla
✅ Pausar como PAUSE_MANAGER → Éxito
✅ Pausar sin rol → Falla
✅ Agregar token como TOKEN_MANAGER → Éxito
✅ Agregar token sin rol → Falla
```

### Pruebas de Integración

```solidity
✅ Depositar ETH → Retirar ETH → Balance correcto
✅ Depositar Token → Swap → Balance USDC correcto
✅ Múltiples depósitos de usuarios diferentes → Balances independientes
✅ Pausa → Depósito falla → Unpause → Depósito exitoso
```

### Fuzzing

```solidity
✅ Depósitos aleatorios (0 a 1000 ETH)
✅ Múltiples swaps con montos aleatorios
✅ Combinaciones de depósitos/retiros
```

### Pruebas de Gas

```
Esperado:
- deposit(): ~20,000-30,000 gas
- depositAndSwapERC20(): ~150,000-200,000 gas
- withdrawToken(): ~50,000-70,000 gas
```

---

## Consideraciones de Gas

### 1. Optimizaciones Implementadas
✅ `unchecked` en operaciones seguras  
✅ Constantes como `immutable`  
✅ Eventos indexados  
✅ Storage packing (implícito)  

### 2. Áreas de Mejora
❌ No implementado: ReentrancyGuard (pequeño costo)  
⚠️ Validación de staleness agregará ~2k gas  
⚠️ Multi-oracle validation agregará gas significativo  

### 3. Estimaciones de Gas (Sepolia)

| Función | Gas | Costo aprox (5 gwei) |
|---------|-----|----------------------|
| deposit() | 25k | $0.10 |
| depositAndSwapERC20() | 180k | $0.72 |
| withdrawToken(ETH) | 55k | $0.22 |
| withdrawToken(USDC) | 70k | $0.28 |

---

## Consideraciones de Privacidad

### 1. Información Visible On-Chain
- ✅ Todos los depósitos/retiros son visibles
- ✅ Balances por usuario son públicos
- ✅ Transacciones de swap son transparentes

### 2. Recomendaciones
- Uso de mixer para transacciones sensibles (opcional)
- Privacidad de datos del usuario depende de dirección EOA
- Considerar Privacy-Centric Wallet para interacciones

---

## Reporte de Auditoría - Plantilla

### Hallazgos Críticos
1. 🔴 [Crítico] Nombre: Descripción
   - Ubicación: línea X en archivo Y
   - Impacto: Alto/Medio/Bajo
   - Recomendación: ...

### Hallazgos Importantes
1. 🟠 [Importante] Nombre: Descripción
   - ...

### Observaciones
1. 🟡 [Observación] Nombre: Descripción
   - ...

### Resumen
- **Criticidad General:** 
- **Recomendación:** Aprobar / Rechazar / Condicionado

---

## Recursos Adicionales

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [Uniswap V2 Documentation](https://docs.uniswap.org/sdk/guides/protocol)
- [Chainlink Price Feed Docs](https://docs.chain.link/data-feeds)
- [Solidity Security Best Practices](https://solidity.readthedocs.io/en/latest/security-considerations.html)
- [Smart Contract Audit Best Practices](https://github.com/Consensys/smart-contract-best-practices)

---

**Última Actualización:** 10 de Noviembre de 2025  
**Versión:** 1.0  
**Preparado para:** Auditoría de Seguridad
