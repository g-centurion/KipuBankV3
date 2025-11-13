#!/usr/bin/env python3
# -*- coding: utf-8 -*-

with open('README.md', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Buscar inicio y fin de la sección
start_idx = None
end_idx = None

for i, line in enumerate(lines):
    if '<a id="entregable-tp4"></a>' in line:
        start_idx = i
    elif start_idx is not None and '</details>' in line and i > start_idx + 50:
        end_idx = i + 1  # incluir la línea </details>
        break

if start_idx and end_idx:
    print(f'Encontrado: líneas {start_idx+1} a {end_idx}')
    
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

</details>
'''
    
    # Reemplazar las líneas
    new_lines = lines[:start_idx] + [new_section] + lines[end_idx:]
    
    with open('README.md', 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    
    print(f'✓ Reemplazadas {end_idx - start_idx} líneas por nueva sección')
else:
    print('✗ No se encontró la sección completa')
    print(f'start_idx: {start_idx}, end_idx: {end_idx}')
