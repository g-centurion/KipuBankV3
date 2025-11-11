// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title TimelockKipuBank
 * @notice Timelock controller for KipuBankV3 governance
 * @dev Implementa un sistema de delays para cambios administrativos críticos
 *
 * Flujo de operación:
 * 1. Proposer propone un cambio (ej: cambiar precio feed)
 * 2. Transacción queda pendiente por DELAY duración
 * 3. Executor ejecuta después del delay
 * 4. Canceler puede cancelar operaciones en cualquier momento
 */

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Contrato simplificado de Timelock para KipuBankV3
 * Proporciona delays configurables para operaciones administrativas críticas
 */
contract TimelockKipuBank is TimelockController {
    /// @dev Delay mínimo entre proposición y ejecución (2 días)
    uint256 public constant MIN_DELAY = 2 days;

    /**
     * @notice Inicializa el Timelock con roles predefinidos
     * @param proposers Array de direcciones que pueden proponer cambios
     * @param executors Array de direcciones que pueden ejecutar cambios
     * @param admin Dirección del administrador del Timelock
     */
    constructor(address[] memory proposers, address[] memory executors, address admin)
        TimelockController(MIN_DELAY, proposers, executors, admin)
    {}

    /**
     * @notice Propone un cambio de precio feed
     * @dev Esta es una función auxiliar para mejorar UX
     */
    function proposePriceFeedChange(address kipuBankAddress, address newPriceFeed) external {
        bytes32 id = this.hashOperation(kipuBankAddress, 0, abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed), bytes32(0), bytes32(0));

        // Use external calls (this.) so the compiler can convert memory -> calldata for the encoded bytes
        this.schedule(kipuBankAddress, 0, abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed), bytes32(0), bytes32(0), MIN_DELAY);

        emit CallScheduled(id, 0, kipuBankAddress, 0, abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed), bytes32(0), MIN_DELAY);
    }

    /**
     * @notice Ejecuta un cambio de precio feed propuesto
     * @dev Debe ser llamado después del delay
     */
    function executePriceFeedChange(address kipuBankAddress, address newPriceFeed, bytes32 salt) external {
        this.execute(kipuBankAddress, 0, abi.encodeWithSignature("setEthPriceFeedAddress(address)", newPriceFeed), bytes32(0), salt);
    }
}
