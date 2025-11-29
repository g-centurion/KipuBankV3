// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title KipuBankV3
 * @author G-Centurion
 * @notice Educational DeFi bank with ETH/ERC-20 deposits, automatic swap to USDC and limited withdrawals.
 * @dev Integrates Uniswap V2 for swaps and Chainlink for ETH/USD price. Applies CEI, ReentrancyGuard, RBAC and oracle validations.
 */

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract KipuBankV3 is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // 1. TYPE DECLARATIONS
    // =========================================================================

    /// @notice Configuration for a supported token.
    /// @dev Includes price feed address, decimals and allowed flag.
    struct TokenData {
        address priceFeedAddress;
        uint8 tokenDecimals;
        bool isAllowed;
    }

    // =========================================================================
    // 2. STATE VARIABLES (Roles, Constants, Immutables, Mappings)
    // =========================================================================

    /// @notice Role authorized to manage bank caps and oracles.
    bytes32 public constant CAP_MANAGER_ROLE = keccak256("CAP_MANAGER_ROLE");
    /// @notice Role authorized to pause/unpause contract operations.
    bytes32 public constant PAUSE_MANAGER_ROLE = keccak256("PAUSE_MANAGER_ROLE");
    /// @notice Role authorized to manage the token catalog.
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    /// @notice Global deposit cap for the bank in USD (8 decimals).
    uint256 public constant BANK_CAP_USD = 1_000_000 * 10 ** 8;

    /// @notice Maximum time allowed to consider oracle price valid (3 hours for robustness).
    uint256 public constant PRICE_FEED_TIMEOUT = 3 hours;

    /// @notice Maximum allowed price deviation (5%).
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 500;

    /// @notice Maximum withdrawal amount per transaction.
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

    /// @notice Catalog of supported tokens with their configuration.
    mapping(address => TokenData) private sTokenCatalog;

    /// @notice Internal balances: user => token => balance.
    mapping(address => mapping(address => uint256)) public balances;

    /// @notice Counter of successful deposits.
    uint256 private _depositCount;
    /// @notice Counter of successful withdrawals.
    uint256 private _withdrawalCount;

    // =========================================================================
    // 3. EVENTS
    // =========================================================================

    /// @dev Emitted upon a successful ETH or ERC-20 deposit or a successful swap to USDC.
    event DepositSuccessful(address indexed user, address indexed token, uint256 amount);

    /// @dev Emitted upon a successful ETH or ERC-20 withdrawal.
    event WithdrawalSuccessful(address indexed user, address indexed token, uint256 amount);

    // =========================================================================
    // 4. ERRORS
    // =========================================================================

    /// @dev Thrown when the deposited amount would exceed the global USD cap.
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

    /// @dev Thrown if the price obtained after the swap is less than the minimum expected amount.
    error Bank__SlippageTooHigh();

    /// @dev Thrown if the price obtained from Chainlink is stale.
    error Bank__StalePrice(uint256 updateTime, uint256 currentTime);

    /// @dev Thrown if the price deviates more than MAX_PRICE_DEVIATION_BPS from the last recorded price.
    error Bank__PriceDeviation(int256 currentPrice, int256 previousPrice);

    // =========================================================================
    // 5. MODIFIERS
    // =========================================================================

    /// @dev Requires amount > 0.
    modifier nonZero(uint256 amount_) {
        if (amount_ == 0) revert Bank__ZeroAmount();
        _;
    }

    /// @dev Requires supported withdrawal token (ETH or USDC).
    modifier supportedWithdrawToken(address token_) {
        if (token_ != ETH_TOKEN && token_ != USDC_TOKEN) revert Bank__TokenNotSupported();
        _;
    }

    /// @dev Requires withdrawal respects per-transaction limit.
    modifier withinWithdrawLimit(uint256 amount_) {
        if (amount_ > MAX_WITHDRAWAL_PER_TX) revert Bank__WithdrawalExceedsLimit(MAX_WITHDRAWAL_PER_TX, amount_);
        _;
    }

    /// @dev Requires allowed deposit token (not ETH, not USDC, and marked as allowed).
    modifier allowedDepositToken(address token_) {
        if (token_ == ETH_TOKEN || token_ == USDC_TOKEN) revert Bank__InvalidTokenAddress();
        if (!sTokenCatalog[token_].isAllowed) revert Bank__TokenNotSupported();
        _;
    }

    // =========================================================================
    // 6. FUNCTIONS (Constructor, External, Internal, View)
    // =========================================================================

    /**
     * @dev Initializes the contract with Chainlink oracle, Uniswap Router, USDC address, and withdrawal limit.
     */
    constructor(
        address ethPriceFeedAddress_,
        uint256 maxWithdrawalAmount_,
        address routerAddress_,
        address usdcAddress_
    ) {
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

        sTokenCatalog[USDC_TOKEN] = TokenData({
            priceFeedAddress: address(0),
            tokenDecimals: 6,
            isAllowed: true
        });
        sTokenCatalog[ETH_TOKEN] =
            TokenData({priceFeedAddress: ethPriceFeedAddress_, tokenDecimals: 18, isAllowed: true});
    }

    // --- ADMIN FUNCTIONS ---

    /// @notice Pauses the contract (emergency). Only `PAUSE_MANAGER_ROLE`.
    function pause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract. Only `PAUSE_MANAGER_ROLE`.
    function unpause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _unpause();
    }

    /// @notice Updates the ETH/USD oracle address. Only `CAP_MANAGER_ROLE`.
    function setEthPriceFeedAddress(address newAddress) external onlyRole(CAP_MANAGER_ROLE) {
        sEthPriceFeed = AggregatorV3Interface(newAddress);
    }

    /**
     * @notice Adds or updates a supported token in the bank's token catalog.
     */
    function addOrUpdateToken(address token, address priceFeed, uint8 decimals) external onlyRole(TOKEN_MANAGER_ROLE) {
        if (token == address(0)) revert Bank__InvalidTokenAddress();
        sTokenCatalog[token] = TokenData({priceFeedAddress: priceFeed, tokenDecimals: decimals, isAllowed: true});
    }

    // --- CORE FUNCTIONS ---

    /**
     * @notice Deposits ERC-20 token and automatically swaps it to USDC via Uniswap V2.
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
            path[0] = WETH_TOKEN;
            path[1] = USDC_TOKEN;
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WETH_TOKEN;
            path[2] = USDC_TOKEN;
        }

        uint256[] memory amounts = I_ROUTER.getAmountsOut(amountIn, path);
        uint256 ethPriceUsd = _getEthPriceInUsd();
        _checkBankCap(amounts[amounts.length - 1], ethPriceUsd);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeIncreaseAllowance(address(I_ROUTER), amountIn);

        uint256[] memory actualAmounts = I_ROUTER.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        uint256 usdcReceived = actualAmounts[actualAmounts.length - 1];
        if (usdcReceived < amountOutMin) revert Bank__SlippageTooHigh();

        unchecked {
            balances[msg.sender][USDC_TOKEN] += usdcReceived;
            _depositCount++;
        }

        emit DepositSuccessful(msg.sender, USDC_TOKEN, usdcReceived);
    }

    /**
     * @notice Deposits ETH to the bank.
     */
    function deposit() external payable whenNotPaused nonReentrant nonZero(msg.value) {
        uint256 ethPriceUsd = _getEthPriceInUsd();
        _updateRecordedPrice(int256(ethPriceUsd));

        uint256 pendingDepositUsd = _getUsdValueFromWei(msg.value, ethPriceUsd);
        _checkEthDepositCap(pendingDepositUsd, ethPriceUsd);

        unchecked {
            balances[msg.sender][ETH_TOKEN] += msg.value;
            _depositCount++;
        }

        emit DepositSuccessful(msg.sender, ETH_TOKEN, msg.value);
    }

    /**
     * @notice Withdraws ETH or USDC from the bank.
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

        unchecked {
            balances[msg.sender][tokenAddress] = userBalance - amountToWithdraw;
        }
        _withdrawalCount++;

        if (tokenAddress == ETH_TOKEN) {
            (bool success,) = payable(msg.sender).call{value: amountToWithdraw}("");
            if (!success) revert Bank__TransferFailed();
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, amountToWithdraw);
        }

        emit WithdrawalSuccessful(msg.sender, tokenAddress, amountToWithdraw);
    }

    // --- INTERNAL & VIEW FUNCTIONS ---

    /**
     * @dev Calculates total bank value in USD including pending deposit.
     * @param pendingUsdValue Pending deposit value in USD (8 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals).
     * @return Total USD value.
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
     * @param pendingUsdValue Pending deposit value in USD (8 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals).
     */
    function _checkBankCap(uint256 pendingUsdValue, uint256 ethPriceUsd) private view {
        uint256 currentUsdBalance = _getBankTotalUsdValue(0, ethPriceUsd);
        unchecked {
            uint256 projectedTotal = currentUsdBalance + pendingUsdValue;
            if (projectedTotal > BANK_CAP_USD) {
                revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, pendingUsdValue);
            }
        }
    }

    /**
     * @dev Checks ETH deposit cap accounting for msg.value already in balance.
     * @param pendingUsdValue Pending ETH deposit value in USD (8 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals).
     */
    function _checkEthDepositCap(uint256 pendingUsdValue, uint256 ethPriceUsd) private view {
        uint256 preEthBalance = address(this).balance - msg.value;
        uint256 preEthUsd = _getUsdValueFromWei(preEthBalance, ethPriceUsd);
        uint256 preUsdcUsd = _getUsdValueFromUsdc(IERC20(USDC_TOKEN).balanceOf(address(this)));
        uint256 currentUsdBalance = preEthUsd + preUsdcUsd;
        unchecked {
            uint256 projectedTotal = currentUsdBalance + pendingUsdValue;
            if (projectedTotal > BANK_CAP_USD) {
                revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, pendingUsdValue);
            }
        }
    }

    /**
     * @dev Retrieves latest ETH/USD price from Chainlink oracle with validation.
     * @return uintPrice ETH price in USD (8 decimals).
     */
    function _getEthPriceInUsd() internal view returns (uint256 uintPrice) {
        (, int256 price,, uint256 updatedAt,) = sEthPriceFeed.latestRoundData();

        if (price <= 0) revert Bank__TransferFailed();

        uint256 timeSinceUpdate = block.timestamp - updatedAt;
        if (timeSinceUpdate > PRICE_FEED_TIMEOUT) {
            revert Bank__StalePrice(updatedAt, block.timestamp);
        }

        uintPrice = uint256(price);

        int256 lr = lastRecordedPrice;

        if (lr > 0) {
            int256 priceDiff = price - lr;
            int256 maxAllowedDiff = (lr * int256(MAX_PRICE_DEVIATION_BPS)) / 10000;

            if (priceDiff > maxAllowedDiff || priceDiff < -maxAllowedDiff) {
                revert Bank__PriceDeviation(price, lr);
            }
        }
        return uintPrice;
    }

    /**
     * @dev Updates last recorded price for deviation checking.
     * @param newPrice Latest accepted ETH/USD price (8 decimals).
     */
    function _updateRecordedPrice(int256 newPrice) internal {
        lastRecordedPrice = newPrice;
    }

    /**
     * @dev Converts ETH amount to USD value.
     * @param ethAmount Amount in Wei (18 decimals).
     * @param ethPriceUsd ETH price in USD (8 decimals).
     * @return USD value (8 decimals).
     */
    function _getUsdValueFromWei(uint256 ethAmount, uint256 ethPriceUsd) private pure returns (uint256) {
        return (ethAmount * ethPriceUsd) / 10 ** 18;
    }

    /**
     * @dev Converts USDC amount to USD value.
     * @param usdcAmount Amount in USDC (6 decimals).
     * @return USD value (8 decimals).
     */
    function _getUsdValueFromUsdc(uint256 usdcAmount) private pure returns (uint256) {
        return usdcAmount * 10 ** 2;
    }

    /**
     * @notice Returns total number of successful deposits.
     * @return depositCount The total number of deposits recorded.
     */
    function getDepositCount() external view returns (uint256) {
        return _depositCount;
    }

    /**
     * @notice Returns number of successful withdrawals.
     * @return withdrawalCount The total number of withdrawals recorded.
     */
    function getWithdrawalCount() external view returns (uint256) {
        return _withdrawalCount;
    }

    /**
     * @notice Returns WETH address used for swap routing.
     * @return weth The canonical WETH token address configured in the router.
     */
    function getWethAddress() external view returns (address) {
        return WETH_TOKEN;
    }

    /**
     * @notice Declares support for AccessControl interfaces.
     * @param interfaceId Interface identifier (ERC165).
     * @return True if interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return AccessControl.supportsInterface(interfaceId);
    }
}
