// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OlympiaTreasury} from "../../src/OlympiaTreasury.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title MockCoreDAO
/// @notice Simulates ECIP-1113 traditional DAO governance for core infrastructure.
///         Handles non-contentious funding: client maintenance, audits, node hosting.
///         When granted DEFAULT_ADMIN_ROLE, can also enable/disable other spending
///         pipelines (FutarchyDAO, LCurveDistributor) — representing the maturation
///         from multisig bootstrap to DAO-controlled governance.
contract MockCoreDAO {
    OlympiaTreasury public immutable treasury;

    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    event CoreInfraFunded(address indexed to, uint256 amount, string description);
    event PipelineEnabled(address indexed pipeline, string description);
    event PipelineDisabled(address indexed pipeline, string reason);

    constructor(address payable _treasury) {
        treasury = OlympiaTreasury(_treasury);
    }

    /// @notice Fund a core infrastructure item from the treasury.
    /// @param to Recipient address (developer, auditor, host).
    /// @param amount Amount in wei.
    /// @param description What the funding is for.
    function fundCoreInfra(address payable to, uint256 amount, string calldata description) external {
        treasury.withdraw(to, amount);
        emit CoreInfraFunded(to, amount, description);
    }

    /// @notice Enable a new spending pipeline by granting it WITHDRAWER_ROLE.
    ///         Requires this contract to have DEFAULT_ADMIN_ROLE on the treasury.
    /// @param pipeline Address of the new pipeline contract (FutarchyDAO, LCurve, etc.).
    /// @param description Why this pipeline is being enabled.
    function enablePipeline(address pipeline, string calldata description) external {
        treasury.grantRole(WITHDRAWER_ROLE, pipeline);
        emit PipelineEnabled(pipeline, description);
    }

    /// @notice Disable a spending pipeline by revoking its WITHDRAWER_ROLE.
    ///         Requires this contract to have DEFAULT_ADMIN_ROLE on the treasury.
    /// @param pipeline Address of the pipeline to disable.
    /// @param reason Why this pipeline is being disabled.
    function disablePipeline(address pipeline, string calldata reason) external {
        treasury.revokeRole(WITHDRAWER_ROLE, pipeline);
        emit PipelineDisabled(pipeline, reason);
    }

    /// @notice Transfer DEFAULT_ADMIN_ROLE to a successor DAO contract.
    ///         This is the key operation for DAO migration — the old DAO
    ///         authorizes the new one, then renounces its own admin role.
    /// @param successor Address of the new DAO that will become admin.
    function transferAdminTo(address successor) external {
        bytes32 adminRole = treasury.DEFAULT_ADMIN_ROLE();
        treasury.grantRole(adminRole, successor);
        treasury.renounceRole(adminRole, address(this));
    }
}
