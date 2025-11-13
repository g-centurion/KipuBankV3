#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re

with open('README.md', 'r', encoding='utf-8') as f:
    content = f.read()

# Encontrar y reemplazar toda la sección Entregable TP4
pattern = r'(<a id="entregable-tp4"></a>\s*<details open>\s*<summary><h2>Entregable TP4</h2></summary>)(.*?)(</details>)'
match = re.search(pattern, content, re.DOTALL)

if match:
    new_section = '''<a id="entregable-tp4"></a>
<details open>
<summary><h2>Entregable TP4</h2></summary>

### Objetivo
Banco DeFi educativo con depósitos de ETH y ERC‑20, swap automático a USDC vía Uniswap V2, retiros con límites por transacción y validación de precios con Chainlink (staleness + desviación máxima), aplicando buenas prácticas de seguridad.

### Funcionalidades principales
- Depósitos ETH con conversión automática a USD y validación de cap global.
- Depósitos ERC‑20 con swap a USDC mediante ruta Token→WETH→USDC.
- Retiros hasta límite por transacción (ETH y USDC).
- Catálogo de tokens administrado por rol y Timelock opcional para cambios sensibles.
- Sistema de roles (admin, cap manager, pause manager, token manager) y pausa de emergencia.

### Arquitectura
- Herencia: AccessControl, Pausable, ReentrancyGuard
- Librerías: SafeERC20
- Integraciones: Uniswap V2 Router, Chainlink (ETH/USD)
- Red: Sepolia | Contrato: `0x773808318d5CE8Bc953398B4A0580e53502eAAe1`

### Interfaz pública

| Función | Rol | Descripción |
|---------|-----|-------------|
| `deposit()` | — | Acepta ETH nativo y actualiza saldo interno |
| `depositAndSwapERC20()` | — | Recibe ERC‑20 y realiza swap a USDC |
| `withdrawToken()` | — | Retira ETH o USDC respetando límites |
| `pause()` / `unpause()` | PAUSE_MANAGER | Control de emergencia |
| `setEthPriceFeedAddress()` | CAP_MANAGER | Actualiza oráculo ETH/USD |
| `addOrUpdateToken()` | TOKEN_MANAGER | Administra tokens soportados |
| `getDepositCount()` / `getWethAddress()` | — | Consultas públicas |

Eventos: `DepositSuccessful`, `WithdrawalSuccessful`

Errores personalizados: `Bank__ZeroAmount`, `Bank__DepositExceedsCap`, `Bank__WithdrawalExceedsLimit`, `Bank__InsufficientBalance`, `Bank__TokenNotSupported`, `Bank__SlippageTooHigh`, `Bank__StalePrice`, `Bank__PriceDeviation`, `Bank__TransferFailed`

### Parámetros clave
- Cap global: 1,000,000 USD (8 decimales)
- Timeout oráculo: 1 hora
- Desviación máxima: 5% (500 bps)
- Límite por retiro: configurado en constructor

### Seguridad
- Patrón CEI, ReentrancyGuard, SafeERC20
- Validación de oráculo (staleness + desviación)
- Slippage controlado en swaps
- RBAC y pausa de emergencia

Documentación de seguridad: AUDITOR_GUIDE.md y THREAT_MODEL.md

</details>'''
    
    content = content[:match.start()] + new_section + content[match.end():]
    
    with open('README.md', 'w', encoding='utf-8') as f:
        f.write(content)
    print('✓ Sección Entregable TP4 reemplazada exitosamente')
else:
    print('✗ No se encontró la sección')
