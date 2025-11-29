// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title KipuBankV3
 * @author G-Centurion
 * @notice Educational DeFi bank with ETH/ERC-20 deposits, automatic swap to USDC and limited withdrawals.
 * @dev Integrates Uniswap V2 for swaps and Chainlink for ETH/USD price. Applies CEI, ReentrancyGuard, RBAC and oracle validations.
 * @dev Este contrato implementa seguridad multi-capa: límites de retiro, caps globales, validación de oracles y roles de acceso.
 * @custom:security Para reportar vulnerabilidades contactar a: security@kipubank.example (educacional)
 * @custom:experimental Este es un contrato educativo desarrollado en el marco del curso EthKipu - Talento Tech.
 */

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// ========= Errors (file scope for test selector access) =========
/// @dev Thrown when the deposited amount would exceed the global USD cap.
/// @param currentBalanceUsd Bank USD value before the attempted deposit.
/// @param bankCapUsd The configured global cap in USD (8 decimals).
/// @param attemptedDepositUsd USD value (8 decimals) of the pending deposit.
error Bank__DepositExceedsCap(uint256 currentBalanceUsd, uint256 bankCapUsd, uint256 attemptedDepositUsd);
/// @dev Thrown when the requested withdrawal amount exceeds the per-transaction limit.
/// @param limit The maximum allowed withdrawal per transaction.
/// @param requested The amount the user attempted to withdraw.
error Bank__WithdrawalExceedsLimit(uint256 limit, uint256 requested);
/// @dev Thrown when the user attempts to withdraw more than their available balance.
/// @param available The user's current balance.
/// @param requested The amount the user attempted to withdraw.
error Bank__InsufficientBalance(uint256 available, uint256 requested);
/// @dev Thrown when a transfer (ETH or ERC-20) fails.
error Bank__TransferFailed();
/// @dev Thrown when an invalid token address (like address(0)) is used in an ERC-20 context.
error Bank__InvalidTokenAddress();
/// @dev Thrown when a zero amount is provided to a function that expects > 0.
error Bank__ZeroAmount();
/// @dev Thrown when a token is not supported by the bank's token catalog.
error Bank__TokenNotSupported();
/// @dev Thrown if the price obtained after the swap is less than the minimum expected amount.
error Bank__SlippageTooHigh();
/// @dev Thrown if the price obtained from Chainlink is stale.
/// @param updateTime Timestamp returned by the oracle for the last price update.
/// @param currentTime `block.timestamp` at validation time.
error Bank__StalePrice(uint256 updateTime, uint256 currentTime);
/// @dev Thrown if the price deviates more than MAX_PRICE_DEVIATION_BPS from the last recorded price.
/// @param currentPrice The newly fetched price.
/// @param previousPrice The previously recorded price.
error Bank__PriceDeviation(int256 currentPrice, int256 previousPrice);

// ========= Events (file scope for test emission checks) =========
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

contract KipuBankV3 is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========= Roles =========
    /// @notice Role authorized to manage bank caps and oracles.
    bytes32 public constant CAP_MANAGER_ROLE = keccak256("CAP_MANAGER_ROLE");
    /// @notice Role authorized to pause/unpause contract operations.
    bytes32 public constant PAUSE_MANAGER_ROLE = keccak256("PAUSE_MANAGER_ROLE");
    /// @notice Role authorized to manage the token catalog.
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    // ========= Constants / Immutables =========
    /// @notice Global deposit cap for the bank in USD (8 decimals).
    uint256 public constant BANK_CAP_USD = 1_000_000 * 10 ** 8;
    /// @notice Maximum time allowed to consider oracle price valid (3 hours for robustness).
    uint256 public constant PRICE_FEED_TIMEOUT = 3 hours;
    /// @notice Maximum allowed price deviation (5%).
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 500;
    /// @notice Maximum withdrawal amount per transaction (immutable set in constructor).
    uint256 public immutable MAX_WITHDRAWAL_PER_TX;

    /// @notice Identifier for native ETH (address(0)).
    address private constant ETH_TOKEN = address(0);

    /// @notice Uniswap V2 Router used for token swaps.
    IUniswapV2Router02 public immutable I_ROUTER;
    /// @notice WETH address used in swap routes.
    address public immutable WETH_TOKEN;
    /// @notice USDC address (main reserve asset of the bank).
    address public immutable USDC_TOKEN;

    /// @notice Chainlink ETH/USD price feed.
    AggregatorV3Interface private sEthPriceFeed;
    /// @notice Last recorded ETH/USD price (8 decimals) for deviation validation.
    int256 private lastRecordedPrice;

    /// @notice Configuration for a supported token.
    /// @dev Includes price feed address, decimals and allowed flag.
    struct TokenData {address priceFeedAddress; uint8 tokenDecimals; bool isAllowed;}
    /// @notice Catalog of supported tokens with their configuration.
    mapping(address => TokenData) private sTokenCatalog;
    /// @notice Internal balances: user => token => balance.
    mapping(address => mapping(address => uint256)) public balances;
    /// @notice Counter of successful deposits.
    uint256 private _depositCount;
    /// @notice Counter of successful withdrawals.
    uint256 private _withdrawalCount;

    /*//////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////*/

    /**
     * @notice Ensures an amount greater than zero.
     * @dev Revierte con Bank__ZeroAmount si el monto es cero, previniendo operaciones vacías.
     * @param amount_ The amount provided by caller that must be > 0.
     */
    modifier nonZero(uint256 amount_) {
        if (amount_ == 0) revert Bank__ZeroAmount();
        _;
    }
    /**
     * @notice Ensures token is ETH or USDC for withdrawals.
     * @dev Solo permite retiros de ETH (address(0)) o USDC. Revierte Bank__TokenNotSupported para otros tokens.
     * @param token_ Token address requested for withdrawal.
     */
    modifier supportedWithdrawToken(address token_) {
        if (token_ != ETH_TOKEN && token_ != USDC_TOKEN) revert Bank__TokenNotSupported();
        _;
    }
    /**
     * @notice Ensures withdrawal does not exceed per-transaction limit.
     * @dev Valida que el monto solicitado no exceda MAX_WITHDRAWAL_PER_TX para prevenir drenajes masivos.
     * @param amount_ Requested withdrawal amount that must be <= MAX_WITHDRAWAL_PER_TX.
     */
    modifier withinWithdrawLimit(uint256 amount_) {
        if (amount_ > MAX_WITHDRAWAL_PER_TX) revert Bank__WithdrawalExceedsLimit(MAX_WITHDRAWAL_PER_TX, amount_);
        _;
    }
    /**
     * @notice Ensures token is allowed for deposit and not ETH/USDC.
     * @dev Valida que el token esté registrado en sTokenCatalog y sea distinto de ETH/USDC (que tienen flujos dedicados).
     * @param token_ ERC-20 token being deposited, must be in catalog and isAllowed=true.
     */
    modifier allowedDepositToken(address token_) {
        if (token_ == ETH_TOKEN || token_ == USDC_TOKEN) revert Bank__InvalidTokenAddress();
        if (!sTokenCatalog[token_].isAllowed) revert Bank__TokenNotSupported();
        _;
    }

    /*//////////////////////////////////////////////////
                       CONSTRUCTOR
    //////////////////////////////////////////////////*/

    /**
     * @notice Initializes core configuration and grants all roles to deployer.
     * @dev Registra USDC y ETH en el catálogo de tokens, configura inmutables y otorga roles administrativos.
     * @param ethPriceFeedAddress_ Address of the ETH/USD Chainlink oracle (must not be address(0)).
     * @param maxWithdrawalAmount_ Maximum amount a user can withdraw per transaction (immutable).
     * @param routerAddress_ Address of the UniswapV2Router02 for token swaps (must not be address(0)).
     * @param usdcAddress_ Address of the USDC token, main reserve asset (must not be address(0)).
     */
    constructor(address ethPriceFeedAddress_, uint256 maxWithdrawalAmount_, address routerAddress_, address usdcAddress_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CAP_MANAGER_ROLE, msg.sender);
        _grantRole(PAUSE_MANAGER_ROLE, msg.sender);
        _grantRole(TOKEN_MANAGER_ROLE, msg.sender);
        if (routerAddress_ == address(0) || usdcAddress_ == address(0) || ethPriceFeedAddress_ == address(0)) {
            revert Bank__InvalidTokenAddress();
        }
        sEthPriceFeed = AggregatorV3Interface(ethPriceFeedAddress_);
        MAX_WITHDRAWAL_PER_TX = maxWithdrawalAmount_;
        I_ROUTER = IUniswapV2Router02(routerAddress_);
        USDC_TOKEN = usdcAddress_;
        WETH_TOKEN = I_ROUTER.WETH();
        sTokenCatalog[USDC_TOKEN] = TokenData({priceFeedAddress: address(0), tokenDecimals: 6, isAllowed: true});
        sTokenCatalog[ETH_TOKEN] = TokenData({priceFeedAddress: ethPriceFeedAddress_, tokenDecimals: 18, isAllowed: true});
    }

    /*//////////////////////////////////////////////////
                    EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @notice Pauses the contract (emergency).
     * @dev Only accounts with PAUSE_MANAGER_ROLE can invoke. Detiene depósitos, retiros y swaps.
     */
    function pause() external onlyRole(PAUSE_MANAGER_ROLE) { _pause(); }

    /**
     * @notice Unpauses the contract.
     * @dev Only accounts with PAUSE_MANAGER_ROLE can invoke. Restablece operaciones normales.
     */
    function unpause() external onlyRole(PAUSE_MANAGER_ROLE) { _unpause(); }
    /**
     * @notice Updates the ETH/USD oracle address.
     * @dev Only accounts with CAP_MANAGER_ROLE can invoke. No valida si es un feed válido, debe usarse con precaución.
     * @param newAddress The new Chainlink ETH/USD feed address.
     */
    function setEthPriceFeedAddress(address newAddress) external onlyRole(CAP_MANAGER_ROLE) {
        sEthPriceFeed = AggregatorV3Interface(newAddress);
    }

    /**
     * @notice Adds or updates a supported token in the bank's token catalog.
     * @dev Restricted to accounts with TOKEN_MANAGER_ROLE. Marca token como permitido para depósito/swap.
     * @param token Address of the token to register (must not be address(0)).
     * @param priceFeed Address of the Chainlink price feed for the token (can be address(0) if not used).
     * @param decimals Token decimals (typically 6, 8 or 18).
     */
    function addOrUpdateToken(address token, address priceFeed, uint8 decimals) external onlyRole(TOKEN_MANAGER_ROLE) {
        if (token == address(0)) revert Bank__InvalidTokenAddress();
        sTokenCatalog[token] = TokenData({priceFeedAddress: priceFeed, tokenDecimals: decimals, isAllowed: true});
    }

    /**
     * @notice Deposits ERC-20 token and automatically swaps it to USDC via Uniswap V2.
     * @dev Follows CEI pattern. Valida cap global, transfiere tokens del usuario, aprueba router y ejecuta swap.
     * @dev Ruta de swap: tokenIn → WETH → USDC (o directo WETH → USDC si tokenIn es WETH).
     * @dev Emite DepositSuccessful con el monto final de USDC recibido.
     * @param tokenIn Address of the ERC-20 token to deposit (must be in catalog and allowed).
     * @param amountIn Amount of tokenIn to deposit (must be > 0).
     * @param amountOutMin Minimum amount of USDC expected to protect against slippage (6 decimals).
     * @param deadline Unix timestamp deadline for the swap (must be >= block.timestamp).
     */
    function depositAndSwapERC20(address tokenIn, uint256 amountIn, uint256 amountOutMin, uint48 deadline)
        external
        whenNotPaused
        nonReentrant
        allowedDepositToken(tokenIn)
        nonZero(amountIn)
    {
        address[] memory path;
        if (tokenIn == WETH_TOKEN) {
            path = new address[](2);
            path[0] = WETH_TOKEN; path[1] = USDC_TOKEN;
        } else {
            path = new address[](3);
            path[0] = tokenIn; path[1] = WETH_TOKEN; path[2] = USDC_TOKEN;
        }
        uint256[] memory amounts = I_ROUTER.getAmountsOut(amountIn, path);
        uint256 ethPriceUsd = _getEthPriceInUsd();
        _checkBankCap(amounts[amounts.length - 1], ethPriceUsd);
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeIncreaseAllowance(address(I_ROUTER), amountIn);
        uint256[] memory actualAmounts = I_ROUTER.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), deadline);
        uint256 usdcReceived = actualAmounts[actualAmounts.length - 1];
        if (usdcReceived < amountOutMin) revert Bank__SlippageTooHigh();
        unchecked { balances[msg.sender][USDC_TOKEN] += usdcReceived; _depositCount++; }
        emit DepositSuccessful(msg.sender, USDC_TOKEN, usdcReceived);
    }

    /**
     * @notice Deposits ETH to the bank.
     * @dev Follows CEI pattern. Obtiene precio ETH/USD de Chainlink, valida cap global (restando msg.value del balance).
     * @dev Actualiza lastRecordedPrice para validación de desviación en futuros depósitos.
     * @dev Emite DepositSuccessful con el monto depositado en Wei.
     */
    function deposit() external payable whenNotPaused nonReentrant nonZero(msg.value) {
        uint256 ethPriceUsd = _getEthPriceInUsd();
        _updateRecordedPrice(int256(ethPriceUsd));
        uint256 pendingDepositUsd = _getUsdValueFromWei(msg.value, ethPriceUsd);
        _checkEthDepositCap(pendingDepositUsd, ethPriceUsd);
        unchecked { balances[msg.sender][ETH_TOKEN] += msg.value; _depositCount++; }
        emit DepositSuccessful(msg.sender, ETH_TOKEN, msg.value);
    }

    /**
     * @notice Withdraws ETH or USDC from the bank.
     * @dev Follows CEI pattern. Valida balance, actualiza estado, luego transfiere (Pull over Push para ETH).
     * @dev Usa low-level call para ETH y SafeERC20 para tokens ERC-20.
     * @dev Emite WithdrawalSuccessful tras transferencia exitosa.
     * @param tokenAddress Address of the token to withdraw (address(0) for ETH, USDC address for USDC).
     * @param amountToWithdraw Amount to withdraw (must be > 0 and <= MAX_WITHDRAWAL_PER_TX and <= user balance).
     */
    function withdrawToken(address tokenAddress, uint256 amountToWithdraw)
        external
        whenNotPaused
        nonReentrant
        nonZero(amountToWithdraw)
        supportedWithdrawToken(tokenAddress)
        withinWithdrawLimit(amountToWithdraw)
    {
        uint256 userBalance = balances[msg.sender][tokenAddress];
        if (userBalance < amountToWithdraw) revert Bank__InsufficientBalance(userBalance, amountToWithdraw);
        unchecked { balances[msg.sender][tokenAddress] = userBalance - amountToWithdraw; }
        _withdrawalCount++;
        if (tokenAddress == ETH_TOKEN) {
            (bool success,) = payable(msg.sender).call{value: amountToWithdraw}("");
            if (!success) revert Bank__TransferFailed();
        } else { IERC20(tokenAddress).safeTransfer(msg.sender, amountToWithdraw); }
        emit WithdrawalSuccessful(msg.sender, tokenAddress, amountToWithdraw);
    }

    /*//////////////////////////////////////////////////
                   INTERNAL FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @dev Calculates total bank value in USD including pending deposit.
     * @dev Suma el valor USD de ETH en balance + USDC en balance + depósito pendiente.
     * @param pendingUsdValue Pending deposit value in USD (8 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals) obtenido del oracle.
     * @return Total USD value of the bank including pending deposit (8 decimals).
     */
    function _getBankTotalUsdValue(uint256 pendingUsdValue, uint256 ethPriceUsd) private view returns (uint256) {
        uint256 ethBalance = address(this).balance;
        uint256 currentEthUsdValue = _getUsdValueFromWei(ethBalance, ethPriceUsd);
        uint256 usdcBalance = IERC20(USDC_TOKEN).balanceOf(address(this));
        uint256 currentUsdcUsdValue = _getUsdValueFromUsdc(usdcBalance);
        return currentEthUsdValue + currentUsdcUsdValue + pendingUsdValue;
    }

    /**
     * @dev Checks if adding pending deposit would exceed bank cap.
     * @dev Revierte Bank__DepositExceedsCap si el total proyectado supera BANK_CAP_USD (1M USD).
     * @param pendingUsdValue Pending deposit value in USD (8 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals) para calcular valor actual del banco.
     */
    function _checkBankCap(uint256 pendingUsdValue, uint256 ethPriceUsd) private view {
        uint256 currentUsdBalance = _getBankTotalUsdValue(0, ethPriceUsd);
        unchecked {
            uint256 projectedTotal = currentUsdBalance + pendingUsdValue;
            if (projectedTotal > BANK_CAP_USD) revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, pendingUsdValue);
        }
    }

    /**
     * @dev Checks ETH deposit cap accounting for msg.value already in balance.
     * @dev Resta msg.value del balance ETH actual para evitar contarlo dos veces, luego valida cap.
     * @param pendingUsdValue Pending ETH deposit value in USD (8 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals) obtenido del oracle.
     */
    function _checkEthDepositCap(uint256 pendingUsdValue, uint256 ethPriceUsd) private view {
        uint256 preEthBalance = address(this).balance - msg.value;
        uint256 preEthUsd = _getUsdValueFromWei(preEthBalance, ethPriceUsd);
        uint256 preUsdcUsd = _getUsdValueFromUsdc(IERC20(USDC_TOKEN).balanceOf(address(this)));
        uint256 currentUsdBalance = preEthUsd + preUsdcUsd;
        unchecked {
            uint256 projectedTotal = currentUsdBalance + pendingUsdValue;
            if (projectedTotal > BANK_CAP_USD) revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, pendingUsdValue);
        }
    }

    /**
     * @dev Retrieves latest ETH/USD price from Chainlink oracle with validation.
     * @dev Valida: precio > 0, no stale (< 3h), desviación < 5% vs lastRecordedPrice.
     * @dev Usa única lectura de storage (SLOAD) de lastRecordedPrice para eficiencia de gas.
     * @return ethPriceUsd ETH price in USD (8 decimals).
     */
    function _getEthPriceInUsd() internal view returns (uint256 ethPriceUsd) {
        (, int256 price,, uint256 updatedAt,) = sEthPriceFeed.latestRoundData();
        if (price <= 0) revert Bank__TransferFailed();
        uint256 timeSinceUpdate = block.timestamp - updatedAt;
        if (timeSinceUpdate > PRICE_FEED_TIMEOUT) revert Bank__StalePrice(updatedAt, block.timestamp);
        int256 lr = lastRecordedPrice; // single SLOAD
        uint256 uintPrice = uint256(price);
        if (lr > 0) {
            int256 priceDiff = price - lr;
            int256 maxAllowedDiff = (lr * int256(MAX_PRICE_DEVIATION_BPS)) / 10000;
            if (priceDiff > maxAllowedDiff || priceDiff < -maxAllowedDiff) revert Bank__PriceDeviation(price, lr);
        }
        return uintPrice;
    }

    /**
     * @dev Updates last recorded price for deviation checking.
     * @dev Llamado tras validar precio exitosamente en deposit() para futuras comparaciones.
     * @param newPrice Latest accepted ETH/USD price (8 decimals) obtenido de Chainlink.
     */
    function _updateRecordedPrice(int256 newPrice) internal { lastRecordedPrice = newPrice; }

    /**
     * @dev Converts ETH amount to USD value.
     * @dev Fórmula: (ethAmount * ethPriceUsd) / 10^18 para escalar de 18 decimales (Wei) a 8 decimales (USD).
     * @param ethAmount Amount in Wei (18 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals) del oracle.
     * @return usdValue USD value (8 decimals).
     */
    function _getUsdValueFromWei(uint256 ethAmount, uint256 ethPriceUsd) private pure returns (uint256 usdValue) {
        return (ethAmount * ethPriceUsd) / 10 ** 18;
    }

    /**
     * @dev Converts USDC amount to USD value.
     * @dev Escala de 6 decimales (USDC) a 8 decimales (USD) multiplicando por 10^2.
     * @param usdcAmount Amount of USDC (6 decimals).
     * @return usdValue USD value (8 decimals).
     */
    function _getUsdValueFromUsdc(uint256 usdcAmount) private pure returns (uint256 usdValue) {
        return usdcAmount * 10 ** 2; // scale 6 -> 8 decimals
    }

    /*//////////////////////////////////////////////////
                     VIEW FUNCTIONS
    //////////////////////////////////////////////////*/

    /**
     * @notice Returns number of successful deposits.
     * @dev Contador incrementado en deposit() y depositAndSwapERC20().
     * @return Total count of successful deposit operations.
     */
    function getDepositCount() external view returns (uint256) { return _depositCount; }

    /**
     * @notice Returns number of successful withdrawals.
     * @dev Contador incrementado en withdrawToken().
     * @return Total count of successful withdrawal operations.
     */
    function getWithdrawalCount() external view returns (uint256) { return _withdrawalCount; }

    /**
     * @notice Returns WETH address used for routing.
     * @dev Obtenido del router en el constructor y usado en rutas de swap.
     * @return WETH token address (immutable).
     */
    function getWethAddress() external view returns (address) { return WETH_TOKEN; }
}
