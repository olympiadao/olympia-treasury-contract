// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OlympiaTreasury} from "../../src/OlympiaTreasury.sol";

/// @notice Attempts reentrancy on treasury.withdraw() in its receive().
contract ReentrantAttacker {
    OlympiaTreasury public treasury;
    uint256 public attackCount;

    constructor(OlympiaTreasury _treasury) {
        treasury = _treasury;
    }

    function attack(uint256 amount) external {
        treasury.withdraw(payable(address(this)), amount);
    }

    receive() external payable {
        attackCount++;
        if (attackCount < 3 && address(treasury).balance >= msg.value) {
            treasury.withdraw(payable(address(this)), msg.value);
        }
    }
}
