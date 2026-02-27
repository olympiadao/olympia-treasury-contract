// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OlympiaTreasury} from "../../src/OlympiaTreasury.sol";

/// @title MockFutarchyDAO
/// @notice Simulates ECIP-1117 futarchy prediction market governance.
///         Handles contentious proposals: ecosystem grants, R&D, new features.
///         In production, this would check prediction market outcomes before executing.
contract MockFutarchyDAO {
    OlympiaTreasury public immutable treasury;

    event ProposalExecuted(address indexed to, uint256 amount, string proposal);

    constructor(address payable _treasury) {
        treasury = OlympiaTreasury(_treasury);
    }

    /// @notice Execute a proposal that the prediction market approved.
    /// @param to Recipient address.
    /// @param amount Amount in wei.
    /// @param proposal Description of the approved proposal.
    function executeProposal(address payable to, uint256 amount, string calldata proposal) external {
        treasury.withdraw(to, amount);
        emit ProposalExecuted(to, amount, proposal);
    }
}
