// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOlympiaTreasury} from "./interfaces/IOlympiaTreasury.sol";

/// @title OlympiaTreasury
/// @notice ECIP-1112 compliant immutable treasury vault.
///         Receives basefee revenue via consensus-layer state credit (ECIP-1111)
///         and voluntary donations via receive(). Only the pre-computed executor
///         (OlympiaExecutor deployed via CREATE2) can withdraw funds.
/// @dev No OpenZeppelin. No roles. No admin. No upgrade path. Pure Solidity.
///      The executor address is immutable — set at construction from a
///      pre-computed CREATE2 address. Before the executor contract is deployed,
///      all withdraw() calls revert with Unauthorized (no code can call from
///      that address). Once deployed, the governance pipeline activates.
contract OlympiaTreasury is IOlympiaTreasury {
    address public immutable executor;

    error Unauthorized();
    error ZeroAddress();
    error InsufficientBalance();
    error TransferFailed();

    /// @param _executor Pre-computed CREATE2 address of OlympiaExecutor.
    constructor(address _executor) {
        if (_executor == address(0)) revert ZeroAddress();
        executor = _executor;
    }

    /// @notice Withdraw ETC from the treasury. Only callable by the executor.
    /// @param to Destination address.
    /// @param amount Amount in wei.
    function withdraw(address payable to, uint256 amount) external {
        if (msg.sender != executor) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (address(this).balance < amount) revert InsufficientBalance();

        emit Withdrawal(to, amount);

        (bool success,) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Accept direct ETH/ETC transfers (voluntary donations).
    /// @dev Basefee deposits arrive via consensus-layer state credit, not through receive().
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
