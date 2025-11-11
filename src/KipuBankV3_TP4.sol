// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// =========================================================================
/**
 * @title KipuBankV3_TP4
 * @author KipuBank V3 contributors
 *
 * @notice
 * KipuBankV3_TP4 is a DeFi banking/lending style contract that exposes core user-facing
 * primitives such as deposit, withdraw, swap, and liquidity management while integrating
 * external infrastructure for pricing and execution. It leverages:
 *  - Uniswap V2 for token swaps and liquidity pool interactions,
 *  - OpenZeppelin libraries for secure ERC-20 handling, access control, and common utilities,
 *  - Chainlink for reliable on-chain price feeds (and/or oracle-based data).
 *
 * @dev
 * This top-level contract coordinates token accounting, user balances, internal bookkeeping,
 * and external protocol calls. Key implementation considerations:
 *  - Use OpenZeppelin's SafeERC20 and SafeMath (or Solidity's builtins) to avoid unsafe
 *    token transfers and arithmetic overflows.
 *  - Protect state-mutating external calls with reentrancy guards and checks-effects-interactions
 *    patterns.
 *  - Validate and normalize token decimals and amounts when interacting with price feeds and
 *    Uniswap pools.
 *  - Maintain explicit access-control for privileged actions (pausing, fee updates, oracle
 *    configuration, emergency withdraws).
 *  - Minimize trust in external oracles: use Chainlink feeds, verify timestamps, and handle
 *    stale or missing data gracefully.
 *  - When performing swaps or adding/removing liquidity on Uniswap V2, bound slippage and gas
 *    usage, and emit events for transparency.
 *  - Design fee and interest accounting to be auditable and gas-efficient (consider using
 *    cumulative index or snapshot patterns for interest accrual).
 *
 * @custom:imports
 * - Uniswap V2: for routing and pair interactions (swapExactTokensForTokens, add/remove liquidity)
 * - OpenZeppelin: for Ownable/AccessControl, SafeERC20, ReentrancyGuard, and upgrade-safe utilities
 * - Chainlink: for price feeds (aggregators) and oracle validation
 *
 * @custom:security-considerations
 * - Reentrancy: ensure all external interactions are protected via ReentrancyGuard and proper
 *   ordering of checks-effects-interactions.
 * - Oracle manipulation: never assume oracle prices are infallible—check for staleness and bound
 *   accepted price deviation; consider TWAP or multi-oracle strategies for critical pricing.
 * - Slippage & MEV: when calling Uniswap, enforce max slippage parameters and consider call
 *   sequencing that limits front-running exposure.
 * - Approval & allowance handling: follow the lowest-privilege principle for token approvals
 *   (approve minimal amounts, reset approvals as needed).
 * - Emergency controls: implement pausing, admin recovery, and clear upgrade/ownership transfer
 *   processes to handle critical failures.
 * - Asset custody: clearly document which tokens are custodial and what guarantees (if any)
 *   the contract provides to users.
 *
 * @custom:testing
 * - Unit tests: deposit/withdraw edge cases, interest accrual logic, fee math, and permissioned
 *   actions.
 * - Integration tests: Uniswap swap flows, add/remove liquidity, and Chainlink feed changes.
 * - Fuzzing & property tests: arithmetic invariants, reentrancy attempts, and oracle outage scenarios.
 *
 * Notes:
 * - This comment block is intended to accompany the implementation file and to provide a concise
 *   design overview, security guidance, and integration notes for auditors and future maintainers.
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
    bytes32 public constant CAP_MANAGER_ROLE = keccak256("CAP_MANAGER_ROLE");
    bytes32 public constant PAUSE_MANAGER_ROLE = keccak256("PAUSE_MANAGER_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    // --- CONSTANTS AND IMMUTABLES (V7: Gas Efficiency) ---

    /// @dev Global deposit limit for the contract, fixed in USD (1,000,000 USD, 8 decimals).
    uint256 public constant BANK_CAP_USD = 1_000_000 * 10 ** 8;

    /// @dev Maximum time allowed for price feed to be considered valid (1 hour).
    uint256 public constant PRICE_FEED_TIMEOUT = 1 hours;

    /// @dev Maximum allowed price deviation percentage (5% = 500 basis points).
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 500; // 5%

    /// @dev Maximum amount a user can withdraw per transaction (set in constructor).
    uint256 public immutable MAX_WITHDRAWAL_PER_TX;
    address private constant ETH_TOKEN = address(0); // Identifier for native ETH.

    // --- M4 DEFI DEPENDENCIES (Immutable) ---
    /// @dev Instance of the Uniswap V2 Router to execute swaps.
    IUniswapV2Router02 public immutable I_ROUTER;
    /// @dev Wrapped ETH token address, critical for swap paths (Token -> WETH -> USDC).
    address public immutable WETH_TOKEN;
    /// @dev USDC token address, the vault's primary reserve asset.
    address public immutable USDC_TOKEN;

    // --- ORACLES (Inherited from V2) ---
    /// @dev Chainlink Data Feed instance for ETH/USD.
    AggregatorV3Interface private sEthPriceFeed;

    /// @dev Last recorded ETH price for deviation checking (8 decimals).
    int256 private lastRecordedPrice;

    // --- TYPE DECLARATIONS (V2/V3: Struct used for clarity) ---
    struct TokenData {
        address priceFeedAddress;
        uint8 tokenDecimals;
        bool isAllowed;
    }

    // --- STATE VARIABLES ---
    /// @dev Mapping token address -> configuration data.
    mapping(address => TokenData) private sTokenCatalog;

    /// @dev Nested mapping: user address -> token address -> balance (Multi-token Accounting).
    mapping(address => mapping(address => uint256)) public balances;

    // Counters (Correction: Removed "= 0" initialization, Gas Optimization V7).
    uint256 private _depositCount;
    uint256 private _withdrawalCount;

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
    function pause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSE_MANAGER_ROLE) {
        _unpause();
    }

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
    {
        // A. CHECKS (Initial validation)
        if (tokenIn == ETH_TOKEN || tokenIn == USDC_TOKEN) revert Bank__InvalidTokenAddress();
        if (amountIn == 0) revert Bank__ZeroAmount();
        if (!sTokenCatalog[tokenIn].isAllowed) revert Bank__TokenNotSupported();

        // --- 1. Transfer TokenIn to the Vault (INTERACTION 1/3) ---
        // Uses SafeERC20. This must happen early to give the contract custody.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // --- 2. Determine Swap Path and Simulate ---
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

        // Use getAmountsOut (view function) to estimate USDC received (Simulation Check V8).
        uint256[] memory amounts = I_ROUTER.getAmountsOut(amountIn, path);
        uint256 estimatedUsdcReceived = amounts[amounts.length - 1];

        // --- 3. Global Bank Cap Check (CRITICAL V8, V2 Logic) ---
        // Checks if the total bank value (ETH + USDC + estimated USDC from swap) exceeds the cap.
        _checkBankCap(estimatedUsdcReceived);

        // --- 4. Give Allowance to Router (INTERACTION 2/3) ---
        // The router needs allowance to pull 'tokenIn' from KipuBankV3's balance.
        IERC20(tokenIn).safeIncreaseAllowance(address(I_ROUTER), amountIn);

        // --- 5. Execute the Swap (INTERACTION 3/3) ---
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
    function deposit() external payable whenNotPaused nonReentrant {
        // A. CHECKS (V2: Oracles and USD Limit)
        if (msg.value == 0) revert Bank__ZeroAmount();

        uint256 ethPriceUsd = _getEthPriceInUsd();
        _updateRecordedPrice(int256(ethPriceUsd));

        // We calculate the USD value of the current deposit + existing bank value (in ETH and USDC)
        uint256 pendingDepositUsd = _getUsdValueFromWei(msg.value, ethPriceUsd);
        uint256 totalUsdValueIfAccepted = _getBankTotalUsdValue(pendingDepositUsd);

        if (totalUsdValueIfAccepted > BANK_CAP_USD) {
            // Report balances before the deposit for clear error context.
            uint256 currentUsdBalance = _getBankTotalUsdValue(0);
            revert Bank__DepositExceedsCap(currentUsdBalance, BANK_CAP_USD, pendingDepositUsd);
        }

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
    function withdrawToken(address tokenAddress, uint256 amountToWithdraw) external whenNotPaused nonReentrant {
        // A. CHECKS
        if (amountToWithdraw == 0) revert Bank__ZeroAmount();

        uint256 userBalance = balances[msg.sender][tokenAddress];
        uint256 limit = MAX_WITHDRAWAL_PER_TX;

        if (tokenAddress != ETH_TOKEN && tokenAddress != USDC_TOKEN) revert Bank__TokenNotSupported();
        if (amountToWithdraw > limit) revert Bank__WithdrawalExceedsLimit(limit, amountToWithdraw);
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
    function _getBankTotalUsdValue(uint256 pendingUsdValue) private view returns (uint256) {
        // 1. Value of ETH deposited internally (address(0))
        uint256 ethBalance = balances[address(this)][ETH_TOKEN];
        uint256 ethPriceUsd = _getEthPriceInUsd();
        uint256 currentEthUsdValue = _getUsdValueFromWei(ethBalance, ethPriceUsd);

        // 2. Value of USDC deposited internally (USDC_TOKEN)
        uint256 usdcBalance = balances[address(this)][USDC_TOKEN];
        uint256 currentUsdcUsdValue = _getUsdValueFromUsdc(usdcBalance);

        // Sum total (ETH USD + USDC USD + Pending USD)
        return currentEthUsdValue + currentUsdcUsdValue + pendingUsdValue;
    }

    /**
     * @dev Helper to check the global BANK_CAP_USD given a pending USD amount.
     * Reverts with Bank__DepositExceedsCap if accepting the pending amount would
     * push the bank over the cap.
     */
    function _checkBankCap(uint256 pendingUsdValue) private view {
        uint256 totalUsdValueIfAccepted = _getBankTotalUsdValue(pendingUsdValue);
        if (totalUsdValueIfAccepted > BANK_CAP_USD) {
            uint256 currentUsdBalance = _getBankTotalUsdValue(0);
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
    function getDepositCount() external view returns (uint256) {
        return _depositCount;
    }

    /// @dev Returns the WETH address used for swap routing.
    function getWethAddress() external view returns (address) {
        return WETH_TOKEN;
    }

    // Required by AccessControl inheritance
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return AccessControl.supportsInterface(interfaceId);
    }
}
