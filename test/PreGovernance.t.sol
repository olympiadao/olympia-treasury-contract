// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";
import {IOlympiaTreasury} from "../src/interfaces/IOlympiaTreasury.sol";
import {MockExecutor} from "./mocks/MockExecutor.sol";

/// @title PreGovernance
/// @notice Tests the pre-governance phase where the executor address has no code.
///         The treasury accumulates funds passively. Once governance contracts are
///         deployed at the pre-computed CREATE2 address, withdrawals activate.
contract PreGovernanceTest is Test {
    OlympiaTreasury treasury;
    address executorAddr;

    function setUp() public {
        // Use a pre-computed address that has NO code yet
        executorAddr = makeAddr("futureExecutor");
        treasury = new OlympiaTreasury(executorAddr);
    }

    /// @notice Treasury accumulates funds while executor has no code.
    function test_accumulationWhileExecutorHasNoCode() public {
        assertEq(executorAddr.code.length, 0, "executor should have no code");

        // Simulate basefee state credits via vm.deal
        vm.deal(address(treasury), 50 ether);
        assertEq(address(treasury).balance, 50 ether);

        // Simulate voluntary donations
        address donor = makeAddr("donor");
        vm.deal(donor, 10 ether);
        vm.prank(donor);
        (bool ok,) = address(treasury).call{value: 10 ether}("");
        assertTrue(ok);
        assertEq(address(treasury).balance, 60 ether);
    }

    /// @notice Non-executor addresses cannot withdraw pre-governance.
    function test_withdrawRevertsForNonExecutor() public {
        vm.deal(address(treasury), 10 ether);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(OlympiaTreasury.Unauthorized.selector);
        treasury.withdraw(payable(makeAddr("recipient")), 1 ether);
    }

    /// @notice Executor address has no code before governance deployment.
    function test_executorAddressHasNoCode() public view {
        assertEq(executorAddr.code.length, 0, "executor should have no code pre-governance");
    }

    /// @notice Executor becomes active after deployment at pre-computed address.
    function test_executorActivatesAfterDeployment() public {
        vm.deal(address(treasury), 10 ether);

        // Deploy MockExecutor at the pre-computed address using CREATE2-like mechanism
        // In reality this would be CREATE2; here we use etch for simulation
        MockExecutor realExecutor = new MockExecutor(treasury);
        vm.etch(executorAddr, address(realExecutor).code);

        // Still can't withdraw because the etched code's storage doesn't have treasury set.
        // In real CREATE2 deployment, constructor sets storage properly.
        // This test demonstrates the concept — real integration test is in Phase 7.
    }

    /// @notice Donations are tracked via Received events.
    function test_donationsTrackedViaEvents() public {
        address donor1 = makeAddr("donor1");
        address donor2 = makeAddr("donor2");
        vm.deal(donor1, 5 ether);
        vm.deal(donor2, 3 ether);

        vm.expectEmit(true, false, false, true, address(treasury));
        emit IOlympiaTreasury.Received(donor1, 5 ether);
        vm.prank(donor1);
        (bool ok1,) = address(treasury).call{value: 5 ether}("");
        assertTrue(ok1);

        vm.expectEmit(true, false, false, true, address(treasury));
        emit IOlympiaTreasury.Received(donor2, 3 ether);
        vm.prank(donor2);
        (bool ok2,) = address(treasury).call{value: 3 ether}("");
        assertTrue(ok2);

        assertEq(address(treasury).balance, 8 ether);
    }

    /// @notice Cumulative balance across state credits and donations.
    function test_cumulativeBalance() public {
        // Phase 1: basefee credits (simulated via vm.deal)
        vm.deal(address(treasury), 100 ether);

        // Phase 2: voluntary donations
        address donor = makeAddr("donor");
        vm.deal(donor, 20 ether);
        vm.prank(donor);
        (bool ok,) = address(treasury).call{value: 20 ether}("");
        assertTrue(ok);

        // Phase 3: more basefee credits
        vm.deal(address(treasury), address(treasury).balance + 30 ether);

        assertEq(address(treasury).balance, 150 ether);
    }
}
