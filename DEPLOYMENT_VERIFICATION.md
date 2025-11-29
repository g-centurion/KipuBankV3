# Reporte de Verificación de Despliegue KipuBankV3 v3

**Fecha de verificación**: 29 de noviembre de 2025  
**Versión del contrato**: v3 (con NatSpec completo)  
**Red**: Sepolia Testnet

---

## Información del Despliegue

| Parámetro | Valor |
|-----------|-------|
| **Dirección del contrato** | `0xc6d24cBbF2CCC70ef6E4EeD507fEA0F801321691` |
| **Transacción de deploy** | `0x9e01b146c4fdcb3ff2968efe6ccbd34ddeeabfee4007a28be88b8128676ca409` |
| **Etherscan** | https://sepolia.etherscan.io/address/0xc6d24cBbF2CCC70ef6E4EeD507fEA0F801321691#code |
| **Blockscout** | https://eth-sepolia.blockscout.com/address/0xc6d24cBbF2CCC70ef6E4EeD507fEA0F801321691 |
| **Verificación en exploradores** | ✅ Código fuente verificado en ambos |

---

## Parámetros del Contrato On-Chain

### Immutables (Constructor)
| Parámetro | Valor Esperado | Valor On-Chain | Estado |
|-----------|---------------|----------------|--------|
| `MAX_WITHDRAWAL_PER_TX` | 1 ether (1e18) | `1000000000000000000` | ✅ Correcto |
| `I_ROUTER` | 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3 | 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3 | ✅ Correcto |
| `USDC_TOKEN` | 0x1c7D4B196Cb0C6B364C3d6eB8F0708a9dA00375D | 0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D | ✅ Correcto |
| `WETH_TOKEN` | (detectado del router) | 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14 | ✅ Correcto |

### Constantes
| Parámetro | Valor Esperado | Valor On-Chain | Estado |
|-----------|---------------|----------------|--------|
| `BANK_CAP_USD` | 1,000,000 USD (1e14) | `100000000000000` | ✅ Correcto |
| `PRICE_FEED_TIMEOUT` | 3 horas (10800 seg) | `10800` | ✅ Correcto |
| `MAX_PRICE_DEVIATION_BPS` | 5% (500 bps) | `500` | ✅ Correcto |

---

## Verificación de Tests

| Métrica | Resultado |
|---------|-----------|
| **Total de tests** | 43/43 |
| **Tests pasados** | ✅ 43 (100%) |
| **Tests fallidos** | 0 |
| **Suite** | test/KipuBankV3.t.sol:KipuBankV3Test |

### Áreas cubiertas
- ✅ Depósito de ETH con validación de cap y precio
- ✅ Swap ERC-20→USDC con slippage mínimo
- ✅ Retiro con límites y errores personalizados
- ✅ Pausa/despausa y verificación de roles
- ✅ Fuzzing de montos y secuencias
- ✅ Emisión de eventos y contadores

---

## Cobertura de Código

| Archivo | Líneas | Funciones | Branches |
|---------|--------|-----------|----------|
| `src/KipuBankV3.sol` | 90.4% (104/115) | 90.9% (20/22) | 65.0% (13/20) |
| **Global** | 67.3% (152/226) | 71.1% (32/45) | 67.7% (21/31) |

---

## Verificación de Compilación

| Aspecto | Estado |
|---------|--------|
| **Compilador** | Solidity 0.8.30 ✅ |
| **Tamaño del contrato** | ~13.2 KB (bajo límite de 24 KB) ✅ |
| **Optimizaciones** | Activadas ✅ |
| **Warnings** | Ninguno crítico ✅ |

---

## Verificación de Código Fuente

### Bytecode
- **Bytecode local (template)**: ~26,400 caracteres
- **Bytecode on-chain (deployed)**: ~26,450 caracteres
- **Diferencia**: ~50 caracteres (consistente con valores de immutables)
- **Estado**: ✅ Coincidente (diferencias esperadas por immutables)

### Archivos actualizados
- ✅ `script/Deploy.s.sol` - direcciones Sepolia correctas
- ✅ `script/Interact.s.sol` - dirección v2 actualizada
- ✅ `README.md` - dirección y TX de deploy correctas
- ✅ `src/KipuBankV3.sol` - timeout 3h, NatSpec completo

---

## CI/CD

| Pipeline | Estado |
|----------|--------|
| **GitHub Actions** | ✅ Pasando (después de aplicar `forge fmt`) |
| **Forge fmt** | ✅ Formato correcto |
| **Forge build** | ✅ Compilación exitosa |
| **Forge test** | ✅ 43/43 tests pasando |

---

## Changelog v3 (29 Nov 2025)

### Cambios Principales
1. ✅ NatSpec completo en todos los parámetros y retornos (funciones internas incluidas)
2. ✅ Redespliegue con dirección nueva para contrato 100% documentado
3. ✅ Verificación automática en Etherscan y Blockscout

### Changelog v2 (28 Nov 2025)

### Cambios Críticos
1. ✅ Fix atomicidad en `_checkBankCap` y `_checkEthDepositCap`
2. ✅ NatSpec completo en todos los errores personalizados
3. ✅ Timeout de oráculo: 1h → 3h
4. ✅ Redespliegue con nueva dirección

### Documentación Actualizada
- ✅ README.md traducido a español latinoamericano
- ✅ Sección de verificación técnica de bytecode
- ✅ Métricas de cobertura actualizadas
- ✅ AUDITOR_GUIDE.md, THREAT_MODEL.md, DEPLOY_EXAMPLE.md

---

## Comandos de Verificación Rápida

```bash
# Ejecutar tests
forge test -vv

# Generar cobertura
forge coverage --report lcov
genhtml lcov.info --branch-coverage --output-directory coverage

# Verificar formato
forge fmt --check

# Verificar parámetros on-chain
bash scripts/quick_verify.sh

# Interacción (dry-run)
forge script script/Interact.s.sol:InteractScript --rpc-url $RPC_URL_SEPOLIA -vvvv --dry-run
```

---

## Conclusión

✅ **Todas las verificaciones pasaron exitosamente**

El contrato desplegado en `0xc6d24cBbF2CCC70ef6E4EeD507fEA0F801321691` coincide con el código fuente del repositorio, todos los parámetros están configurados correctamente según especificaciones, los tests pasan al 100%, la documentación NatSpec está completa en todas las funciones, y el código fuente está verificado en Etherscan y Blockscout.

**Estado**: Listo para uso educativo en Sepolia.

---

**Responsable**: G-Centurion  
**Última actualización**: 29 Nov 2025
