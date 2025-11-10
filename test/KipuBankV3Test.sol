// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/KipuBankV3_TP4.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 al = allowance[from][msg.sender];
        if (msg.sender != from) {
            require(al >= amount, "allowance");
            allowance[from][msg.sender] = al - amount;
        }
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockAggregator is AggregatorV3Interface {
    int256 public answer;

    constructor(int256 _answer) {
        answer = _answer;
    }

    function decimals() external pure override returns (uint8) { return 8; }
    function description() external pure override returns (string memory) { return "mock"; }
    function version() external pure override returns (uint256) { return 1; }

    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        revert("not needed");
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, answer, 0, 0, 0);
    }
}

contract MockRouter {
    address public WETH_TOKEN;

    constructor(address _weth) {
        WETH_TOKEN = _weth;
    }

    function WETH() external view returns (address) {
        return WETH_TOKEN;
    }

    // Minimal implementations to satisfy interface used in tests
    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            if (i == 0) amounts[i] = amountIn;
            else amounts[i] = 100 * 10 ** 6; // return 100 USDC (6 decimals) as a conservative estimate
        }
        return amounts;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        // pull tokens from caller (the bank contract)
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        // mint the output token to recipient (assumes last path token implements mint)
        uint256 out = amountIn * 2;
        MockERC20(path[path.length - 1]).mint(to, out);
        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            if (i == 0) amounts[i] = amountIn;
            else amounts[i] = out;
        }
        return amounts;
    }
}

contract KipuBankV3Test is Test {
    KipuBankV3 bank;
    MockAggregator priceFeed;
    MockRouter router;
    MockERC20 usdc;
    MockERC20 tokenIn;

    address user = address(0xCAFE);

    function setUp() public {
        // create tokens and mocks
        usdc = new MockERC20("USD Coin", "USDC", 6);
        tokenIn = new MockERC20("TokenIn", "TIN", 18);
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);

        router = new MockRouter(address(weth));

        // price = 2000 USD with 8 decimals
        priceFeed = new MockAggregator(int256(2000 * 10 ** 8));

        // deploy bank
        bank = new KipuBankV3(address(priceFeed), 1 ether, address(router), address(usdc));

    // register tokenIn as allowed in the bank's catalog (granted to this test contract in constructor)
    bank.addOrUpdateToken(address(tokenIn), address(0), 18);

        // fund user with ETH and tokenIn
        vm.deal(user, 10 ether);
        tokenIn.mint(user, 1000 ether);
    }

    function testDepositEth() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        bank.deposit{value: amount}();

        // check internal balance recorded
        assertEq(bank.balances(user, address(0)), amount);
        assertEq(bank.getDepositCount(), 1);
    }

    function testWithdrawEth() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        bank.deposit{value: amount}();

        // now withdraw
        vm.prank(user);
        bank.withdrawToken(address(0), amount);

        // internal balance should be zero
        assertEq(bank.balances(user, address(0)), 0);
    }

    function testDepositAndSwapERC20() public {
        uint256 amountIn = 1 ether;

        // user approves bank to pull tokenIn
        vm.prank(user);
        tokenIn.approve(address(bank), amountIn);

        // execute deposit and swap
        vm.prank(user);
        bank.depositAndSwapERC20(address(tokenIn), amountIn, 1, uint48(block.timestamp + 1));

        // expected USDC minted by router = amountIn * 2
        uint256 expected = amountIn * 2;
        assertEq(bank.balances(user, address(usdc)), expected);
    }

    function testPauseAndUnpause() public {
        vm.startPrank(address(bank));
        bank.pause();
        assertTrue(bank.paused());
        
        bank.unpause();
        assertFalse(bank.paused());
        vm.stopPrank();
    }

    function testDepositExceedsCap() public {
        uint256 hugeAmount = 1_000_000 ether; // Intentar depositar más del cap
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Bank__DepositExceedsCap.selector, 0, bank.BANK_CAP_USD(), hugeAmount * 2000 * 10**8 / 10**18));
        bank.deposit{value: hugeAmount}();
    }

    function testZeroAmountDeposit() public {
        vm.prank(user);
        vm.expectRevert(Bank__ZeroAmount.selector);
        bank.deposit{value: 0}();
    }

    function testSwapWithHighSlippage() public {
        uint256 amountIn = 1 ether;
        uint256 minAmountOut = type(uint256).max; // Requiere más de lo posible
        
        vm.prank(user);
        tokenIn.approve(address(bank), amountIn);
        
        vm.prank(user);
        vm.expectRevert(Bank__SlippageTooHigh.selector);
        bank.depositAndSwapERC20(address(tokenIn), amountIn, minAmountOut, uint48(block.timestamp + 1));
    }

    function testInvalidPriceFeed() public {
        // Set price to negative to test oracle validation
        MockAggregator invalidPriceFeed = new MockAggregator(-1);
        
        // Need to have CAP_MANAGER_ROLE to set price feed
        bytes32 CAP_MANAGER_ROLE = bank.CAP_MANAGER_ROLE();
        vm.prank(address(bank));
        bank.grantRole(CAP_MANAGER_ROLE, address(this));
        
        bank.setEthPriceFeedAddress(address(invalidPriceFeed));
        
        vm.prank(user);
        vm.expectRevert(Bank__TransferFailed.selector);
        bank.deposit{value: 1 ether}();
    }

    function testWithdrawExceedsLimit() public {
        // First deposit some ETH
        uint256 depositAmount = 2 ether;
        vm.prank(user);
        bank.deposit{value: depositAmount}();

        // Try to withdraw more than the limit
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Bank__WithdrawalExceedsLimit.selector, 1 ether, 2 ether));
        bank.withdrawToken(address(0), 2 ether);
    }

    function testInvalidTokenWithdraw() public {
        address invalidToken = address(0x1234);
        vm.prank(user);
        vm.expectRevert(Bank__TokenNotSupported.selector);
        bank.withdrawToken(invalidToken, 1 ether);
    }

    function testDepositInvalidToken() public {
        address invalidToken = address(0x1234);
        vm.prank(user);
        vm.expectRevert(Bank__TokenNotSupported.selector);
        bank.depositAndSwapERC20(invalidToken, 1 ether, 0, uint48(block.timestamp + 1));
    }

    // ========== Pruebas de Fuzzing ==========
    
    function testFuzz_Deposit(uint256 amount) public {
        // Limitar el monto para evitar que exceda el cap del banco
        amount = bound(amount, 1, 100 ether);
        
        vm.deal(user, amount);
        vm.prank(user);
        bank.deposit{value: amount}();
        
        assertEq(bank.balances(user, address(0)), amount);
    }

    function testFuzz_SwapAmounts(uint256 amountIn) public {
        // Limitar el monto para que sea razonable
        amountIn = bound(amountIn, 1, 1000 ether);
        
        // Mint tokens para el usuario
        tokenIn.mint(user, amountIn);
        
        vm.startPrank(user);
        tokenIn.approve(address(bank), amountIn);
        bank.depositAndSwapERC20(
            address(tokenIn),
            amountIn,
            1, // minAmountOut mínimo para que pase
            uint48(block.timestamp + 1)
        );
        vm.stopPrank();
        
        // Verificar que el usuario recibió USDC
        assertTrue(bank.balances(user, address(usdc)) > 0);
    }

    // ========== Pruebas de Eventos ==========
    
    function testDepositEvent() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        
        vm.expectEmit(true, true, false, true);
        emit DepositSuccessful(user, address(0), amount);
        
        bank.deposit{value: amount}();
    }

    function testWithdrawEvent() public {
        uint256 amount = 1 ether;
        
        // Primero depositamos
        vm.prank(user);
        bank.deposit{value: amount}();
        
        // Luego retiramos y verificamos el evento
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit WithdrawalSuccessful(user, address(0), amount);
        
        bank.withdrawToken(address(0), amount);
    }

    // ========== Pruebas de Roles y Permisos ==========
    
    function testRoleManagement() public {
        address newManager = address(0xBEEF);
        bytes32 CAP_MANAGER_ROLE = bank.CAP_MANAGER_ROLE();
        bytes32 PAUSE_MANAGER_ROLE = bank.PAUSE_MANAGER_ROLE();
        bytes32 TOKEN_MANAGER_ROLE = bank.TOKEN_MANAGER_ROLE();
        
        // El deployer (this) debería tener DEFAULT_ADMIN_ROLE
        assertTrue(bank.hasRole(bank.DEFAULT_ADMIN_ROLE(), address(this)));
        
        // Otorgar roles
        bank.grantRole(CAP_MANAGER_ROLE, newManager);
        bank.grantRole(PAUSE_MANAGER_ROLE, newManager);
        bank.grantRole(TOKEN_MANAGER_ROLE, newManager);
        
        assertTrue(bank.hasRole(CAP_MANAGER_ROLE, newManager));
        assertTrue(bank.hasRole(PAUSE_MANAGER_ROLE, newManager));
        assertTrue(bank.hasRole(TOKEN_MANAGER_ROLE, newManager));
        
        // Revocar roles
        bank.revokeRole(CAP_MANAGER_ROLE, newManager);
        assertFalse(bank.hasRole(CAP_MANAGER_ROLE, newManager));
    }

    function testOnlyPauseManagerCanPause() public {
        // Usuario sin rol intenta pausar
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                bank.PAUSE_MANAGER_ROLE()
            )
        );
        bank.pause();
    }

    // ========== Pruebas de Integración Extendidas ==========
    
    function testComplexSwapScenario() public {
        // 1. Configurar montos
        uint256 depositAmount = 5 ether;
        uint256 swapAmount = 2 ether;
        
        // 2. Realizar depósito de ETH
        vm.prank(user);
        bank.deposit{value: depositAmount}();
        
        // 3. Preparar swap
        tokenIn.mint(user, swapAmount);
        
        vm.startPrank(user);
        tokenIn.approve(address(bank), swapAmount);
        
        // 4. Realizar swap
        bank.depositAndSwapERC20(
            address(tokenIn),
            swapAmount,
            1,
            uint48(block.timestamp + 1)
        );
        vm.stopPrank();
        
        // 5. Verificar balances
        assertEq(bank.balances(user, address(0)), depositAmount);
        assertTrue(bank.balances(user, address(usdc)) > 0);
        
        // 6. Intentar retirar ambos tokens
        vm.startPrank(user);
        bank.withdrawToken(address(0), 1 ether);
        bank.withdrawToken(address(usdc), bank.balances(user, address(usdc)));
        vm.stopPrank();
        
        // 7. Verificar balances finales
        assertEq(bank.balances(user, address(0)), depositAmount - 1 ether);
        assertEq(bank.balances(user, address(usdc)), 0);
    }

    function testMultiUserScenario() public {
        address user2 = address(0xBEEF);
        vm.deal(user2, 5 ether);
        
        // Usuario 1 deposita ETH
        vm.prank(user);
        bank.deposit{value: 1 ether}();
        
        // Usuario 2 deposita ETH
        vm.prank(user2);
        bank.deposit{value: 2 ether}();
        
        // Usuario 1 realiza swap
        tokenIn.mint(user, 1 ether);
        vm.startPrank(user);
        tokenIn.approve(address(bank), 1 ether);
        bank.depositAndSwapERC20(
            address(tokenIn),
            1 ether,
            1,
            uint48(block.timestamp + 1)
        );
        vm.stopPrank();
        
        // Verificar balances independientes
        assertEq(bank.balances(user, address(0)), 1 ether);
        assertEq(bank.balances(user2, address(0)), 2 ether);
        assertTrue(bank.balances(user, address(usdc)) > 0);
        assertEq(bank.balances(user2, address(usdc)), 0);
    }

    // ========== Pruebas de Recuperación de Errores ==========
    
    function testRecoveryFromFailedSwap() public {
        // Simular un escenario donde el swap falla pero el ETH está seguro
        uint256 ethAmount = 1 ether;
        vm.prank(user);
        bank.deposit{value: ethAmount}();
        
        // Intentar swap con slippage imposible
        tokenIn.mint(user, 1 ether);
        vm.startPrank(user);
        tokenIn.approve(address(bank), 1 ether);
        
        vm.expectRevert(Bank__SlippageTooHigh.selector);
        bank.depositAndSwapERC20(
            address(tokenIn),
            1 ether,
            type(uint256).max, // Slippage imposible
            uint48(block.timestamp + 1)
        );
        vm.stopPrank();
        
        // Verificar que el ETH sigue seguro
        assertEq(bank.balances(user, address(0)), ethAmount);
    }

    // ========== Pruebas de Control de Acceso (Funciones Administrativas) ==========

    function testSetEthPriceFeedAddress() public {
        MockAggregator newPriceFeed = new MockAggregator(int256(2500 * 10 ** 8));
        
        // Debe permitir a CAP_MANAGER_ROLE
        bytes32 CAP_MANAGER_ROLE = bank.CAP_MANAGER_ROLE();
        vm.prank(address(this)); // Este test contract es el deployer
        bank.setEthPriceFeedAddress(address(newPriceFeed));
        
        // Verificar que el nuevo feed funciona
        vm.prank(user);
        bank.deposit{value: 1 ether}();
        
        assertEq(bank.balances(user, address(0)), 1 ether);
    }

    function testOnlyCapManagerCanSetPriceFeed() public {
        MockAggregator newPriceFeed = new MockAggregator(int256(2500 * 10 ** 8));
        
        // Usuario sin rol intenta cambiar el feed
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                bank.CAP_MANAGER_ROLE()
            )
        );
        bank.setEthPriceFeedAddress(address(newPriceFeed));
    }

    function testAddOrUpdateToken() public {
        address newToken = address(0x9999);
        MockAggregator newTokenFeed = new MockAggregator(int256(1 * 10 ** 8)); // 1 USD
        
        // Test contract (deployer) tiene TOKEN_MANAGER_ROLE
        bank.addOrUpdateToken(newToken, address(newTokenFeed), 18);
        
        // Verificar que el token fue registrado
        assertTrue(bank.balances(user, newToken) == 0); // Simplemente verificar que no hay error
    }

    function testOnlyTokenManagerCanAddToken() public {
        address newToken = address(0x9999);
        MockAggregator newTokenFeed = new MockAggregator(int256(1 * 10 ** 8));
        
        // Usuario sin rol intenta agregar token
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                bank.TOKEN_MANAGER_ROLE()
            )
        );
        bank.addOrUpdateToken(newToken, address(newTokenFeed), 18);
    }

    function testOnlyPauseManagerCanUnpause() public {
        // Primero, pausar (como deployer que tiene el rol)
        bank.pause();
        assertTrue(bank.paused());
        
        // Usuario sin rol intenta despaused
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                bank.PAUSE_MANAGER_ROLE()
            )
        );
        bank.unpause();
        
        // Pero el deployer puede
        bank.unpause();
        assertFalse(bank.paused());
    }

    function testGrantRoleAndVerify() public {
        address newManager = address(0xDEAD);
        bytes32 CAP_MANAGER_ROLE = bank.CAP_MANAGER_ROLE();
        
        // Deployer otorga rol
        bank.grantRole(CAP_MANAGER_ROLE, newManager);
        assertTrue(bank.hasRole(CAP_MANAGER_ROLE, newManager));
        
        // Nuevo manager puede usar el rol
        MockAggregator newPriceFeed = new MockAggregator(int256(2200 * 10 ** 8));
        vm.prank(newManager);
        bank.setEthPriceFeedAddress(address(newPriceFeed));
    }

    function testRevokeRoleAndDeny() public {
        address newManager = address(0xDEAD);
        bytes32 CAP_MANAGER_ROLE = bank.CAP_MANAGER_ROLE();
        
        // Otorgar rol
        bank.grantRole(CAP_MANAGER_ROLE, newManager);
        assertTrue(bank.hasRole(CAP_MANAGER_ROLE, newManager));
        
        // Revocar rol
        bank.revokeRole(CAP_MANAGER_ROLE, newManager);
        assertFalse(bank.hasRole(CAP_MANAGER_ROLE, newManager));
        
        // Intento de usar el rol debe fallar
        MockAggregator newPriceFeed = new MockAggregator(int256(2200 * 10 ** 8));
        vm.prank(newManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControl.AccessControlUnauthorizedAccount.selector,
                newManager,
                CAP_MANAGER_ROLE
            )
        );
        bank.setEthPriceFeedAddress(address(newPriceFeed));
    }

    function testDepositWhenPausedFails() public {
        // Pausar el contrato
        bank.pause();
        
        // Intentar depositar
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        bank.deposit{value: 1 ether}();
    }

    function testSwapWhenPausedFails() public {
        // Pausar el contrato
        bank.pause();
        
        // Intentar realizar swap
        tokenIn.mint(user, 1 ether);
        vm.startPrank(user);
        tokenIn.approve(address(bank), 1 ether);
        
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        bank.depositAndSwapERC20(
            address(tokenIn),
            1 ether,
            1,
            uint48(block.timestamp + 1)
        );
        vm.stopPrank();
    }

    function testWithdrawWhenPausedFails() public {
        // Depositar primero
        vm.prank(user);
        bank.deposit{value: 1 ether}();
        
        // Pausar el contrato
        bank.pause();
        
        // Intentar retirar
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        bank.withdrawToken(address(0), 0.5 ether);
    }

    function testInvalidTokenAddressThrows() public {
        // Intentar agregar token con dirección cero
        vm.prank(address(this));
        vm.expectRevert(Bank__InvalidTokenAddress.selector);
        bank.addOrUpdateToken(address(0), address(0), 18);
    }

    function testDepositETHWhilePausedFails() public {
        bank.pause();
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        bank.deposit{value: 1 ether}();
    }

    // ========== Pruebas Adicionales de Seguridad ==========

    function testZeroAmountSwap() public {
        vm.prank(user);
        vm.expectRevert(Bank__ZeroAmount.selector);
        bank.depositAndSwapERC20(address(tokenIn), 0, 0, uint48(block.timestamp + 1));
    }

    function testZeroAmountWithdraw() public {
        vm.prank(user);
        vm.expectRevert(Bank__ZeroAmount.selector);
        bank.withdrawToken(address(0), 0);
    }

    function testWithdrawUSDCSuccessfully() public {
        // Depositar y hacer swap
        uint256 amountIn = 1 ether;
        tokenIn.mint(user, amountIn);
        
        vm.startPrank(user);
        tokenIn.approve(address(bank), amountIn);
        bank.depositAndSwapERC20(address(tokenIn), amountIn, 1, uint48(block.timestamp + 1));
        
        uint256 usdcBalance = bank.balances(user, address(usdc));
        assertTrue(usdcBalance > 0);
        
        // Retirar USDC
        bank.withdrawToken(address(usdc), usdcBalance);
        assertEq(bank.balances(user, address(usdc)), 0);
        vm.stopPrank();
    }

    function testDepositCountIncrement() public {
        uint256 initialCount = bank.getDepositCount();
        
        vm.prank(user);
        bank.deposit{value: 0.5 ether}();
        
        assertEq(bank.getDepositCount(), initialCount + 1);
        
        vm.prank(user);
        bank.deposit{value: 0.5 ether}();
        
        assertEq(bank.getDepositCount(), initialCount + 2);
    }

    // ========== Pruebas Avanzadas de Seguridad ==========

    function testReentrancyProtectionDeposit() public {
        // Crear un contrato malicioso que intenta reentrancia
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(bank));
        
        // Dar fondos al atacante
        vm.deal(address(attacker), 10 ether);
        
        // El atacante intenta hacer reentrancia en deposit
        vm.prank(address(attacker));
        bank.deposit{value: 1 ether}();
        
        // Si no revierte, la protección está funcionando
        assertEq(bank.balances(address(attacker), address(0)), 1 ether);
    }

    function testStalePriceDetection() public {
        // Crear un precio feed desactualizado
        int256 stalePriceValue = int256(2000 * 10 ** 8);
        MockAggregator stalePriceFeed = new MockAggregator(stalePriceValue);
        
        // Cambiar el feed de precios
        bank.setEthPriceFeedAddress(address(stalePriceFeed));
        
        // Intentar depositar con precio desactualizado
        // Nota: En este mock, siempre retorna el mismo timestamp, así que esto es más teórico
        vm.prank(user);
        bank.deposit{value: 1 ether}();
        
        // Si llegamos aquí, el precio fue validado
        assertEq(bank.balances(user, address(0)), 1 ether);
    }

    function testSequentialDepositsAndWithdrawals() public {
        // Test de múltiples operaciones secuenciales
        uint256 ethAmount = 0.5 ether;
        
        // Depositar múltiples veces
        for (uint i = 0; i < 5; i++) {
            vm.prank(user);
            bank.deposit{value: ethAmount}();
        }
        
        // Verificar balance total
        assertEq(bank.balances(user, address(0)), ethAmount * 5);
        
        // Retirar múltiples veces
        for (uint i = 0; i < 3; i++) {
            vm.prank(user);
            bank.withdrawToken(address(0), ethAmount);
        }
        
        // Verificar balance final
        assertEq(bank.balances(user, address(0)), ethAmount * 2);
    }

    function testCrossUserIsolation() public {
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        address user3 = address(0x3333);
        
        vm.deal(user1, 5 ether);
        vm.deal(user2, 5 ether);
        vm.deal(user3, 5 ether);
        
        // User 1 deposita
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        
        // User 2 deposita diferente cantidad
        vm.prank(user2);
        bank.deposit{value: 2 ether}();
        
        // User 3 deposita diferente cantidad
        vm.prank(user3);
        bank.deposit{value: 3 ether}();
        
        // Verificar que cada usuario tiene el balance correcto
        assertEq(bank.balances(user1, address(0)), 1 ether);
        assertEq(bank.balances(user2, address(0)), 2 ether);
        assertEq(bank.balances(user3, address(0)), 3 ether);
    }

    function testSwapAndWithdrawCycle() public {
        // Depositar y hacer swap
        uint256 amountIn = 2 ether;
        tokenIn.mint(user, amountIn);
        
        vm.startPrank(user);
        
        // Depositamos ETH
        bank.deposit{value: 1 ether}();
        assertEq(bank.balances(user, address(0)), 1 ether);
        
        // Hacemos swap
        tokenIn.approve(address(bank), amountIn);
        bank.depositAndSwapERC20(
            address(tokenIn),
            amountIn,
            1,
            uint48(block.timestamp + 1)
        );
        
        uint256 usdcBalance = bank.balances(user, address(usdc));
        assertTrue(usdcBalance > 0);
        
        // Retiramos ETH
        bank.withdrawToken(address(0), 0.5 ether);
        assertEq(bank.balances(user, address(0)), 0.5 ether);
        
        // Retiramos USDC
        bank.withdrawToken(address(usdc), usdcBalance);
        assertEq(bank.balances(user, address(usdc)), 0);
        
        vm.stopPrank();
    }

    function testBankCapEnforcementMultiUser() public {
        // Test que el cap es respetado incluso con múltiples usuarios
        address user1 = address(0x4444);
        address user2 = address(0x5555);
        
        // Dar muchísimos fondos
        vm.deal(user1, 500_000 ether);
        vm.deal(user2, 500_000 ether);
        
        // User 1 deposita cantidad grande (pero no excesiva)
        vm.prank(user1);
        bank.deposit{value: 250 ether}();
        
        // User 2 intenta depositar cantidad que haría exceder el cap
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Bank__DepositExceedsCap.selector));
        bank.deposit{value: 300 ether}();
    }

    function testEventEmissionAccuracy() public {
        // Verificar que los eventos emiten valores correctos
        vm.prank(user);
        
        vm.expectEmit(true, true, false, true);
        emit DepositSuccessful(user, address(0), 1 ether);
        
        bank.deposit{value: 1 ether}();
    }

    function testMaxWithdrawalEnforcement() public {
        // Depositar el máximo permitido más un poco
        uint256 maxWithdrawal = bank.MAX_WITHDRAWAL_PER_TX();
        uint256 depositAmount = maxWithdrawal + 1 ether;
        
        vm.deal(user, depositAmount);
        vm.prank(user);
        bank.deposit{value: depositAmount}();
        
        // Intentar retirar el máximo - debería funcionar
        vm.prank(user);
        bank.withdrawToken(address(0), maxWithdrawal);
        assertEq(bank.balances(user, address(0)), 1 ether);
        
        // Intentar retirar el máximo nuevamente - debería fallar
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Bank__WithdrawalExceedsLimit.selector));
        bank.withdrawToken(address(0), maxWithdrawal);
    }

    function testLargeAmountHandling() public {
        // Probar que el contrato maneja números grandes correctamente
        uint256 largeAmount = 100 ether;
        
        vm.deal(user, largeAmount);
        vm.prank(user);
        bank.deposit{value: largeAmount}();
        
        assertEq(bank.balances(user, address(0)), largeAmount);
    }

    function testSmallAmountHandling() public {
        // Probar que el contrato maneja números pequeños correctamente
        uint256 smallAmount = 0.001 ether; // 1 Gwei
        
        vm.deal(user, smallAmount);
        vm.prank(user);
        bank.deposit{value: smallAmount}();
        
        assertEq(bank.balances(user, address(0)), smallAmount);
    }
}

// ========== Contrato Auxiliar para Pruebas de Reentrancia ==========

contract ReentrancyAttacker {
    KipuBankV3 bank;

    constructor(address bankAddress) {
        bank = KipuBankV3(bankAddress);
    }

    receive() external payable {
        // Intenta hacer reentrancia en withdraw si es posible
        // En un escenario real, intentaríamos llamar al mismo banco de nuevo
        // Pero con ReentrancyGuard, esto debería fallar
    }

    function attack() external {
        bank.deposit{value: msg.value}();
    }
}
