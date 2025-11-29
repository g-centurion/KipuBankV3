// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title TimelockKipuBank
 * @notice Timelock controller for KipuBankV3 governance.
 * @dev Simplified timelock enforcing a minimum delay for critical administrative operations.
 *
 * Operation flow:
 * 1. Proposer schedules an operation (e.g., updating the price feed).
 * 2. Operation remains queued for the minimum delay period.
 * 3. Executor executes after the delay has passed.
 * 4. Canceler (if configured) may cancel before execution.
 */

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// ==========================================================================
// 1. TYPE DECLARATIONS
// ==========================================================================
// (No custom structs or enums required for this timelock)

// ==========================================================================
// 2. STATE VARIABLES
// ==========================================================================
contract TimelockKipuBank is TimelockController {
    /// @notice Minimum enforced delay between scheduling and execution (2 days).
    uint256 public constant MIN_DELAY = 2 days;

    // ======================================================================
    // 3. EVENTS
    // ======================================================================
    // (Using inherited TimelockController events: CallScheduled, CallExecuted, CallCanceled)

    // ======================================================================
    // 4. ERRORS
    // ======================================================================
    // (No custom errors required for this minimal timelock wrapper)

    // ======================================================================
    // 5. MODIFIERS
    // ======================================================================
    // (No custom modifiers needed)

    // ======================================================================
    // 6. FUNCTIONS (Constructor & External Helpers)
    // ======================================================================

    /**
     * @dev Initializes the timelock with predefined role lists.
     * @param proposers Addresses allowed to schedule operations.
     * @param executors Addresses allowed to execute ready operations.
     * @param admin Admin address with initial configuration authority.
     */
    constructor(address[] memory proposers, address[] memory executors, address admin)
        TimelockController(MIN_DELAY, proposers, executors, admin)
    {}

    /**
     * @notice Schedules a price feed update on the target KipuBank contract.
     * @dev Helper to encapsulate encoding and scheduling.
     * @param kipuBankAddress Target KipuBank contract address.
     * @param newPriceFeed New Chainlink price feed address.
     */
    function proposePriceFeedChange(address kipuBankAddress, address newPriceFeed) external {
        bytes32 id = this.hashOperation(
            kipuBankAddress,
            0,
            abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed),
            bytes32(0),
            bytes32(0)
        );

        this.schedule(
            kipuBankAddress,
            0,
            abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed),
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );

        emit CallScheduled(
            id,
            0,
            kipuBankAddress,
            0,
            abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed),
            bytes32(0),
            MIN_DELAY
        );
    }

    /**
     * @notice Executes a previously scheduled price feed update.
     * @dev Must be called after the delay has elapsed.
     * @param kipuBankAddress Target KipuBank contract address.
     * @param newPriceFeed New Chainlink price feed address.
     * @param salt Optional salt used when scheduling (bytes32(0) if none).
     */
    function executePriceFeedChange(address kipuBankAddress, address newPriceFeed, bytes32 salt) external {
        this.execute(
            kipuBankAddress,
            0,
            abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed),
            bytes32(0),
            salt
        );
    }
}
