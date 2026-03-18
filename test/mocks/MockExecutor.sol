// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OlympiaTreasury} from "../../src/OlympiaTreasury.sol";

/// @notice Mock executor that calls treasury.withdraw().
contract MockExecutor {
    OlympiaTreasury public treasury;

    constructor(OlympiaTreasury _treasury) {
        treasury = _treasury;
    }

    function executeWithdraw(address payable to, uint256 amount) external {
        treasury.withdraw(to, amount);
    }
}
