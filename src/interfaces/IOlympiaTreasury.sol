// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IOlympiaTreasury
/// @notice ECIP-1112 minimal treasury interface.
interface IOlympiaTreasury {
    event Withdrawal(address indexed to, uint256 amount);
    event Received(address indexed from, uint256 amount);

    function executor() external view returns (address);
    function withdraw(address payable to, uint256 amount) external;
}
