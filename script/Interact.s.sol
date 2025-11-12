// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {KipuBankV3} from "../src/KipuBankV3_TP4.sol";

/**
 * @title InteractScript
 * @notice Script educativo para demostrar interacciones básicas contra el contrato desplegado.
 * @dev Ejecutar en modo dry-run para no gastar gas: forge script script/Interact.s.sol:InteractScript --rpc-url $RPC_URL_SEPOLIA -vvvv --dry-run
 */
contract InteractScript is Script {
    // Dirección del contrato desplegado en Sepolia (actualizar si cambia)
    address constant KIPU_BANK_ADDRESS = 0x5b7f2F853AdF9730fBA307dc2Bd2B19FF51FcDD7;

    // Dirección USDC Sepolia usada dentro del contrato (para lecturas de balance)
    address constant USDC_ADDRESS = 0x1c7d4B196CB0c6b364c3d6eB8F0708a9dA00375D;

    function run() external {
        // Obtiene clave privada desde entorno (formato uint con prefijo 0x en .env)
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        KipuBankV3 bank = KipuBankV3(KIPU_BANK_ADDRESS);

        // Lecturas iniciales
        console.log("==== INTERACCIÓN EDUCATIVA ====");
        console.log("Contrato:", address(bank));
        console.log("Deployer/Usuario:", deployer);
        console.log("Max Withdrawal Per TX:", bank.MAX_WITHDRAWAL_PER_TX());
        console.log("Router:", address(bank.I_ROUTER()));
        console.log("WETH:", bank.getWethAddress());

        // NOTA: No hacemos llamadas de escritura reales aquí para evitar afectar estado.
        // Ejemplo de cómo se haría un depósito de ETH (DESCOMENTAR SOLO SI SE DESEA EJECUTAR REAL):
        // bank.deposit{ value: 0.01 ether }();
        // console.log("Depósito ETH simulado completado");

        // Ejemplo conceptual de lectura de balance interno (ETH = address(0))
        uint256 ethBalance = bank.balances(deployer, address(0));
        uint256 usdcBalance = bank.balances(deployer, USDC_ADDRESS);
        console.log("Balance interno ETH (wei):", ethBalance);
        console.log("Balance interno USDC (6d):", usdcBalance);

        // Verificación de rol admin
        bytes32 DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;
        bool isAdmin = bank.hasRole(DEFAULT_ADMIN_ROLE, deployer);
        console.log("Is Admin Role:", isAdmin);

        // Ejemplo conceptual de retiro (NO ejecutar en modo educativo):
        // bank.withdrawToken(address(0), 0.005 ether);
        // console.log("Retiro ETH simulado");

        vm.stopBroadcast();
        console.log("==== FIN INTERACCIÓN ====");
    }
}
