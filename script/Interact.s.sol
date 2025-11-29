// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";

/**
 * @title InteractScript
 * @notice Educational script demonstrating basic read-only interactions with the deployed contract.
 * @dev Dry-run example (no gas spent): forge script script/Interact.s.sol:InteractScript --rpc-url $RPC_URL_SEPOLIA -vvvv --dry-run
 */
contract InteractScript is Script {
    // Deployed contract address on Sepolia (update if it changes)
    address constant KIPU_BANK_ADDRESS = 0xc6d24cBbF2CCC70ef6E4EeD507fEA0F801321691;

    // USDC address on Sepolia used by the contract (for internal balance reads)
    address constant USDC_ADDRESS = 0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D; // Corrected: No invalid characters

    function run() external {
        // Load private key from environment (.env, uint with 0x prefix)
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        KipuBankV3 bank = KipuBankV3(KIPU_BANK_ADDRESS);

        // Initial reads
        console.log("==== EDUCATIONAL INTERACTION ====");
        console.log("Contract:", address(bank));
        console.log("Deployer/User:", deployer);
        console.log("Max Withdrawal Per TX:", bank.MAX_WITHDRAWAL_PER_TX());
        console.log("Router:", address(bank.I_ROUTER()));
        console.log("WETH:", bank.getWethAddress());

        // NOTE: No state-changing calls here to avoid altering on-chain state.
        // Example of how an ETH deposit would look (UNCOMMENT ONLY TO EXECUTE FOR REAL):
        // bank.deposit{ value: 0.01 ether }();
        // console.log("Simulated ETH deposit completed");

        // Conceptual example of internal balance reads (ETH = address(0))
        uint256 ethBalance = bank.balances(deployer, address(0));
        uint256 usdcBalance = bank.balances(deployer, USDC_ADDRESS);
        console.log("Internal ETH balance (wei):", ethBalance);
        console.log("Internal USDC balance (6d):", usdcBalance);

        // Admin role verification
        bytes32 DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;
        bool isAdmin = bank.hasRole(DEFAULT_ADMIN_ROLE, deployer);
        console.log("Is Admin Role:", isAdmin);

        // Conceptual example of withdrawal (DO NOT execute in educational mode):
        // bank.withdrawToken(address(0), 0.005 ether);
        // console.log("Simulated ETH withdrawal");

        vm.stopBroadcast();
        console.log("==== END INTERACTION ====");
    }
}
