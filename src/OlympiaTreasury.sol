// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

/// @title OlympiaTreasury
/// @notice ETC Olympia treasury vault (ECIP-1112).
///         Receives basefee revenue via state credit (not transfers).
///         Role-gated withdrawal allows staged governance — deploy with
///         an admin EOA/multisig, then grant WITHDRAWER_ROLE to a DAO later.
///         Uses AccessControlDefaultAdminRules for 2-step admin transfer with delay.
/// @dev Deployed via CREATE2 for deterministic address across Mordor and mainnet.
contract OlympiaTreasury is AccessControlDefaultAdminRules {
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    event Withdrawal(address indexed to, uint256 amount);
    event Received(address indexed from, uint256 amount);

    /// @param adminTransferDelay Delay in seconds for 2-step admin transfers.
    /// @param admin Initial admin address (receives DEFAULT_ADMIN_ROLE and WITHDRAWER_ROLE).
    constructor(uint48 adminTransferDelay, address admin)
        AccessControlDefaultAdminRules(adminTransferDelay, admin)
    {
        _grantRole(WITHDRAWER_ROLE, admin);
    }

    /// @notice Withdraw ETC from the treasury.
    /// @param to Destination address.
    /// @param amount Amount in wei.
    function withdraw(address payable to, uint256 amount) external onlyRole(WITHDRAWER_ROLE) {
        require(to != address(0), "OlympiaTreasury: zero address");
        require(amount <= address(this).balance, "OlympiaTreasury: insufficient balance");

        (bool success,) = to.call{value: amount}("");
        require(success, "OlympiaTreasury: transfer failed");

        emit Withdrawal(to, amount);
    }

    /// @notice Accept direct ETH/ETC transfers (voluntary donations).
    /// @dev Basefee deposits arrive via consensus-layer state credit, not through receive().
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
