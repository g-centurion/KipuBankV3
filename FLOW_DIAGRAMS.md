# Diagramas de Flujo - KipuBankV3

Este documento contiene los diagramas completos del sistema. En el README solo se muestran los esenciales; aquí se listan los flujos extendidos y módulos administrativos.

## Índice
- [1. Flujo General del Sistema](#1-flujo-general-del-sistema)
- [2. Flujo Detallado: Depósito de ETH](#2-flujo-detallado-depósito-de-eth)
- [3. Flujo Detallado: Depósito con Swap](#3-flujo-detallado-depósito-con-swap)
- [4. Flujo Detallado: Retiro](#4-flujo-detallado-retiro)
- [5. Validación de Precios (Oracle Check)](#5-validación-de-precios-oracle-check)
- [6. Ciclo de Vida de una Transacción](#6-ciclo-de-vida-de-una-transacción)
- [7. Matriz de Validación de Entrada](#7-matriz-de-validación-de-entrada)
- [8. Manejo de Errores - Árbol de Decisión](#8-manejo-de-errores---árbol-de-decisión)
- [9. Secuencia de Seguridad: CEI Pattern](#9-secuencia-de-seguridad-cei-pattern)
- [10. Catálogo de Tokens: Alta/Actualización](#10-catálogo-de-tokens-altaactualización)
- [11. Pausa y Reanudación](#11-pausa-y-reanudación)
- [12. Gestión de Roles (AccessControl)](#12-gestión-de-roles-accesscontrol)
- [13. Timelock: Proponer, Programar y Ejecutar](#13-timelock-proponer-programar-y-ejecutar)
- [14. Verificación Límite Global (_checkBankCap)](#14-verificación-límite-global-_checkbankcap)

## 1. Flujo General del Sistema

```
┌─────────────────────────────────────────────────────────────┐
│                    USUARIO FINAL                            │
└──────────┬──────────────────────────────────────────┬───────┘
           │                                          │
           ▼                                          ▼
    ┌──────────────┐                         ┌──────────────┐
    │ Deposita ETH │                         │ Deposita ERC20
    │   (Nativo)   │                         │    Token     │
    └──────┬───────┘                         └──────┬───────┘
           │                                        │
           ▼                                        ▼
    ┌──────────────────────┐           ┌─────────────────────┐
    │ deposit()            │           │ depositAndSwapERC20 │
    │ - Validar monto      │           │ - Validar token     │
    │ - Obtener precio ETH │           │ - Transferir token  │
    │ - Validar cap        │           │ - Aprobar router    │
    │ - Acreditar balance  │           │ - Ejecutar swap     │
    │ - Emitir evento      │           │ - Validar slippage  │
    │                      │           │ - Acreditar USDC    │
    └──────────┬───────────┘           │ - Emitir evento     │
               │                        └──────┬──────────────┘
               │                               │
               └────────────────┬──────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  BALANCE ACTUALIZADO  │
                    │ en KipuBankV3         │
                    └───────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  Retira USDC/ETH      │
                    │  withdrawToken()      │
                    └────────┬──────────────┘
                             │
                             ▼
                    ┌───────────────────────┐
                    │ FONDOS A USUARIO      │
                    └───────────────────────┘
```

---

## 2. Flujo Detallado: Depósito de ETH

```
┌─ INICIO: deposit() ─────────────────────────────────────┐
│                                                         │
│  INPUT: msg.value (cantidad de ETH)                   │
│                                                         │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │ ¿msg.value > 0?      │
        └──────────┬───────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
      NO              YES (Continue)
    REVERT                   │
  (ZeroAmount)               ▼
                  ┌─────────────────────────────┐
                  │ Obtener precio ETH/USD de   │
                  │ Chainlink (_getEthPriceInUsd)
                  └──────────┬──────────────────┘
                             │
                             ▼
                  ┌─────────────────────────────┐
                  │ ¿price > 0?                 │
                  └──────────┬──────────────────┘
                             │
                  ┌──────────┴──────────┐
                  │                     │
                  ▼                     ▼
                 NO                   YES
            REVERT              (Continue)
         (TransferFailed)          │
                                   ▼
                        ┌──────────────────────────┐
                        │ Validar staleness        │
                        │ block.timestamp - updatedAt
                        │ <= PRICE_FEED_TIMEOUT    │
                        └──────────┬───────────────┘
                                   │
                        ┌──────────┴──────────┐
                        │                     │
                        ▼                     ▼
                    REVERT                  YES
                 (StalePrice)          (Continue)
                                           │
                                           ▼
                        ┌──────────────────────────────┐
                        │ Calcular USD value del       │
                        │ depósito                     │
                        │ pendingDepositUSD =          │
                        │ (msg.value * price) / 10^18 │
                        └──────────┬───────────────────┘
                                   │
                                   ▼
                        ┌──────────────────────────────┐
                        │ Obtener total bank value     │
                        │ (ETH + USDC en USD)          │
                        │ + pendingDepositUSD          │
                        └──────────┬───────────────────┘
                                   │
                                   ▼
                        ┌──────────────────────────────┐
                        │ ¿totalUsdValueIfAccepted     │
                        │  <= BANK_CAP_USD?            │
                        └──────────┬───────────────────┘
                                   │
                        ┌──────────┴──────────┐
                        │                     │
                        ▼                     ▼
                    REVERT                  YES
              (DepositExceedsCap)       (Continue)
                                           │
                                           ▼
                        ┌──────────────────────────────┐
                        │ UPDATE STATE                 │
                        │                              │
                        │ balances[msg.sender][ETH]    │
                        │  += msg.value                │
                        │                              │
                        │ _depositCount++              │
                        │ lastRecordedPrice = price    │
                        └──────────┬───────────────────┘
                                   │
                                   ▼
                        ┌──────────────────────────────┐
                        │ EMIT EVENT                   │
                        │                              │
                        │ DepositSuccessful(           │
                        │   user: msg.sender,          │
                        │   token: address(0),         │
                        │   amount: msg.value          │
                        │ )                            │
                        └──────────┬───────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │ ✓ ÉXITO                      │
                    │ Balance actualizado          │
                    │ Evento emitido              │
                    └──────────────────────────────┘
```

---

## 3. Flujo Detallado: Depósito con Swap

```
┌─ INICIO: depositAndSwapERC20() ──────────────────────────────┐
│                                                              │
│  INPUTS:                                                    │
│  - tokenIn: dirección del token                            │
│  - amountIn: cantidad del token                            │
│  - amountOutMin: mínimo USDC a recibir (slippage)          │
│  - deadline: timestamp máximo                              │
│                                                              │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────────────┐
        │ CHECKS (Fase de Validación)  │
        └──────────────────────────────┘
                   │
                   ├─── ¿tokenIn != address(0)?
                   ├─── ¿tokenIn != USDC_TOKEN?
                   ├─── ¿amountIn > 0?
                   ├─── ¿token permitido en catálogo?
                   │
                   └──► Si NO en cualquier check → REVERT
                        │
                        ▼
                   Si TODO OK → Continue
                        │
                        ▼
        ┌──────────────────────────────────────┐
        │ TRANSFER (Fase de Transferencia 1/3) │
        └──────────────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────────────────────┐
        │ safeTransferFrom(                    │
        │   token: tokenIn,                    │
        │   from: msg.sender,                  │
        │   to: address(this),                 │
        │   amount: amountIn                   │
        │ )                                    │
        └──────────────────────────────────────┘
                   │
            ¿Transfer exitoso?
            │        │
            NO       YES
            │        │
          REVERT    ▼
                   ┌─────────────────────────────┐
                   │ DETERMINAR RUTA DE SWAP     │
                   └──────────────────────────────┘
                   │
              ¿tokenIn == WETH?
              │           │
             YES          NO
              │            │
              ▼            ▼
         path = [    path = [
         WETH,       tokenIn,
         USDC        WETH,
         ]           USDC
                     ]
              │            │
              └────┬───────┘
                   │
                   ▼
        ┌──────────────────────────────┐
        │ getAmountsOut()              │
        │ (View - sin cambiar estado)  │
        │                              │
        │ Estima USDC a recibir        │
        │ amounts[] =                  │
        │ [amountIn, ..., usdcOut]     │
        └──────────┬───────────────────┘
                   │
                   ▼
        ┌──────────────────────────────┐
        │ estimatedUsdcReceived =      │
        │ amounts[amounts.length - 1]  │
        └──────────┬───────────────────┘
                   │
                   ▼
        ┌──────────────────────────────┐
        │ VALIDAR BANK CAP             │
        │ _checkBankCap(estimatedUsd)  │
        └──────────┬───────────────────┘
                   │
        ¿Cap OK?   │
            │      │
           NO      YES
            │      │
          REVERT  ▼
               ┌────────────────────────────────┐
               │ APPROVE (Interacción 2/3)      │
               │                                │
               │ safeIncreaseAllowance(         │
               │   spender: I_ROUTER,           │
               │   amount: amountIn             │
               │ )                              │
               └────────┬─────────────────────────┘
                        │
                        ▼
               ┌────────────────────────────────┐
               │ EJECUTAR SWAP (Interacción 3/3)│
               │                                │
               │ I_ROUTER.swapExactTokensFor    │
               │ Tokens(                        │
               │   amountIn,                    │
               │   amountOutMin,                │
               │   path,                        │
               │   to: address(this),           │
               │   deadline                     │
               │ )                              │
               └────────┬─────────────────────────┘
                        │
                        ▼
               ┌────────────────────────────────┐
               │ actualAmounts[] = resultado    │
               │ usdcReceived =                 │
               │ actualAmounts[length - 1]      │
               └────────┬─────────────────────────┘
                        │
                        ▼
               ┌────────────────────────────────┐
               │ ¿usdcReceived >=               │
               │  amountOutMin?                 │
               └────────┬─────────────────────────┘
                        │
                  ┌─────┴──────┐
                  │            │
                  NO           YES
                  │            │
               REVERT         ▼
            (SlippageTooHigh)
                        ┌────────────────────────────┐
                        │ UPDATE STATE               │
                        │                            │
                        │ balances[msg.sender][USDC] │
                        │ += usdcReceived            │
                        │                            │
                        │ _depositCount++            │
                        └────────┬───────────────────┘
                                 │
                                 ▼
                        ┌────────────────────────────┐
                        │ EMIT EVENT                 │
                        │                            │
                        │ DepositSuccessful(         │
                        │   msg.sender,              │
                        │   USDC_TOKEN,              │
                        │   usdcReceived             │
                        │ )                          │
                        └────────┬───────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────────────┐
                    │ ✓ ÉXITO                        │
                    │ Token swapped a USDC           │
                    │ Balance en USDC actualizado   │
                    └────────────────────────────────┘
```

---

## 4. Flujo Detallado: Retiro

```
┌─ INICIO: withdrawToken() ──────────────────────────────────┐
│                                                            │
│  INPUTS:                                                  │
│  - tokenAddress: 0x0...0 (ETH) o USDC_ADDRESS            │
│  - amountToWithdraw: cantidad a retirar                  │
│                                                            │
└──────────────────┬────────────────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────────┐
        │ ¿amountToWithdraw > 0?    │
        └──────────┬───────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        NO                   YES
        │                    │
      REVERT                ▼
     (ZeroAmount)  ┌────────────────────────────┐
                   │ ¿tokenAddress in           │
                   │ [address(0), USDC]?        │
                   └──────────┬────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
                   NO                 YES
                    │                  │
                 REVERT               ▼
            (TokenNotSupported)  ┌──────────────┐
                                 │ ¿amount <=   │
                                 │ MAX_WITH_TX? │
                                 └──────┬───────┘
                                        │
                              ┌─────────┴─────────┐
                              │                   │
                             NO                 YES
                              │                  │
                           REVERT               ▼
                        (ExceedsLimit)  ┌──────────────────┐
                                        │ userBalance =    │
                                        │ balances[user]   │
                                        │ [tokenAddress]   │
                                        └────────┬─────────┘
                                                 │
                                                 ▼
                                        ┌──────────────────┐
                                        │ ¿userBalance >=  │
                                        │  amount?         │
                                        └────────┬─────────┘
                                                 │
                                    ┌────────────┴────────────┐
                                    │                         │
                                   NO                       YES
                                    │                        │
                                 REVERT                     ▼
                              (Insufficient)     ┌──────────────────────┐
                                                 │ UPDATE STATE         │
                                                 │ (CEI Pattern)        │
                                                 │                      │
                                                 │ balances[user][addr] │
                                                 │ -= amount            │
                                                 │                      │
                                                 │ _withdrawalCount++   │
                                                 └────────┬─────────────┘
                                                          │
                                                          ▼
                                        ┌──────────────────────────┐
                                        │ TRANSFER (Interacción)   │
                                        └──────────────────────────┘
                                                          │
                            ┌─────────────────────────────┴─────────┐
                            │                                       │
                    ¿tokenAddress == ETH?                           │
                            │                                       │
                       YES   │                                    NO │
                            │                                       │
                            ▼                                       ▼
        ┌──────────────────────────┐          ┌────────────────────────────┐
        │ Transfer ETH             │          │ Transfer ERC20             │
        │ (low-level call)         │          │ (SafeERC20)                │
        │                          │          │                            │
        │ (bool success, ) =       │          │ safeTransfer(              │
        │ payable(msg.sender)      │          │   tokenAddress,            │
        │ .call{value: amount}("");│          │   msg.sender,              │
        │                          │          │   amount                   │
        │ ¿success?                │          │ )                          │
        └────────┬─────────────────┘          └────────┬───────────────────┘
                 │                                     │
        ┌────────┴─────────┐                  Transfer exitoso?
        │                  │                     │        │
       NO                 YES                   NO       YES
        │                  │                    │        │
      REVERT              ▼                  REVERT     ▼
    (TransferFailed)
               ┌──────────────────────────┐
               │ EMIT EVENT               │
               │                          │
               │ WithdrawalSuccessful(    │
               │   msg.sender,            │
               │   tokenAddress,          │
               │   amount                 │
               │ )                        │
               └────────┬─────────────────┘
                        │
                        ▼
             ┌──────────────────────────┐
             │ ✓ ÉXITO                  │
             │ Fondos transferidos      │
             │ Balance actualizado      │
             │ Evento emitido          │
             └──────────────────────────┘
```

---

## 5. Validación de Precios (Oracle Check)

```
┌─ _getEthPriceInUsd() ─────────────────────────────┐
│                                                   │
│  Obtiene precio de Chainlink con validaciones    │
│                                                   │
└───────────────────┬───────────────────────────────┘
                    │
                    ▼
        ┌─────────────────────────────┐
        │ latestRoundData() de        │
        │ Chainlink Aggregator        │
        │                             │
        │ Obtiene:                    │
        │ - price (int256)            │
        │ - timestamp                 │
        └─────────┬───────────────────┘
                  │
                  ▼
        ┌─────────────────────────────┐
        │ ¿price > 0?                 │
        └─────────┬───────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        NO                 YES
        │                  │
      REVERT              ▼
    (Transfer      ┌──────────────────────┐
     Failed)       │ Staleness Check      │
                   │                      │
                   │ timeSinceUpdate =    │
                   │ block.timestamp -    │
                   │ updatedAt            │
                   │                      │
                   │ ¿timeSinceUpdate <=  │
                   │ PRICE_FEED_TIMEOUT?  │
                   └────────┬─────────────┘
                            │
                  ┌─────────┴─────────┐
                  │                   │
                 NO                 YES
                  │                  │
               REVERT               ▼
            (StalePrice)  ┌──────────────────────┐
                          │ Price Deviation Check│
                          │                      │
                          │ ¿lastRecordedPrice > │
                          │ 0?                   │
                          │ (Primera vez?)       │
                          └────────┬─────────────┘
                                   │
                         ┌─────────┴─────────┐
                         │                   │
                        YES                 NO
                         │                  │
                         ▼                  ▼
                  ┌──────────────────┐   Skip check,
                  │ Calcular         │   actualizar
                  │ maxAllowedDiff   │   y retornar
                  │                  │
                  │ = price * 500 /  │
                  │   10000 (5%)     │
                  │                  │
                  │ ¿deviation >     │
                  │ maxAllowedDiff?  │
                  └────────┬─────────┘
                           │
                 ┌─────────┴────────┐
                 │                  │
                YES                NO
                 │                 │
              REVERT              ▼
           (PriceDeviation)  ┌──────────────────┐
                             │ Update recorded  │
                             │ price            │
                             │                  │
                             │ lastRecordedPrice
                             │ = price          │
                             │                  │
                             │ Return price     │
                             └──────────────────┘
```

---

## 6. Ciclo de Vida de una Transacción

```
                    ┌─────────────────────────┐
                    │  USUARIO EN FRONTEND    │
                    │  (Wallet conectada)     │
                    └────────────┬────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │ 1. PREPARAR TX          │
                    │                         │
                    │ - Seleccionar función  │
                    │ - Ingresarparametrros  │
                    │ - Estimar gas          │
                    └────────────┬────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │ 2. FIRMAR TX            │
                    │                         │
                    │ - Confirmación en      │
                    │   wallet               │
                    │ - Usuario revisa datos │
                    │ - Firma con clave      │
                    └────────────┬────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │ 3. ENVIAR TX A RED      │
                    │                         │
                    │ - TX en mempool         │
                    │ - Esperando minero/     │
                    │   validator             │
                    └────────────┬────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │ 4. EJECUTAR EN BLOCKCHAIN
                    │                         │
                    │ - Validar formato       │
                    │ - Ejecutar smart contract
                    │ - Actualizar estado     │
                    │ - Emitir eventos        │
                    └────────────┬────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │ 5. CONFIRMAR EN BLOQUE  │
                    │                         │
                    │ - Incluida en bloque    │
                    │ - Gas gastado           │
                    │ - Recibida confirmación │
                    └────────────┬────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │ 6. ACTUALIZAR FRONTEND  │
                    │                         │
                    │ - Escuchar eventos      │
                    │ - Actualizar UI         │
                    │ - Mostrar confirmación  │
                    └────────────┬────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │ ✓ TRANSACCIÓN COMPLETA  │
                    └─────────────────────────┘
```

---

## 7. Matriz de Validación de Entrada

```
┌─────────────────────────────────────────────────────────────┐
│                   VALIDACIONES CRÍTICAS                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ deposit()                                                   │
│  ├─ msg.value > 0                     ✓ Validado            │
│  ├─ Precio ETH > 0                    ✓ Validado            │
│  ├─ Precio no stale (< 1h)            ✓ Validado            │
│  ├─ Price deviation < 5%              ✓ Validado            │
│  └─ (current + new) <= BANK_CAP       ✓ Validado            │
│                                                              │
│ depositAndSwapERC20()                                      │
│  ├─ tokenIn != address(0)             ✓ Validado            │
│  ├─ tokenIn != USDC                   ✓ Validado            │
│  ├─ amountIn > 0                      ✓ Validado            │
│  ├─ Token permitido en catálogo       ✓ Validado            │
│  ├─ Transfer exitoso                  ✓ SafeERC20           │
│  ├─ Ruta de swap válida               ✓ Determinada         │
│  ├─ Slippage <= amountOutMin          ✓ Validado            │
│  ├─ Deadline no expirado              ✓ Validado            │
│  └─ (current + swap) <= BANK_CAP      ✓ Validado            │
│                                                              │
│ withdrawToken()                                            │
│  ├─ amountToWithdraw > 0              ✓ Validado            │
│  ├─ tokenAddress en [ETH, USDC]       ✓ Validado            │
│  ├─ amount <= MAX_WITHDRAWAL_PER_TX   ✓ Validado            │
│  ├─ userBalance >= amount             ✓ Validado            │
│  └─ Transfer exitoso                  ✓ SafeERC20/call      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. Manejo de Errores - Árbol de Decisión

```
┌─ TX Fallida ──────────────────────────────────┐
│                                               │
└───────┬─────────────────────────────────────┘
        │
        ├─ ¿CUSTOM ERROR?
        │  │
        │  ├─ Bank__ZeroAmount
        │  │   → Ingresaste 0
        │  │
        │  ├─ Bank__DepositExceedsCap
        │  │   → Supera el límite del banco
        │  │
        │  ├─ Bank__WithdrawalExceedsLimit
        │  │   → Supera límite por TX
        │  │
        │  ├─ Bank__InsufficientBalance
        │  │   → No tienes suficiente balance
        │  │
        │  ├─ Bank__SlippageTooHigh
        │  │   → El precio cambió mucho (MEV)
        │  │
        │  ├─ Bank__StalePrice
        │  │   → Precio del oráculo desactualizado
        │  │
        │  ├─ Bank__PriceDeviation
        │  │   → Precio se desvió >5%
        │  │
        │  ├─ Bank__TokenNotSupported
        │  │   → Token no permitido
        │  │
        │  ├─ Bank__InvalidTokenAddress
        │  │   → Dirección inválida
        │  │
        │  └─ Bank__TransferFailed
        │      → Error en transferencia
        │
        └─ ¿ERROR ESTÁNDAR?
           │
           ├─ Pausable.EnforcedPause
           │   → Contrato está pausado
           │
           ├─ AccessControl.AccessControlUnauthorizedAccount
           │   → No tienes permisos
           │
           ├─ ERC20InsufficientAllowance
           │   → Token no aprobado
           │
           ├─ ERC20InsufficientBalance
           │   → Balance insuficiente de token
           │
           └─ ReentrancyGuardReentrantCall
               → Reentrancia detectada
```

---

## 9. Secuencia de Seguridad: CEI Pattern

```
FUNCIÓN SEGURA (CEI - Checks Effects Interactions)

┌─ CHECKS ────────────────────────────┐
│ 1. Validar inputs                   │
│ 2. Verificar balances               │
│ 3. Verificar límites                │
│ 4. Verificar permisos               │
│ 5. Verificar estado del contrato    │
│                                      │
│ ⚠️  NO modificar estado aquí        │
│ ⚠️  NO hacer llamadas externas      │
│                                      │
│ ✓ Si falla: REVERT sin cambios      │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─ EFFECTS ───────────────────────────┐
│ 1. Actualizar balances              │
│ 2. Actualizar contadores            │
│ 3. Actualizar estado                │
│                                      │
│ ✓ TODAS las actualizaciones aquí    │
│ ✓ ANTES de interacciones externas   │
│                                      │
│ ⚠️  NO hacer llamadas externas      │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─ INTERACTIONS ──────────────────────┐
│ 1. Transferencias de tokens         │
│ 2. Llamadas a otros contratos       │
│ 3. Llamadas a Uniswap               │
│ 4. Emisión de eventos               │
│                                      │
│ ✓ Estado ya actualizado             │
│ ✓ Seguro contra reentrancia         │
│ ✓ ReentrancyGuard activo            │
└──────────────────┬──────────────────┘
                   │
                   ▼
              ✓ SEGURO
```

---

**Documentación generada:** 10 de Noviembre de 2025

---

## 10. Catálogo de Tokens: Alta/Actualización

```
┌─ addOrUpdateToken(token, priceFeed, decimals) ───────────────┐
│                                                              │
│  REQUIERE: caller tiene TOKEN_MANAGER_ROLE                  │
└───────────┬──────────────────────────────────────────────────┘
                  │
                  ▼
      ┌──────────────────────────┐
      │ ¿token != address(0)?    │
      └──────────┬───────────────┘
                      │
            ┌──────┴───────┐
            │              │
          NO             SÍ
            │              │
      REVERT       ┌─────────────────────────────┐
 (InvalidToken)  │ sTokenCatalog[token] = {    │
                         │   priceFeed, decimals,      │
                         │   isAllowed: true           │
                         │ }                           │
                         └─────────────────────────────┘
```

---

## 11. Pausa y Reanudación

```
┌─ pause() / unpause() ──────────────────────────────┐
│                                                     │
│ REQUIERE: caller tiene PAUSE_MANAGER_ROLE          │
└──────────────────┬─────────────────────────────────┘
                            │
                            ▼
             ┌─────────────────────┐
             │   _pause()/_unpause │
             └─────────────────────┘
                              │
                              ▼
                Estado pausado / activo
```

---

## 12. Gestión de Roles (AccessControl)

```
DEFAULT_ADMIN_ROLE puede:
   ├─ grantRole(X_ROLE, account)
   └─ revokeRole(X_ROLE, account)

CAP_MANAGER_ROLE:
   └─ setEthPriceFeedAddress(newFeed)

PAUSE_MANAGER_ROLE:
   ├─ pause()
   └─ unpause()

TOKEN_MANAGER_ROLE:
   └─ addOrUpdateToken(token, priceFeed, decimals)
```

---

## 13. Timelock: Proponer, Programar y Ejecutar

```
┌─ TimelockKipuBank (OZ TimelockController) ───────────────────────────┐
│ MIN_DELAY = 2 días                                                   │
├──────────────────────────────────────────────────────────────────────┤
│ 1) Propose: proposePriceFeedChange(bank, newFeed)                    │
│    └─ schedule(... setEthPriceFeedAddress(newFeed) ...)              │
│ 2) Esperar DELAY                                                     │
│ 3) Execute: executePriceFeedChange(bank, newFeed, salt)              │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 14. Verificación Límite Global (_checkBankCap)

```
┌─ _checkBankCap(pendingUsd) ──────────────────────────────────────────┐
│ total = _getBankTotalUsdValue(pendingUsd)                            │
│ ¿total <= BANK_CAP_USD?                                             │
├───────────────┬──────────────────────────────────────────────────────┤
│ NO            │ SÍ                                                   │
│               │                                                      │
│ REVERT        │ continuar                                            │
│ (DepositExceedsCap)                                                  │
└───────────────┴──────────────────────────────────────────────────────┘
```
