// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

/**
 * @title Deploy
 * @notice Deployment script for KipuBankV3 on Sepolia testnet.
 * @dev Configures required addresses for Uniswap V2, Chainlink and tokens.
 */
contract DeployScript is Script {
    // ========== SEPOLIA TESTNET ADDRESSES ==========

    /// @dev Chainlink ETH/USD Price Feed on Sepolia (8 decimals)
    address private constant SEPOLIA_ETH_PRICE_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    /// @dev Uniswap V2 Router on Sepolia
    address private constant SEPOLIA_UNISWAP_V2_ROUTER = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;

    /// @dev USDC on Sepolia (6 decimals)
    address private constant SEPOLIA_USDC = 0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D;

    /// @dev WETH on Sepolia (retrieved from router)
    // address private constant SEPOLIA_WETH = 0xfFf9976782d46CC05630D07AE6142005F2c69f1d;

    // ========== CONFIGURATION PARAMETERS ==========

    /// @dev Max withdrawal per transaction (1 ETH)
    uint256 private constant MAX_WITHDRAWAL_PER_TX = 1 ether;

    // ========== DEPLOYMENT FUNCTION ==========

    /**
     * @notice Deploys KipuBankV3 configured for Sepolia testnet.
     * @dev Run with: forge script script/Deploy.s.sol:DeployScript --rpc-url <RPC_URL> --broadcast
     */
    function run() external {
        // Load deployer private key from .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy KipuBankV3 contract
        KipuBankV3 kipuBank = new KipuBankV3(
            SEPOLIA_ETH_PRICE_FEED, // ETH/USD Price Feed
            MAX_WITHDRAWAL_PER_TX, // Max withdrawal per transaction
            SEPOLIA_UNISWAP_V2_ROUTER, // Uniswap V2 Router
            SEPOLIA_USDC // USDC Token Address
        );

        vm.stopBroadcast();

        // ========== LOGS ==========
        console.log("========== KipuBankV3 Deployment Complete ==========");
        console.log("KipuBankV3 Contract Address:", address(kipuBank));
        console.log("ETH/USD Price Feed:", SEPOLIA_ETH_PRICE_FEED);
        console.log("Uniswap V2 Router:", SEPOLIA_UNISWAP_V2_ROUTER);
        console.log("USDC Token:", SEPOLIA_USDC);
        console.log("Max Withdrawal Per TX:", MAX_WITHDRAWAL_PER_TX);
        console.log("=================================================");
    }

    // ========== HELPER FUNCTIONS FOR MANUAL DEPLOYMENT ==========

    /**
     * @notice Helper for manual deployment without broadcast.
     * @return Deployed contract address.
     */
    function deployManual() external returns (address) {
        KipuBankV3 kipuBank =
            new KipuBankV3(SEPOLIA_ETH_PRICE_FEED, MAX_WITHDRAWAL_PER_TX, SEPOLIA_UNISWAP_V2_ROUTER, SEPOLIA_USDC);

        return address(kipuBank);
    }
}

/**
 * @title DeployMainnet
 * @notice Deployment script for KipuBankV3 on Ethereum Mainnet.
 * @dev IMPORTANT: Use only after full audit and exhaustive testing.
 */
contract DeployMainnetScript is Script {
    // ========== MAINNET ADDRESSES ==========

    /// @dev Chainlink ETH/USD Price Feed on Mainnet (8 decimals)
    address private constant MAINNET_ETH_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @dev Uniswap V2 Router on Mainnet
    address private constant MAINNET_UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /// @dev USDC on Mainnet (6 decimals)
    address private constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev Max withdrawal per transaction on Mainnet
    uint256 private constant MAX_WITHDRAWAL_PER_TX = 100 ether;

    /**
     * @notice Deploys contract on Mainnet.
     * @dev REQUIRES: Prior audit and exhaustive testnet validation.
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        KipuBankV3 kipuBank =
            new KipuBankV3(MAINNET_ETH_PRICE_FEED, MAX_WITHDRAWAL_PER_TX, MAINNET_UNISWAP_V2_ROUTER, MAINNET_USDC);

        vm.stopBroadcast();

        console.log("========== KipuBankV3 Mainnet Deployment ==========");
        console.log("KipuBankV3 Contract Address:", address(kipuBank));
        console.log("WARNING: Contract deployed on MAINNET - Verify thoroughly!");
        console.log("==================================================");
    }
}
