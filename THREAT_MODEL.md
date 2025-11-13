# Análisis de Amenazas - KipuBankV3

## Resumen Ejecutivo

- Objetivo: detallar análisis de seguridad, vulnerabilidades y mitigaciones implementadas en KipuBankV3.
- Estado: análisis previo al despliegue en producción.

**Nivel de Riesgo General:** MEDIO  
**Estado de Madurez:** PRE-PRODUCCIÓN  
**Recomendación:** Auditoría externa antes del despliegue en Mainnet

---

## 1. Arquitectura y Componentes

### 1.1 Componentes Principales

```
KipuBankV3 (Contrato Principal)
├── Integración Chainlink (Oráculos de Precios)
├── Integración Uniswap V2 (Swaps)
├── OpenZeppelin (SafeERC20, AccessControl)
└── Sistema de Almacenamiento (Balances por Usuario/Token)
```

### 1.2 Flujo de Datos Crítico

```
Usuario deposita Token ERC20
    ↓
Validación y aprobación
    ↓
Obtención de ruta de swap (TOKEN → WETH → USDC)
    ↓
Estimación de cantidad con getAmountsOut
    ↓
Validación contra BANK_CAP_USD
    ↓
Ejecución de swap en Uniswap V2
    ↓
Acreditación de USDC al balance del usuario
```

---

## 2. Vulnerabilidades Identificadas y Mitigaciones

### 2.1 Manipulación de Precios (Oracle Price Manipulation)

**Severity:** ALTA  
**CVSS Score:** 7.5

#### Descripción
Un atacante podría manipular el precio del oráculo de Chainlink para:
- Depositar más valor que el permitido (bypass de BANK_CAP)
- Retirar más USDC del que debería ser permitido
- Explotar diferencias de precio

#### Escenarios de Ataque
1. **Manipulación de Chainlink Feed:**
   - Si el deployer usa un feed inválido o comprometido
   - Chainlink se vuelve inaccesible

2. **Flash Loan Attack (Indirecto):**
   - No aplicable directamente a precios de Chainlink
   - Posible si se implementan feeds alternativos

#### Mitigaciones Implementadas
✅ **Chainlink Feeds Oficiales**
- Uso de feeds verificados de Chainlink
- Solo en Sepolia y Mainnet

✅ **Validación de Precios**
```solidity
if (price <= 0) {
    revert Bank__TransferFailed();
}
```

✅ **Slippage Protection**
```solidity
if (usdcReceived < amountOutMin) {
    revert Bank__SlippageTooHigh();
}
```

✅ **Deadlines en Swaps**
```solidity
I_ROUTER.swapExactTokensForTokens(
    ...
    deadline  // Previene transacciones retrasadas
);
```

#### Mitigaciones Recomendadas
❌ **A Implementar Antes de Producción:**
1. **Validación de Staleness**
   ```solidity
   uint256 PRICE_FEED_TIMEOUT = 1 hours;
   require(block.timestamp - updatedAt <= PRICE_FEED_TIMEOUT);
   ```

2. **Multi-Oracle Strategy**
   - Implementar validación con múltiples feeds
   - Comparar con TWAP de Uniswap V3

3. **Pausabilidad de Emergencia**
   - Pausar depósitos si hay anomalía en precios
   - Sistema de alertas

---

### 2.2 Reentrancy (Re-entrada)

**Severity:** ALTA  
**CVSS Score:** 8.0

#### Descripción
Un atacante podría explotar llamadas externas para reentrarse en funciones críticas.

#### Escenarios de Ataque
1. **Reentrancy en depositAndSwapERC20:**
   - Token malicioso hace transferencia de retorno a KipuBankV3
   - Reentra en la función antes de actualizar el balance

#### Mitigaciones Implementadas
✅ **Checks-Effects-Interactions Pattern (CEI)**
```solidity
// CHECKS
if (!sTokenCatalog[tokenIn].isAllowed) revert Bank__TokenNotSupported();

// EFFECTS (Estado actualizado ANTES de interacciones)
balances[msg.sender][USDC_TOKEN] += usdcReceived;

// INTERACTIONS (Último, después de actualizar estado)
emit DepositSuccessful(msg.sender, USDC_TOKEN, usdcReceived);
```

✅ **SafeERC20 para Transferencias**
```solidity
IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
```

✅ **Validación de Resultado del Swap**
```solidity
uint256 usdcReceived = actualAmounts[actualAmounts.length - 1];
if (usdcReceived < amountOutMin) {
    revert Bank__SlippageTooHigh();
}
```

#### Mitigaciones Recomendadas
❌ **A Implementar:**
1. **ReentrancyGuard de OpenZeppelin**
   ```solidity
   import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
   
   contract KipuBankV3 is AccessControl, Pausable, ReentrancyGuard {
       function depositAndSwapERC20(...) external nonReentrant {
           // ...
       }
   }
   ```

2. **Mutex Pattern**
   ```solidity
   bool private _locked;
   
   modifier noReentrant() {
       require(!_locked, "No reentrancy");
       _locked = true;
       _;
       _locked = false;
   }
   ```

---

### 2.3 Overflow/Underflow (Arithmetic Issues)

**Severity:** MEDIA  
**CVSS Score:** 6.5

#### Descripción
Aunque Solidity 0.8+ tiene protección automática, existen casos donde `unchecked` podría causar problemas.

#### Ubicaciones de Riesgo
1. **Cálculos en `_getUsdValueFromWei`**
   ```solidity
   return (ethAmount * ethPriceUsd) / 10 ** 18;
   ```

2. **Actualización de balances**
   ```solidity
   balances[msg.sender][USDC_TOKEN] += usdcReceived;  // Podría overflow
   ```

#### Mitigaciones Implementadas
✅ **Solidity 0.8.30 (Overflow Protection Built-in)**

✅ **unchecked Solo en Contextos Seguros**
```solidity
unchecked {
    // Safe porque ya validamos: userBalance >= amountToWithdraw
    balances[msg.sender][tokenAddress] = userBalance - amountToWithdraw;
}
```

✅ **Validaciones Previas**
```solidity
if (totalUsdValueIfAccepted > BANK_CAP_USD) {
    revert Bank__DepositExceedsCap(...);
}
```

#### Mitigaciones Recomendadas
✅ **Implementado:**
1. SafeMath (implicit en Solidity 0.8+)
2. Validaciones de límites superiores
3. Uso conservador de `unchecked`

---

### 2.4 Token Malicioso (Malicious Token Attack)

**Severity:** MEDIA  
**CVSS Score:** 6.0

#### Descripción
Un atacante podría registrar un token ERC20 malicioso que:
- Revierte en `transferFrom` bajo ciertas condiciones
- Cobra fees en cada transferencia
- Tiene lógica reentrante en `transfer`

#### Escenarios de Ataque
1. **Token con transferencia condicional**
2. **Token que se modifica durante transacción**
3. **Token que cobra comisiones**

#### Mitigaciones Implementadas
✅ **SafeERC20 para Manejo Seguro**
```solidity
IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
```

✅ **Validación de Tokens Permitidos**
```solidity
if (!sTokenCatalog[tokenIn].isAllowed) revert Bank__TokenNotSupported();
```

✅ **Control de Acceso en addOrUpdateToken**
```solidity
function addOrUpdateToken(...)
    external 
    onlyRole(TOKEN_MANAGER_ROLE)
```

#### Mitigaciones Recomendadas
❌ **A Implementar:**
1. **Lista Blanca de Tokens (Whitelist)**
   ```solidity
   mapping(address => bool) private whitelist;
   
   modifier onlyWhitelisted(address token) {
       require(whitelist[token], "Token not whitelisted");
       _;
   }
   ```

2. **Verificación de Interfaz ERC20**
   ```solidity
   require(token.code.length > 0, "Not a contract");
   ```

3. **Auditoría Manual de Tokens Nuevos**

---

### 2.5 Front-Running (MEV)

**Severity:** MEDIA  
**CVSS Score:** 5.8

#### Descripción
Un atacante en la red (Searcher/Validator) podría:
- Ver transacción pendiente en mempool
- Insertar su propia transacción delante (front-run)
- Manipular precios de Uniswap antes del swap del usuario

#### Escenarios de Ataque
1. **Front-run de Depósito**
   - Atacante compra mucho del token
   - Sube el precio en Uniswap
   - Usuario recibe menos USDC

2. **Back-run de Depósito**
   - Atacante vende el token después
   - Usuario pierde valor

#### Mitigaciones Implementadas
✅ **Deadline en Swaps**
```solidity
I_ROUTER.swapExactTokensForTokens(
    ...
    deadline  // Transacción invalida si se demora
);
```

✅ **amountOutMin (Slippage Protection)**
```solidity
uint256[] memory actualAmounts = I_ROUTER.swapExactTokensForTokens(
    amountIn,
    amountOutMin,  // Mínimo USDC a recibir
    path,
    address(this),
    deadline
);
```

#### Mitigaciones Recomendadas
❌ **A Implementar:**
1. **MEV-Resistant Router**
   - Usar Cowswap o 1inch Fusion para swap
   - Orderflow auctions

2. **Slippage Dinámico**
   ```solidity
   uint256 expectedAmount = getExpectedAmount(...);
   uint256 minAmount = (expectedAmount * 95) / 100; // 5% slippage
   ```

3. **Encrypted Mempools**
   - Usar MEV-burn o threshold encryption

---

### 2.6 Gestión de Aprobaciones (Approval Vulnerabilities)

**Severity:** MEDIA  
**CVSS Score:** 5.5

#### Descripción
Riesgo de doble gasto o aprobaciones exageradas a terceros.

#### Escenarios de Ataque
1. **Aprobación No Reseteada**
   - Después del swap, la aprobación permanece
   - Uniswap router podría gastar más tokens

2. **Race Condition en Aprobación**
   - Usuario autoriza cantidad X
   - Antes de que llegue TX, cambia a Y
   - Potencial doble gasto

#### Mitigaciones Implementadas
✅ **SafeERC20 con Aumento de Allowance**
```solidity
IERC20(tokenIn).safeIncreaseAllowance(address(I_ROUTER), amountIn);
```

✅ **Allowance Exacto**
- No aprobamos más de lo necesario
- El router solo toma exactamente lo necesario

#### Mitigaciones Recomendadas
✅ **Implementado parcialmente:**
1. **Reset de Allowance Post-Swap**
   ```solidity
   // Opcionalmente, resetear después del swap:
   // IERC20(tokenIn).safeApprove(address(I_ROUTER), 0);
   ```

2. **Usar permit() si disponible**
   ```solidity
   // Para tokens que soporten permit (EIP-2612)
   // Evita double approval
   ```

---

### 2.7 Problemas de Oráculos (Oracle Issues)

**Severity:** ALTA  
**CVSS Score:** 7.2

#### Descripción
Dependencia de Chainlink como única fuente de verdad para precios.

#### Escenarios de Ataque
1. **Chainlink Feed Desactualizado**
   - Feed no se actualiza por X horas
   - Precio stale es usado para validaciones

2. **Chainlink Feed Caido**
   - Feed retorna precio 0 o negativo
   - Transacciones fallan o se comportan erráticamente

3. **Cambio de Feed no Comunicado**
   - Admin actualiza feed a uno malicioso

#### Mitigaciones Implementadas
✅ **Validación de Precio Positivo**
```solidity
if (price <= 0) {
    revert Bank__TransferFailed();
}
```

✅ **Control de Acceso en Cambio de Feed**
```solidity
function setEthPriceFeedAddress(address newAddress) 
    external 
    onlyRole(CAP_MANAGER_ROLE)
```

✅ **Error Explícito**
```solidity
error Bank__TransferFailed();
```

#### Mitigaciones Recomendadas
❌ **CRÍTICO - A Implementar:**
1. **Validación de Staleness**
   ```solidity
   (uint80 roundID, int256 price, , uint256 updatedAt, ) = sEthPriceFeed.latestRoundData();
   
   require(block.timestamp - updatedAt <= PRICE_FEED_TIMEOUT, "Price feed stale");
   require(price > 0, "Invalid price");
   require(roundID > lastRoundID, "Oracle price is repeated");
   ```

2. **TWAP Alternativo**
   ```solidity
   // Usar Uniswap V3 TWAP como validación
   uint256 uniswapPrice = getUniswapTWAP();
   require(
       price > uniswapPrice * 95 / 100 && 
       price < uniswapPrice * 105 / 100,
       "Price deviation too high"
   );
   ```

3. **Circuit Breaker**
   ```solidity
   if (priceDeviation > MAX_DEVIATION) {
       pause();
       emit PriceFeedAnomalyDetected();
   }
   ```

---

### 2.8 Gestión de Roles (Access Control Issues)

**Severity:** MEDIA  
**CVSS Score:** 6.3

#### Descripción
Riesgos en el control de acceso y gestión de roles.

#### Escenarios de Ataque
1. **Compromiso de Cuenta Admin**
   - Admin malicioso o comprometido
   - Pausa el contrato indefinidamente
   - Cambia feed de precios a uno malicioso

2. **Falta de Transferencia de Admin**
   - Admin no puede ser reemplazado
   - Contrato queda "congelado"

3. **Revocación de Roles Sin Previo Aviso**

#### Mitigaciones Implementadas
✅ **AccessControl de OpenZeppelin**
```solidity
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract KipuBankV3 is AccessControl {
    bytes32 public constant CAP_MANAGER_ROLE = keccak256("CAP_MANAGER_ROLE");
}
```

✅ **Roles Separados por Responsabilidad**
- `DEFAULT_ADMIN_ROLE`: Administración de roles
- `CAP_MANAGER_ROLE`: Gestión de cap y feeds
- `PAUSE_MANAGER_ROLE`: Pausa de emergencia
- `TOKEN_MANAGER_ROLE`: Registro de tokens

✅ **Verificación de Roles en Funciones Críticas**
```solidity
function pause() external onlyRole(PAUSE_MANAGER_ROLE) {
    _pause();
}
```

#### Mitigaciones Recomendadas
❌ **A Implementar:**
1. **Ownable2Step**
   ```solidity
   import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
   
   contract KipuBankV3 is Ownable2Step {
       // Permite transferencia de admin en dos pasos
   }
   ```

2. **Timelock para Cambios Críticos**
   ```solidity
   import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
   
   // Todos los cambios críticos requieren espera de X días
   ```

3. **Multi-sig para Admin**
   - Usar Gnosis Safe u otro multi-sig
   - Requiere múltiples firmas para cambios

---

## 3. Escenarios Críticos No Cubiertos

### 3.1 Falta de ReentrancyGuard Explícito
**Riesgo:** ALTO

Aunque implementamos CEI pattern, la adición de `ReentrancyGuard` de OpenZeppelin sería una capa de defensa adicional.

**Solución:** Agregar `nonReentrant` modifier.

### 3.2 Validación de Staleness de Precio
**Riesgo:** ALTO

El contrato no valida si el precio del oráculo está desactualizado.

**Solución:** Agregar validación de timestamp.

### 3.3 Falta de Pausabilidad Granular
**Riesgo:** MEDIO

Solo se pausa todo el contrato, no funciones específicas.

**Solución:** Implementar pausas por tipo de función.

### 3.4 Límite de Gas (Gas Limit Issues)
**Riesgo:** MEDIO

Swaps en Uniswap podrían consumir mucho gas si hay mucho slippage.

**Solución:** Establecer límite máximo de gas para swaps.

---

## 4. Pasos para Alcanzar Madurez del Protocolo

### FASE 1: Pre-Auditoría (ACTUAL)
- [x] Implementación básica
- [x] Pruebas unitarias (50%+ cobertura)
- [x] Documentación
- [ ] **FALTA: Implementar ReentrancyGuard**
- [ ] **FALTA: Validación de staleness de precios**

### FASE 2: Auditoría Externa (RECOMENDADO)
- [ ] Auditoría de seguridad por firma especializada
- [ ] Fuzzing exhaustivo
- [ ] Testing en testnet con datos reales

### FASE 3: Despliegue en Testnet
- [ ] Desplegar en Sepolia
- [ ] Pruebas de integración con Uniswap V2 real
- [ ] Monitoreo de eventos

### FASE 4: Mejoras Post-Auditoría
- [ ] Implementación de Timelock
- [ ] Integración de multi-sig
- [ ] Sistema de alertas y monitoreo

### FASE 5: Despliegue en Producción
- [ ] Despliegue en Mainnet
- [ ] Liquidez inicial en mercados
- [ ] Monitoreo 24/7

---

## 5. Checklist de Seguridad para Auditor

### Validaciones a Realizar

- [ ] Verificar todos los custom errors y mensajes
- [ ] Confirmar que CEI pattern se sigue en todas las funciones
- [ ] Validar uso de SafeERC20 en todas las transferencias
- [ ] Revisar cálculos de USD en `_getUsdValueFromWei` y `_getUsdValueFromUsdc`
- [ ] Verificar rutas de swap en Uniswap
- [ ] Validar límites de BANK_CAP_USD
- [ ] Revisar manejo de deadlines en swaps
- [ ] Validar slippage protection
- [ ] Verificar acceso basado en roles
- [ ] Validar que no hay transferencias ETH inseguras (usar `call` correctamente)
- [ ] Revisar evento emissions en ubicaciones críticas
- [ ] Verificar que los mocks en tests reflejan comportamiento real
- [ ] Validar que no hay delegatecall innecesario
- [ ] Revisar inicialización de estado en constructor
- [ ] Verificar que constantes están marcadas como `immutable`

---

## 6. Recomendaciones Finales

### ALTA PRIORIDAD (Antes de Producción)
1. ✅ **Agregar ReentrancyGuard**
2. ✅ **Implementar validación de staleness en oráculos**
3. ✅ **Agregar TWAP de Uniswap V3 como validación**

### MEDIA PRIORIDAD (Para Mejora Continua)
4. ⚠️ **Implementar Timelock para cambios críticos**
5. ⚠️ **Pasar a Ownable2Step**
6. ⚠️ **Agregar pausas granulares por función**

### BAJA PRIORIDAD (Futuro)
7. ℹ️ **Integración con Governance Token**
8. ℹ️ **Sistema de comisiones dinámicas**
9. ℹ️ **Soporte para swaps en Uniswap V3**

---

## 7. Referencias

- [OpenZeppelin Security Best Practices](https://docs.openzeppelin.com/contracts/4.x/security)
- [Chainlink Price Feed Best Practices](https://docs.chain.link/docs/data-feeds/price-feeds/addresses/)
- [Uniswap V2 Security](https://uniswap.org/docs/v2/smart-contracts/)
- [Smart Contract Audit Checklist](https://github.com/Consensys/smart-contract-best-practices)

---

**Documento Generado:** 10 de Noviembre de 2025  
**Versión:** 1.0  
**Autor:** KipuBank V3 Security Team  
**Estado:** DRAFT - Requiere revisión y actualización post-auditoría
