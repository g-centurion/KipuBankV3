<div align="center">

# 🏦 KipuBankV3_TP4 – Banco DeFi Educativo con Swaps y Oráculos
## Trabajo Práctico Nº 4 – Solidity Avanzado

**Estado:** ✅ Completado y verificado en Sepolia  
**Contrato:** `0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7`  
**Tx Hash:** `0x403dd8a522806960ef682142215a9f0e9d3251ce4e919f170d02e3539cda0e71`  
**Etherscan:** https://sepolia.etherscan.io/address/0x5b7f2f853adf9730fba307dc2bd2b19ff51fcdd7#code  
**Blockscout:** (puede demorar indexación) https://sepolia.blockscout.com/address/0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7  

</div>

---

## 📑 Índice Rápido
- [Resumen Ejecutivo](#-resumen-ejecutivo)
- [Guía de Uso](#-guía-de-uso-rápida)
- [Interacción On-Chain (Foundry / cast)](#-interacción-on-chain-foundry--cast)
- [Arquitectura y Diseño](#-arquitectura-y-diseño)
- [Diagramas (Mermaid)](#-diagramas-mermaid)
- [Seguridad y Buenas Prácticas](#-seguridad-y-buenas-prácticas)
- [Gas y Optimización](#-gas-y-optimizaciones)
- [Roles y Control de Acceso](#-roles-y-control-de-acceso)
- [Errores Personalizados](#-errores-personalizados)
- [Pruebas y Cobertura](#-pruebas-y-cobertura)
- [Decisiones de Diseño Explicadas para Principiantes](#-decisiones-de-diseño-explicadas-para-principiantes)
- [Deploy y Verificación](#-deploy-y-verificación)
- [Entrega para Profesor](#-entrega-para-profesor)

---

## 🎯 Resumen Ejecutivo
KipuBankV3_TP4 es un contrato educativo DeFi que permite:
1. Depósitos de ETH nativo.  
2. Depósitos de cualquier ERC-20 soportado con swap automático a USDC vía Uniswap V2.  
3. Retiros controlados con límite por transacción.  
4. Validación de precios Chainlink con chequeos de staleness y desviación (circuit breaker).  
5. Protección CEI, ReentrancyGuard, Custom Errors y Slippage.  
6. Catálogo de tokens extensible y roles RBAC para administración segura.  

> Objetivo pedagógico: Mostrar una integración completa (tokens + oráculos + DEX + seguridad) siguiendo buenas prácticas profesionales.

---

## 🧪 Pruebas y Cobertura
| Métrica | Valor |
<div align="center">

# 🏦 KipuBankV3_TP4 – Banco DeFi con Swaps y Oráculos
<strong>Contrato desplegado en Sepolia</strong>

<sub>
Contrato: <code>0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7</code> ·
Tx: <code>0x403dd8a522806960ef682142215a9f0e9d3251ce4e919f170d02e3539cda0e71</code> ·
<a href="https://sepolia.etherscan.io/address/0x5b7f2f853adf9730fba307dc2bd2b19ff51fcdd7#code">Etherscan</a> ·
<a href="https://sepolia.blockscout.com/address/0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7">Blockscout</a>
</sub>

</div>

---

## 📑 Índice
- [Resumen ejecutivo](#-resumen-ejecutivo)
- [Características principales](#-características-principales)
- [Especificaciones técnicas](#-especificaciones-técnicas)
- [Integraciones DeFi](#-integraciones-defi)
- [Diagramas esenciales](#-diagramas-esenciales)
- [Instalación y uso](#-instalación-y-uso)
- [Interacción on-chain (cast)](#-interacción-on-chain-cast)
- [Testing y cobertura](#-testing-y-cobertura)
- [Deploy y verificación](#-deploy-y-verificación)
- [Gas y optimizaciones](#-gas-y-optimizaciones)
- [Roles y control de acceso](#-roles-y-control-de-acceso)
- [Errores personalizados](#-errores-personalizados)
- [Limitaciones y roadmap](#-limitaciones-y-roadmap)
- [Licencia](#-licencia)

---

## 🎯 Resumen ejecutivo
KipuBankV3 es un contrato DeFi educativo que admite depósitos de ETH y ERC-20 (con swap automático a USDC), retiros con límites por transacción y validaciones robustas vía Chainlink. Integra seguridad basada en CEI, ReentrancyGuard, Pausable, AccessControl y errores personalizados.

---

## 🧩 Características principales
- Depósitos: ETH nativo y ERC-20 con conversión a USDC mediante Uniswap V2.
- Contabilidad multi‑token con saldos internos por usuario.
- Límite global de banco en USD y tope de retiro por transacción.
- Validación de oráculo: staleness y desviación máxima (circuit breaker).
- RBAC con roles separados y modo de pausa de emergencia.
- Timelock opcional (`TimelockKipuBank.sol`) para cambios administrativos diferidos.

---

## 🧠 Especificaciones técnicas

### Arquitectura (herencia, librerías e interfaces)
- Herencia: `AccessControl`, `Pausable`, `ReentrancyGuard`.
- Librerías: `SafeERC20`.
- Interfaces: `IERC20`, `IUniswapV2Router02`, `AggregatorV3Interface`.

### Constantes y parámetros
- `BANK_CAP_USD = 1,000,000 * 1e8` (USD, 8 dec)
- `PRICE_FEED_TIMEOUT = 1 hours`
- `MAX_PRICE_DEVIATION_BPS = 500` (5%)
- `MAX_WITHDRAWAL_PER_TX` (immutable, se define en el constructor)

### Módulos funcionales (TPs previos + TP4)
- Depósitos ETH: `deposit()` con validación de precio y cap.
- Depósitos ERC-20 con swap: `depositAndSwapERC20()` (ruta Token→WETH→USDC; o WETH→USDC).
- Retiros: `withdrawToken(address token, uint256 amount)` (ETH o USDC).
- Oráculos: `_getEthPriceInUsd()`, `_updateRecordedPrice()`.
- Conversión USD: `_getUsdValueFromWei()`, `_getUsdValueFromUsdc()`.
- Límite global: `_checkBankCap()` + `_getBankTotalUsdValue()`.
- Métricas: `getDepositCount()`, contadores internos.

### Tokens soportados y catálogo
- Base: ETH (address(0)) y USDC (6 dec) habilitados en constructor.
- Extensión: `addOrUpdateToken(token, priceFeed, decimals)` bajo `TOKEN_MANAGER_ROLE`.

### Timelock opcional
- [`src/TimelockKipuBank.sol`](src/TimelockKipuBank.sol) (basado en `TimelockController` de OZ): permite programar y ejecutar cambios (p. ej., `setEthPriceFeedAddress`) con delay mínimo de 2 días.

---

## 🔗 Integraciones DeFi
- Uniswap V2 Router: estimaciones con `getAmountsOut`, swap con `swapExactTokensForTokens` y ruta por WETH.
- Chainlink: `latestRoundData()` para ETH/USD; validación de staleness y desviación contra `lastRecordedPrice`.

---

## 🗺 Diagramas esenciales
Se muestran los flujos clave. Los diagramas de mayor detalle (incluyendo árboles de decisión y matrices) están en [FLOW_DIAGRAMS.md](FLOW_DIAGRAMS.md).

<details><summary><strong>Flujo general</strong></summary>

```mermaid
graph LR
   A[Usuario] --> B{Deposita}
   B -->|ETH| C[deposit]
   B -->|ERC20| D[depositAndSwapERC20]
   C --> E[Validar precio + cap]
   D --> F[Transfer + getAmountsOut + cap]
   E --> G[Actualizar saldo]
   F --> H[Swap a USDC]
   G --> I[Evento DepositSuccessful]
   H --> I
   I --> J{Retiro}
   J -->|ETH/USDC| K[withdrawToken]
   K --> L[Transfer + Evento]
```
</details>

<details><summary><strong>Depósito ETH</strong></summary>

```mermaid
sequenceDiagram
   participant U as Usuario
   participant C as Contrato
   participant O as Chainlink
   U->>C: deposit(value)
   C->>O: latestRoundData()
   O-->>C: price, updatedAt
   C->>C: validar staleness y desviación
   C->>C: calcular USD y comparar cap
   C->>C: actualizar balances
   C-->>U: evento DepositSuccessful
```
</details>

<details><summary><strong>Retiro</strong></summary>

```mermaid
flowchart TD
   A[withdrawToken] --> B{amount > 0?}
   B -->|No| R[REVERT ZeroAmount]
   B -->|Sí| C{token soportado?}
   C -->|No| S[REVERT TokenNotSupported]
   C -->|Sí| D{<= MAX_WITHDRAWAL?}
   D -->|No| T[REVERT WithdrawalExceedsLimit]
   D -->|Sí| E{balance suficiente?}
   E -->|No| U[REVERT InsufficientBalance]
   E -->|Sí| F[Update balance]
   F --> G{ETH?}
   G -->|Sí| H[call value]
   G -->|No| I[SafeERC20.transfer]
   H --> J[Emitir evento]
   I --> J[Emitir evento]
```
</details>

> Más diagramas, incluyendo validación de oráculo, catálogo de tokens, roles, pausa y timelock: ver [FLOW_DIAGRAMS.md](FLOW_DIAGRAMS.md).

---

## 🛠 Instalación y uso
```bash
git clone https://github.com/g-centurion/KipuBankV3_TP4.git
cd KipuBankV3_TP4
forge install
```

Configurar `.env` (no commitear):
```bash
PRIVATE_KEY=0xTUCLAVE
RPC_URL_SEPOLIA=https://eth-sepolia.g.alchemy.com/v2/TU_RPC_KEY
ETHERSCAN_API_KEY=TU_KEY
```

Compilar y probar:
```bash
forge build
forge test -vv
forge coverage
```

### Script de interacción (dry‑run)
Archivo: `script/Interact.s.sol`
```bash
source .env
forge script script/Interact.s.sol:InteractScript --rpc-url $RPC_URL_SEPOLIA -vvvv --dry-run
```

---

## 🔄 Interacción on-chain (cast)
```bash
# Max withdrawal
cast call 0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7 "MAX_WITHDRAWAL_PER_TX()(uint256)" --rpc-url $RPC_URL_SEPOLIA

# Router
cast call 0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7 "I_ROUTER()(address)" --rpc-url $RPC_URL_SEPOLIA

# Ver rol admin
cast call 0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7 "hasRole(bytes32,address)(bool)" \
   0x0000000000000000000000000000000000000000000000000000000000000000 0xe7Bc10cbDA9e4830921384C49B9E711d48b0E8C2 \
   --rpc-url $RPC_URL_SEPOLIA
```

---

## 🧪 Testing y cobertura
- Framework: Foundry (forge-std/Test).
- Tipos de pruebas: unitarias, integración (router/oráculo mocked), fuzzing, eventos, control de acceso y escenarios multi‑usuario.

### Resumen de resultados
| Métrica | Valor |
|--------|-------|
| Tests passing | 47 / 47 |
| Cobertura global (líneas) | 73.04% |
| `KipuBankV3_TP4.sol` (líneas) | 89.38% |
| Branches | 69.70% |
| Functions | 69.23% |

```mermaid
pie
   title Cobertura Global (líneas)
   "Cubierto" : 73.04
   "No cubierto" : 26.96
```

#### Cobertura por archivo (líneas)

| Archivo | Cobertura |
|---------|-----------|
| `src/KipuBankV3_TP4.sol` | 89.38% |
| `test/KipuBankV3Test.sol` | 81.36% |

### Áreas cubiertas por los tests
- Depósito de ETH y validación de cap y precio.
- Swap ERC‑20→USDC con slippage mínimo y ruta WETH.
- Retiro con límites y manejo de errores personalizados.
- Pausa/despausa y verificación de roles (grant/revoke, unauthorized).
- Fuzzing de montos y secuencias de operaciones.
- Emisión de eventos y contadores (`getDepositCount`).

### Generar reporte HTML de cobertura (opcional, local)
```bash
forge coverage --report lcov
sudo apt-get install -y lcov
genhtml -o coverage-html lcov.info
```

---

## 🚀 Deploy y verificación
```bash
source .env
forge script script/Deploy.s.sol:DeployScript \
   --rpc-url $RPC_URL_SEPOLIA \
   --broadcast \
   --verify \
   --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
```
Resultado: contrato desplegado y verificado en Sepolia.

---

## ⛽ Gas y optimizaciones
- `constant`/`immutable` para reducir SLOAD.
- Errores personalizados en lugar de strings.
- `unchecked` en incrementos con pre‑checks.
- Una sola lectura de oráculo por función.
- Reutilización de memoria en rutas de swap.

---

## 👥 Roles y control de acceso
| Rol | Propósito |
|-----|-----------|
| DEFAULT_ADMIN_ROLE | Gestión total y asignación de roles |
| CAP_MANAGER_ROLE | Cambios de feed/params de riesgo |
| PAUSE_MANAGER_ROLE | `pause` / `unpause` |
| TOKEN_MANAGER_ROLE | Alta/actualización de tokens soportados |

---

## ❌ Errores personalizados
| Error | Contexto |
|-------|----------|
| Bank__ZeroAmount | Entradas numéricas vacías |
| Bank__DepositExceedsCap | Bank cap excedido |
| Bank__WithdrawalExceedsLimit | Límite por TX superado |
| Bank__InsufficientBalance | Saldo insuficiente |
| Bank__TokenNotSupported | Token fuera de catálogo |
| Bank__SlippageTooHigh | Resultado < mínimo esperado |
| Bank__StalePrice | Oráculo desactualizado > TIMEOUT |
| Bank__PriceDeviation | Desviación > tolerancia |
| Bank__TransferFailed | Fallo de transferencia |

---

## 🚧 Limitaciones y roadmap
| Área | Limitación |
|------|------------|
| Oráculos | Solo ETH/USD (sin TWAP/multi‑feed) |
| Swaps | Ruta fija Token→WETH→USDC |
| Gobernanza | Timelock opcional, sin multisig |
| Auditoría | Slither debe ejecutarse localmente |
| Tests | Faltan stress tests de gas/MEV |

Siguientes mejoras sugeridas: integrar multisig + timelock, TWAP/multi‑oracle, módulos de estrategia y CI con cobertura y Slither.

---

## 📜 Licencia
MIT

<sub>Última actualización: 12 Nov 2025</sub>


---


