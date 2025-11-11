# Guía: abi.encodeWithSelector en Solidity y Tests Foundry

## ¿Qué es `abi.encodeWithSelector`?

`abi.encodeWithSelector` es una función de bajo nivel en Solidity que codifica datos para una llamada de función, incluyendo:
1. El **selector** de la función (primeros 4 bytes del hash keccak256 de la firma)
2. Los **argumentos** codificados en ABI

El resultado es un array de bytes que representa completamente esa llamada.

### Sintaxis
```solidity
bytes memory encodedCall = abi.encodeWithSelector(
    function.selector,  // o ErrorType.selector para custom errors
    arg1,
    arg2,
    ...
);
```

---

## Uso Principal: Tests con Custom Errors

### En Foundry (Forge)

Cuando quieres verificar que una función revierte con un **custom error específico Y con argumentos exactos**, usas:

```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        MyCustomError.selector,
        expectedArg1,
        expectedArg2
    )
);
myFunction();
```

### Ejemplo Real: OpenZeppelin AccessControl

```solidity
// Contrato: función protegida por rol
function pause() external onlyRole(PAUSE_MANAGER_ROLE) {
    _pause();
}

// Test: verificar que usuario sin rol no puede pausar
function testOnlyPauseManagerCanPause() public {
    vm.prank(user);  // user no tiene PAUSE_MANAGER_ROLE
    
    // Esperar revert con selector + argumentos de AccessControl
    vm.expectRevert(
        abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            user,                          // La cuenta que intentó
            bank.PAUSE_MANAGER_ROLE()      // El rol requerido
        )
    );
    
    bank.pause();  // Esta llamada revierte
}
```

---

## Casos de Uso

### ✅ Úsalo para verificar Custom Errors CON argumentos:

```solidity
// Custom error en contrato:
error Bank__WithdrawalExceedsLimit(uint256 limit, uint256 requested);

// Test:
vm.expectRevert(
    abi.encodeWithSelector(
        Bank__WithdrawalExceedsLimit.selector,
        1 ether,    // limit
        2 ether     // requested
    )
);
bank.withdrawToken(address(0), 2 ether);
```

### ✅ Para simple revert sin argumentos:

```solidity
// Custom error sin argumentos:
error Bank__ZeroAmount();

// Test (opción 1 - explícito):
vm.expectRevert(
    abi.encodeWithSelector(Bank__ZeroAmount.selector)
);
bank.deposit{value: 0}();

// Test (opción 2 - simple):
vm.expectRevert(Bank__ZeroAmount.selector);
bank.deposit{value: 0}();
```

### ✅ Para cualquier revert (sin verificar qué error):

```solidity
vm.expectRevert();  // Acepta cualquier revert
bank.someFunction();
```

---

## ¿Dónde NO aparece `abi.encodeWithSelector` en tu código?

### ❌ NO en el contrato principal (`src/KipuBankV3_TP4.sol`)

El contrato usa **revert con custom errors directamente**:
```solidity
// En KipuBankV3_TP4.sol
if (amountToWithdraw > limit) {
    revert Bank__WithdrawalExceedsLimit(limit, amountToWithdraw);  // Revert directo
}
```

No hay construcción manual de bytes; Solidity maneja todo automáticamente.

### ✅ SÍ en los tests (`test/KipuBankV3Test.sol`)

Los tests usan `abi.encodeWithSelector` para:
1. **Construir el revert esperado** y pasarlo a `vm.expectRevert(...)`
2. Decirle a Foundry exactamente qué bytes de error esperar

```solidity
// En KipuBankV3Test.sol
vm.expectRevert(
    abi.encodeWithSelector(
        Bank__WithdrawalExceedsLimit.selector,
        1 ether,
        2 ether
    )
);
bank.withdrawToken(address(0), 2 ether);
```

---

## Patrón Correcto de Tests

### Patrón General para RBAC Tests:

```solidity
function testOnly<Role>Can<Action>() public {
    // Setup
    address unauthorizedUser = address(0xBEEF);
    
    // Simular al usuario sin rol
    vm.prank(unauthorizedUser);
    
    // Esperar revert con selector + argumentos
    vm.expectRevert(
        abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            unauthorizedUser,
            bank.REQUIRED_ROLE()
        )
    );
    
    // Llamada que debe revertir
    bank.protectedFunction();
}
```

### Patrón para Custom Error con Argumentos:

```solidity
function testFunctionThrowsCustomError() public {
    vm.prank(user);
    
    vm.expectRevert(
        abi.encodeWithSelector(
            Bank__CustomError.selector,
            arg1Expected,
            arg2Expected
        )
    );
    
    bank.functionThatErrors();
}
```

---

## Resumen de Argumentos Comunes

| Error | Argumentos | Ejemplo |
|-------|-----------|---------|
| `IAccessControl.AccessControlUnauthorizedAccount` | `(address account, bytes32 role)` | `(user, bank.PAUSE_MANAGER_ROLE())` |
| `Bank__WithdrawalExceedsLimit` | `(uint256 limit, uint256 requested)` | `(1 ether, 2 ether)` |
| `Bank__InsufficientBalance` | `(uint256 available, uint256 requested)` | `(1 ether, 2 ether)` |
| `Bank__DepositExceedsLimit` | `(uint256 currentBalance, uint256 cap, uint256 attempted)` | depende del contexto |
| `Bank__ZeroAmount` | (ninguno) | `Bank__ZeroAmount.selector` |
| `Pausable.EnforcedPause` | (ninguno) | `Pausable.EnforcedPause.selector` |

---

## Tips y Trucos

### 1. Verificar el selector correcto
```solidity
// Para custom error:
bytes4 selector = Bank__WithdrawalExceedsLimit.selector;
console.logBytes4(selector);  // Imprime el selector en logs

// Para error de OpenZeppelin:
bytes4 selector = IAccessControl.AccessControlUnauthorizedAccount.selector;
```

### 2. Si los argumentos son dinámicos
Si esperas una string o dynamic array, `abi.encodeWithSelector` los encoda correctamente:
```solidity
vm.expectRevert(
    abi.encodeWithSelector(
        SomeError.selector,
        dynamicString,
        dynamicArray
    )
);
```

### 3. Usar vm.expectRevert() genérico para casos frágiles
Si calcular exactamente todos los argumentos es complejo:
```solidity
vm.expectRevert();  // Cualquier revert vale
bank.complexFunction();
```

---

## Referencias

- **Solidity Docs:** https://docs.soliditylang.org/en/latest/abi-spec.html
- **Foundry Docs:** https://book.getfoundry.sh/forge/tests
- **OpenZeppelin AccessControl:** https://docs.openzeppelin.com/contracts/4.x/access-control

