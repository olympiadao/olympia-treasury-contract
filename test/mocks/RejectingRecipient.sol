// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Contract that rejects ETH transfers.
contract RejectingRecipient {
    receive() external payable {
        revert("RejectingRecipient: rejected");
    }
}
