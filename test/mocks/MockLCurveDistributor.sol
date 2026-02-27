// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OlympiaTreasury} from "../../src/OlympiaTreasury.sol";

/// @title MockLCurveDistributor
/// @notice Simulates ECIP-1115 L-curve miner incentive distribution.
///         Withdraws from treasury and distributes to miners using logarithmic
///         weighting — top miners receive more, with diminishing returns.
///         Provides predictable supplemental income as block rewards decline.
contract MockLCurveDistributor {
    OlympiaTreasury public immutable treasury;

    event Distribution(uint256 totalAmount, uint256 minerCount);
    event MinerPaid(address indexed miner, uint256 amount, uint256 rank);

    constructor(address payable _treasury) {
        treasury = OlympiaTreasury(_treasury);
    }

    /// @notice Withdraw from treasury and distribute to miners via L-curve.
    /// @param miners Array of miner addresses, ordered by hash power (highest first).
    /// @param totalAmount Total amount to withdraw and distribute.
    function distribute(address payable[] calldata miners, uint256 totalAmount) external {
        require(miners.length > 0, "LCurve: no miners");
        require(miners.length <= 100, "LCurve: too many miners");

        // Withdraw from treasury to this contract
        treasury.withdraw(payable(address(this)), totalAmount);

        // Calculate L-curve weights using integer log approximation
        // weight[i] = lnApprox(n - i), where rank 0 = top miner
        uint256 n = miners.length;
        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](n);

        for (uint256 i = 0; i < n; i++) {
            // ln(n - i) approximated as (n - i) * 1000 / (i + 1)
            // This gives a concave, monotonically decreasing curve
            weights[i] = _lnApprox(n - i);
            totalWeight += weights[i];
        }

        // Distribute proportionally
        uint256 distributed = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 share;
            if (i == n - 1) {
                // Last miner gets remainder (avoids rounding dust)
                share = totalAmount - distributed;
            } else {
                share = (totalAmount * weights[i]) / totalWeight;
            }
            distributed += share;

            (bool ok,) = miners[i].call{value: share}("");
            require(ok, "LCurve: transfer failed");
            emit MinerPaid(miners[i], share, i);
        }

        emit Distribution(totalAmount, n);
    }

    /// @dev Integer approximation of ln(x) * 1000 for x >= 1.
    ///      Uses a simple lookup + interpolation for small values.
    ///      ln(1)=0, ln(2)=693, ln(3)=1099, ln(4)=1386, ln(5)=1609
    function _lnApprox(uint256 x) internal pure returns (uint256) {
        require(x >= 1, "LCurve: ln(0) undefined");
        if (x == 1) return 1;       // floor to 1 to avoid zero weight
        if (x == 2) return 693;
        if (x == 3) return 1099;
        if (x == 4) return 1386;
        if (x == 5) return 1609;
        if (x == 6) return 1792;
        if (x == 7) return 1946;
        if (x == 8) return 2079;
        if (x == 9) return 2197;
        if (x == 10) return 2303;
        // For x > 10, approximate: ln(x) ≈ ln(10) + (x-10)/x * 1000
        // This is rough but sufficient for testing
        return 2303 + ((x - 10) * 1000) / x;
    }

    receive() external payable {}
}
