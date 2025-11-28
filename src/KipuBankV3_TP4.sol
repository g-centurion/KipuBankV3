// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// =========================================================================
/**
 * @title KipuBankV3_TP4
 * @author G-Centurion
 * @notice Banco DeFi educativo con depósitos en ETH/ERC‑20, swap automático a USDC y retiros con límites.
 * @dev Integra Uniswap V2 (swaps) y Chainlink (ETH/USD). Aplica CEI, ReentrancyGuard, RBAC y validaciones de precio.
 */
// M4 IMPORTS: UNISWAP V2, OPENZEPPELIN, CHAINLINK
// Uses audited libraries and interfaces.
// =========================================================================

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// =========================================================================
// CUSTOM ERRORS (Correction: Eliminating require strings)
// =========================================================================

/// @dev Thrown when the deposited amount exceeds the remaining capacity of the bank in USD (V8: Business Limits).
error Bank__DepositExceedsCap(uint256 currentBalanceUsd, uint256 bankCapUsd, uint256 attemptedDepositUsd);
/// @dev Thrown when the requested withdrawal amount exceeds the per-transaction limit.
error Bank__WithdrawalExceedsLimit(uint256 limit, uint256 requested);
/// @dev Thrown when the user attempts to withdraw more than their available balance.
error Bank__InsufficientBalance(uint256 available, uint256 requested);
/// @dev Thrown when a transfer (ETH or ERC-20) fails.
error Bank__TransferFailed();
/// @dev Thrown when an invalid token address (like address(0)) is used in an ERC-20 context.
error Bank__InvalidTokenAddress();
/// @dev Thrown when a zero amount is provided to a function that expects > 0.
error Bank__ZeroAmount();
/// @dev Thrown when a token is not supported by the bank's token catalog.
error Bank__TokenNotSupported();
/// @dev Thrown if the price obtained after the swap is less than the minimum expected amount (V8, V14: Anti-Slippage/MEV protection).
error Bank__SlippageTooHigh();
/// @dev Thrown if the price obtained from Chainlink is stale (timestamp too old).
error Bank__StalePrice(uint256 updateTime, uint256 currentTime);
/// @dev Thrown if the price deviated too much from expected bounds (circuit breaker).
error Bank__PriceDeviation(int256 currentPrice, int256 previousPrice);

// ===================================
// EVENTS (M2/M3 Requirement: Observability)
// ===================================

/// @dev Emitted upon a successful ETH or ERC-20 deposit or a successful swap to USDC.
/// @param user The address of the depositor.
/// @param token The token address (address(0) for ETH, USDC address for swaps).
/// @param amount The amount deposited/received.
event DepositSuccessful(address indexed user, address indexed token, uint256 amount);

/// @dev Emitted upon a successful ETH or ERC-20 withdrawal.
/// @param user The address of the user who withdrew.
/// @param token The token address (address(0) for ETH).
/// @param amount The amount withdrawn.
event WithdrawalSuccessful(address indexed user, address indexed token, uint256 amount);

// =========================================================================
// CONTRACT KipuBankV3 (Inherits V2 Security)
// =========================================================================

contract KipuBankV3 is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20; // Enables secure ERC-20 interactions (V10: Token Security).

    // --- ROLES (Inherited from V2) ---
    /// @notice Rol admin por defecto (gestiona roles).
    bytes32 public constant CAP_MANAGER_ROLE = keccak256("CAP_MANAGER_ROLE");
    /// @notice Rol autorizado a pausar/despausar.
    bytes32 public constant PAUSE_MANAGER_ROLE = keccak256("PAUSE_MANAGER_ROLE");
    /// @notice Rol autorizado a administrar catálogo de tokens.
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    // --- CONSTANTS AND IMMUTABLES (V7: Gas Efficiency) ---

    /// @notice Límite global de depósitos del banco en USD (8 decimales).
    uint256 public constant BANK_CAP_USD = 1_000_000 * 10 ** 8;

    /// @notice Máximo tiempo permitido para considerar válido el oráculo (1 hora).
    uint256 public constant PRICE_FEED_TIMEOUT = 1 hours;

    /// @notice Desviación máxima de precio permitida (5% = 500 bps).
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 500; // 5%

    /// @notice Límite máximo por retiro (configurado en el constructor).
    uint256 public immutable MAX_WITHDRAWAL_PER_TX;
    /// @notice Identificador para ETH nativo (address(0)).
    /// @dev Constante privada usada para distinguir ETH en los mapas de balances.
    address private constant ETH_TOKEN = address(0);

    // --- M4 DEFI DEPENDENCIES (Immutable) ---
    /// @notice Router Uniswap V2 usado para swaps.
    IUniswapV2Router02 public immutable I_ROUTER;
    /// @notice Dirección de WETH utilizada en rutas de swap.
    address public immutable WETH_TOKEN;
    /// @notice Dirección de USDC (activo de reserva principal del banco).
    address public immutable USDC_TOKEN;

    // --- ORACLES (Inherited from V2) ---
    /// @notice Oráculo Chainlink ETH/USD principal.
    AggregatorV3Interface private sEthPriceFeed;

    /// @notice Último precio ETH/USD registrado (8 decimales) para validar desviación.
    int256 private lastRecordedPrice;

    // --- TYPE DECLARATIONS (V2/V3: Struct used for clarity) ---
    /// @notice Configuración de un token soportado por el banco.
    /// @dev Incluye oráculo, decimales y flag de habilitación.
    struct TokenData {
        address priceFeedAddress;
        uint8 tokenDecimals;
        bool isAllowed;
    }

    // --- STATE VARIABLES ---
    /// @notice Catálogo de tokens soportados: configuración por token.
    mapping(address => TokenData) private sTokenCatalog;

    /// @notice Saldos internos: usuario => token => balance.
    mapping(address => mapping(address => uint256)) public balances;

    // Counters (Correction: Removed "= 0" initialization, Gas Optimization V7).
    /// @notice Contador de depósitos exitosos.
    uint256 private _depositCount;
    /// @notice Contador de retiros exitosos.
    uint256 private _withdrawalCount;

    // --- AGGREGATES PARA CAP GLOBAL ---
    /// @notice Precio ETH/USD usado en la operación en curso (cache local para evitar múltiples lecturas).
    /// @dev Se obtiene una vez por operación y se pasa a funciones internas que lo requieran.

    // --- MODIFIERS ---
    /// @dev Requiere monto > 0.
    modifier nonZero(uint256 amount_) {
        if (amount_ == 0) revert Bank__ZeroAmount();
        _;
    }

    /// @dev Requiere token soportado para retiro (ETH o USDC).
    modifier supportedWithdrawToken(address token_) {
        if (token_ != ETH_TOKEN && token_ != USDC_TOKEN) revert Bank__TokenNotSupported();
        _;
    }

    /// @dev Requiere que el retiro respete el límite por transacción.
    modifier withinWithdrawLimit(uint256 amount_) {
        if (amount_ > MAX_WITHDRAWAL_PER_TX) revert Bank__WithdrawalExceedsLimit(MAX_WITHDRAWAL_PER_TX, amount_);
        _;
    }

    /// @dev Requiere token permitido para depósito con swap (no ETH, no USDC, y marcado allowed).
    modifier allowedDepositToken(address token_) {
        if (token_ == ETH_TOKEN || token_ == USDC_TOKEN) revert Bank__InvalidTokenAddress();
        if (!sTokenCatalog[token_].isAllowed) revert Bank__TokenNotSupported();
        _;
    }

    // ===============================================================
    // CONSTRUCTOR (Initializes roles, oracles, and DeFi components)
    // ===============================================================

    /**
     * @dev Initializes V3 with Chainlink oracle, Uniswap Router, USDC address, and withdrawal limit.
     * @param ethPriceFeedAddress_ Address of the ETH/USD Chainlink oracle (Sepolia).
     * @param maxWithdrawalAmount_ Max amount a user can withdraw per transaction (Wei/Token decimals).
     * @param routerAddress_ Address of the UniswapV2Router02 (Sepolia: 0xeE56...).
     * @param usdcAddress_ Address of the USDC testnet token.
     */
    constructor(
        address ethPriceFeedAddress_,
        uint256 maxWithdrawalAmount_,
        address routerAddress_,
        address usdcAddress_
    ) {
    // --- 1. Role Assignment (RBAC V2) ---
    // Grant roles to the deployer (msg.sender) only.
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(CAP_MANAGER_ROLE, msg.sender);
    _grantRole(PAUSE_MANAGER_ROLE, msg.sender);
    _grantRole(TOKEN_MANAGER_ROLE, msg.sender);

    // --- 2. Input Validation ---
        if (routerAddress_ == address(0) || usdcAddress_ == address(0) || ethPriceFeedAddress_ == address(0)) {
            revert Bank__InvalidTokenAddress();
        }

        // --- 3. State Initialization (Immutables) ---
        sEthPriceFeed = AggregatorV3Interface(ethPriceFeedAddress_);
        MAX_WITHDRAWAL_PER_TX = maxWithdrawalAmount_;

        I_ROUTER = IUniswapV2Router02(routerAddress_);
        USDC_TOKEN = usdcAddress_;
        WETH_TOKEN = I_ROUTER.WETH(); // Get WETH address directly from the Router.

        // --- 4. Token Catalog Setup (Base Tokens) ---
        // USDC (Assumed 6 decimals for testnet stablecoin)
        sTokenCatalog[USDC_TOKEN] = TokenData({
            priceFeedAddress: address(0), // No oracle needed as its value is 1 USD
            tokenDecimals: 6,
            isAllowed: true
        });
        // ETH (Native Token)
        sTokenCatalog[ETH_TOKEN] =
            TokenData({priceFeedAddress: ethPriceFeedAddress_, tokenDecimals: 18, isAllowed: true});
    }

    // --- ADMINISTRATIVE FUNCTIONS (V2/V3 Inherited) ---
    // Includes pause(), unpause(), setEthPriceFeedAddress(), etc. (Omitted here for brevity, assuming standard V2 implementation protected by onlyRole).
    /// @notice Pausa el contrato (emergencia). Solo `PAUSE_MANAGER_ROLE`.
    function pause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _pause();
    }

    /// @notice Reanuda el contrato. Solo `PAUSE_MANAGER_ROLE`.
    function unpause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _unpause();
    }

    /// @notice Actualiza la dirección del oráculo ETH/USD. Solo `CAP_MANAGER_ROLE`.
    function setEthPriceFeedAddress(address newAddress) external onlyRole(CAP_MANAGER_ROLE) {
        sEthPriceFeed = AggregatorV3Interface(newAddress);
    }

    /**
     * @notice Adds or updates a supported token in the bank's token catalog.
     * @dev Restricted to accounts with TOKEN_MANAGER_ROLE. This helper simplifies testing and
     * administration by registering a token's oracle address and decimals and marking it allowed.
     * @param token Address of the token to register.
     * @param priceFeed Address of the Chainlink price feed for the token (or address(0) if not applicable).
     * @param decimals Token decimals (e.g., 18 for most ERC-20s, 6 for USDC).
     */
    function addOrUpdateToken(address token, address priceFeed, uint8 decimals) external onlyRole(TOKEN_MANAGER_ROLE) {
        if (token == address(0)) revert Bank__InvalidTokenAddress();
        sTokenCatalog[token] = TokenData({priceFeedAddress: priceFeed, tokenDecimals: decimals, isAllowed: true});
    }

    // ===============================================================
    // M4 CORE FUNCTIONALITY: DEFI SWAP
    // ===============================================================

    /**
     * @notice Allows a user to deposit any ERC-20 token (tokenIn) and automatically swaps it to USDC using Uniswap V2 Router.
     * @dev Follows the Checks-Effects-Interactions pattern strictly. Crucially, checks the BANK_CAP_USD based on the *estimated* swap result before execution.
     * @param tokenIn Address of the ERC-20 token to deposit.
     * @param amountIn Amount of tokenIn to deposit.
     * @param amountOutMin Minimum amount of USDC expected to receive (V8, V14: Front-running/Slippage Protection).
     * @param deadline Unix timestamp by which the swap must complete.
     */
    function depositAndSwapERC20(address tokenIn, uint256 amountIn, uint256 amountOutMin, uint48 deadline)
        external
        whenNotPaused
        nonReentrant
        allowedDepositToken(tokenIn)
        nonZero(amountIn)
    {
        // --- 1. Determinar ruta y simular (CHECKS, sin mover fondos) ---
        address[] memory path;

        if (tokenIn == WETH_TOKEN) {
            // Path 2: WETH -> USDC
            path = new address[](2);
            path[0] = WETH_TOKEN;
            path[1] = USDC_TOKEN;
        } else {
            // Path 3: TokenIn -> WETH -> USDC (Standard reliable route)
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WETH_TOKEN;
            path[2] = USDC_TOKEN;
        }

        // Estimar USDC recibido (view)
        uint256[] memory amounts = I_ROUTER.getAmountsOut(amountIn, path);

        // --- 2. Chequear CAP global antes de mover tokens (CEI) ---
        uint256 ethPriceUsd = _getEthPriceInUsd();
        _checkBankCapWithOnchainBalances(amounts[amounts.length - 1], ethPriceUsd);

        // --- 3. Transferir tokens al contrato (INTERACTION 1/3) ---
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // --- 4. Dar allowance al router (INTERACTION 2/3) ---
        // The router needs allowance to pull 'tokenIn' from KipuBankV3's balance.
        IERC20(tokenIn).safeIncreaseAllowance(address(I_ROUTER), amountIn);

        // --- 5. Ejecutar el swap (INTERACTION 3/3) ---
        // Executes swapExactTokensForTokens, sending the resulting USDC to KipuBankV3.
        uint256[] memory actualAmounts = I_ROUTER.swapExactTokensForTokens(
            amountIn,
            amountOutMin, // Protection against slippage/MEV.
            path,
            address(this), // Recipient is the contract itself
            deadline
        );

        uint256 usdcReceived = actualAmounts[actualAmounts.length - 1];

        // Final Slippage Check (Should also be handled by the router, but adding redundancy)
        if (usdcReceived < amountOutMin) {
            revert Bank__SlippageTooHigh();
        }

        // B. EFFECTS (CEI: Update state before final event/interaction)
        unchecked {
            // Credit the USDC received to the user's internal balance.
            balances[msg.sender][USDC_TOKEN] += usdcReceived;
            _depositCount++;
        }

        // C. INTERACTIONS (Event emission)
        emit DepositSuccessful(msg.sender, USDC_TOKEN, usdcReceived);
    }

    /**
     * @notice Allows users to deposit ETH (native token).
     * @dev Follows the Checks-Effects-Interactions pattern (CEI V13.2).
     */
    function deposit() external payable whenNotPaused nonReentrant nonZero(msg.value) {
        // A. CHECKS (V2: Oracles and USD Limit)
        uint256 ethPriceUsd = _getEthPriceInUsd();
        _updateRecordedPrice(int256(ethPriceUsd));

        // Calcular USD del depósito y chequear CAP usando balances on-chain previos al msg.value
        uint256 pendingDepositUsd = _getUsdValueFromWei(msg.value, ethPriceUsd);
        _checkEthDepositCapAtomic(pendingDepositUsd, ethPriceUsd);

        // B. EFFECTS (State modification before external call/event)
        unchecked { // V7: Gas optimization
            balances[msg.sender][ETH_TOKEN] += msg.value;
            _depositCount++;
        }

        // C. INTERACTIONS
        emit DepositSuccessful(msg.sender, ETH_TOKEN, msg.value);
    }

    /**
     * @notice Allows users to withdraw ETH or USDC (and potentially other supported tokens).
     * @dev Follows CEI pattern. Uses low-level call for ETH and SafeERC20 for ERC-20.
     * @param tokenAddress The address of the token (address(0) for ETH).
     * @param amountToWithdraw The amount to withdraw (in token decimals/Wei).
     */
    function withdrawToken(address tokenAddress, uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        nonZero(amountToWithdraw)
        supportedWithdrawToken(tokenAddress)
        withinWithdrawLimit(amountToWithdraw)
    {
        // A. CHECKS
        uint256 userBalance = balances[msg.sender][tokenAddress];
        if (userBalance < amountToWithdraw) revert Bank__InsufficientBalance(userBalance, amountToWithdraw);

        // B. EFFECTS (CEI: Update state)
        unchecked { // V7: Gas optimization (safe due to preceding check)
            balances[msg.sender][tokenAddress] = userBalance - amountToWithdraw;
        }
        _withdrawalCount++;

        // C. INTERACTIONS (Secure Transfer V4)
        if (tokenAddress == ETH_TOKEN) {
            // Use low-level call and check return for secure ETH transfer.
            (bool success,) = payable(msg.sender).call{value: amountToWithdraw}("");
            if (!success) revert Bank__TransferFailed();
        } else {
            // Use SafeERC20 for ERC-20 transfer.
            IERC20(tokenAddress).safeTransfer(msg.sender, amountToWithdraw);
        }

        emit WithdrawalSuccessful(msg.sender, tokenAddress, amountToWithdraw);
    }

    // ===============================================================
    // INTERNAL & VIEW FUNCTIONS (V2 Oracles and Conversion Logic)
    // ===============================================================

    /**
     * @dev Retrieves the total value of the bank (ETH and USDC internally held) in USD (8 decimals), plus a pending USD amount.
     * @param pendingUsdValue The value of the potential deposit already converted to USD (8 decimals).
     * @return The total USD value of the contract's balances if the pending deposit is included.
     */
    function _getBankTotalUsdValueOnchain(uint256 pendingUsdValue, uint256 ethPriceUsd) private view returns (uint256) {
        // Usar balances on-chain reales del contrato para el cálculo (atomicidad y consistencia):
        // ETH actual sin contar el msg.value del depósito en curso (el caller controla esto antes de invocar).
        uint256 ethBalance = address(this).balance;
        uint256 currentEthUsdValue = _getUsdValueFromWei(ethBalance, ethPriceUsd);
        uint256 usdcBalance = IERC20(USDC_TOKEN).balanceOf(address(this));
        uint256 currentUsdcUsdValue = _getUsdValueFromUsdc(usdcBalance);
        return currentEthUsdValue + currentUsdcUsdValue + pendingUsdValue;
    }

    /**
     * @dev Helper to check the global BANK_CAP_USD given a pending USD amount.
     * Reverts with Bank__DepositExceedsCap if accepting the pending amount would
     * push the bank over the cap.
     */
    /// @dev Verifica que, al sumar `pendingUsdValue` (USD, 8 dec), el total no exceda `BANK_CAP_USD`.
    /// @param pendingUsdValue Monto pendiente a acreditar expresado en USD (8 decimales).
    /// @param ethPriceUsd Precio ETH/USD actual (8 decimales) usado para valorar balances de ETH.
    function _checkBankCapWithOnchainBalances(uint256 pendingUsdValue, uint256 ethPriceUsd) private view {
        uint256 totalUsdValueIfAccepted = _getBankTotalUsdValueOnchain(pendingUsdValue, ethPriceUsd);
        if (totalUsdValueIfAccepted > BANK_CAP_USD) {
            uint256 currentUsdBalance = _getBankTotalUsdValueOnchain(0, ethPriceUsd);
            revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, pendingUsdValue);
        }
    }

    /// @dev Chequea CAP para depósito de ETH considerando que `address(this).balance` ya incluye `msg.value`.
    /// @param pendingUsdValue Valor en USD (8 decimales) del ETH a depositar.
    /// @param ethPriceUsd Precio ETH/USD (8 decimales) para valorar el balance previo.
    function _checkEthDepositCapAtomic(uint256 pendingUsdValue, uint256 ethPriceUsd) private view {
        // Restar msg.value del balance ETH on-chain para evaluar el estado previo al depósito.
        // Nota: Este helper se usa inmediatamente al inicio del depósito ETH.
        uint256 preEthBalance = address(this).balance - msg.value;
        uint256 preEthUsd = _getUsdValueFromWei(preEthBalance, ethPriceUsd);
        uint256 usdcBalance = IERC20(USDC_TOKEN).balanceOf(address(this));
        uint256 preUsdcUsd = _getUsdValueFromUsdc(usdcBalance);
        uint256 totalIfAccepted = preEthUsd + preUsdcUsd + pendingUsdValue;
        if (totalIfAccepted > BANK_CAP_USD) {
            uint256 currentUsdBalance = preEthUsd + preUsdcUsd;
            revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, pendingUsdValue);
        }
    }

    /**
     * @dev Internal view function to retrieve the latest ETH/USD price from the main oracle.
     * Includes staleness checks and price deviation validation for enhanced security.
     * @return price The price of 1 ETH in USD (8 decimals).
     */
    function _getEthPriceInUsd() internal view returns (uint256) {
        // Query the latest price from the AggregatorV3Interface.
        (
            /* uint80 roundID */,
            int256 price,
            /* uint startedAt */,
            uint256 updatedAt,
            /* uint80 answeredInRound */
        ) = sEthPriceFeed.latestRoundData();

        // Sanity check price (V2 inherited check).
        if (price <= 0) {
            revert Bank__TransferFailed();
        }

        // CRITICAL: Check for stale prices
        uint256 timeSinceUpdate = block.timestamp - updatedAt;
        if (timeSinceUpdate > PRICE_FEED_TIMEOUT) {
            revert Bank__StalePrice(updatedAt, block.timestamp);
        }

        // casting to 'uint256' is safe because price > 0
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 uintPrice = uint256(price);

        // Price deviation check (if we have a previous price)
        if (lastRecordedPrice > 0) {
            int256 priceDiff = price - lastRecordedPrice;
            int256 maxAllowedDiff = (lastRecordedPrice * int256(MAX_PRICE_DEVIATION_BPS)) / 10000;

            if (priceDiff > maxAllowedDiff || priceDiff < -maxAllowedDiff) {
                revert Bank__PriceDeviation(price, lastRecordedPrice);
            }
        }

        return uintPrice;
    }

    /**
     * @dev Internal helper to update the last recorded price for deviation checking.
     * Should be called after successful price retrieval.
     */
    /// @param newPrice Último precio ETH/USD aceptado (8 decimales, con signo > 0).
    function _updateRecordedPrice(int256 newPrice) internal {
        lastRecordedPrice = newPrice;
    }

    /**
     * @dev Calculates the USD value of an ETH amount (Wei) given the ETH/USD price.
     * @param ethAmount Amount in Wei (18 decimals).
     * @param ethPriceUsd Price in USD (8 decimals, from Chainlink).
     * @return The value of the ETH amount in USD (8 decimals).
     */
    function _getUsdValueFromWei(uint256 ethAmount, uint256 ethPriceUsd) private pure returns (uint256) {
        // Arithmetic Safety V5: Multiply before dividing to maintain precision.
        // (1e18 * 1e8) / 10**18 = 1e8 (USD value in 8 decimals)
        return (ethAmount * ethPriceUsd) / 10 ** 18;
    }

    /**
     * @dev Converts USDC amount (assuming 6 decimals) to USD value in Chainlink standard (8 decimals).
     * @param usdcAmount Amount in 6 decimals.
     * @return Value in USD (8 decimals).
     */
    function _getUsdValueFromUsdc(uint256 usdcAmount) private pure returns (uint256) {
        // 10^8 / 10^6 = 10^2
        return usdcAmount * 10 ** 2;
    }

    // --- View Functions (M2/M3 Requirement) ---

    /// @dev Returns the total number of deposits made to the contract.
    /// @notice Retorna el total de depósitos exitosos.
    function getDepositCount() external view returns (uint256) {
        return _depositCount;
    }

    /// @notice Dirección de WETH usada para ruteo de swaps.
    function getWethAddress() external view returns (address) {
        return WETH_TOKEN;
    }

    /// @notice Requisito de `AccessControl` para declarar soporte de interfaces.
    /// @param interfaceId Identificador de interfaz (ERC165).
    /// @return Verdadero si la interfaz es soportada.
    // Required by AccessControl inheritance
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return AccessControl.supportsInterface(interfaceId);
    }
}
