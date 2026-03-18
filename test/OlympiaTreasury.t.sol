// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";
import {IOlympiaTreasury} from "../src/interfaces/IOlympiaTreasury.sol";
import {MockExecutor} from "./mocks/MockExecutor.sol";
import {RejectingRecipient} from "./mocks/RejectingRecipient.sol";

contract OlympiaTreasuryTest is Test {
    OlympiaTreasury public treasury;
    MockExecutor public executor;
    address payable public recipient = payable(makeAddr("recipient"));

    function setUp() public {
        // Deploy executor first to get its address, then deploy treasury with that address
        // In real deployment, executor address is pre-computed via CREATE2
        address executorAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        treasury = new OlympiaTreasury(executorAddr);
        executor = new MockExecutor(treasury);
        assertEq(address(executor), executorAddr, "executor address mismatch");

        // Fund treasury
        vm.deal(address(treasury), 100 ether);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_constructor_setsExecutor() public view {
        assertEq(treasury.executor(), address(executor));
    }

    function test_constructor_rejectsZeroAddress() public {
        vm.expectRevert(OlympiaTreasury.ZeroAddress.selector);
        new OlympiaTreasury(address(0));
    }

    // =========================================================================
    // withdraw()
    // =========================================================================

    function test_withdraw_happyPath() public {
        uint256 balBefore = recipient.balance;
        executor.executeWithdraw(recipient, 1 ether);
        assertEq(recipient.balance, balBefore + 1 ether);
        assertEq(address(treasury).balance, 99 ether);
    }

    function test_withdraw_emitsWithdrawal() public {
        vm.expectEmit(true, false, false, true, address(treasury));
        emit IOlympiaTreasury.Withdrawal(recipient, 1 ether);
        executor.executeWithdraw(recipient, 1 ether);
    }

    function test_withdraw_unauthorizedEOA() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(OlympiaTreasury.Unauthorized.selector);
        treasury.withdraw(recipient, 1 ether);
    }

    function test_withdraw_unauthorizedContract() public {
        MockExecutor fakeExecutor = new MockExecutor(treasury);
        vm.expectRevert(OlympiaTreasury.Unauthorized.selector);
        fakeExecutor.executeWithdraw(recipient, 1 ether);
    }

    function test_withdraw_zeroAddress() public {
        vm.prank(address(executor));
        vm.expectRevert(OlympiaTreasury.ZeroAddress.selector);
        treasury.withdraw(payable(address(0)), 1 ether);
    }

    function test_withdraw_insufficientBalance() public {
        vm.prank(address(executor));
        vm.expectRevert(OlympiaTreasury.InsufficientBalance.selector);
        treasury.withdraw(recipient, 101 ether);
    }

    function test_withdraw_entireBalance() public {
        executor.executeWithdraw(recipient, 100 ether);
        assertEq(address(treasury).balance, 0);
        assertEq(recipient.balance, 100 ether);
    }

    function test_withdraw_zeroAmount() public {
        executor.executeWithdraw(recipient, 0);
        assertEq(address(treasury).balance, 100 ether);
    }

    function test_withdraw_transferFailed() public {
        RejectingRecipient rejector = new RejectingRecipient();
        vm.prank(address(executor));
        vm.expectRevert(OlympiaTreasury.TransferFailed.selector);
        treasury.withdraw(payable(address(rejector)), 1 ether);
    }

    // =========================================================================
    // receive()
    // =========================================================================

    function test_receive_acceptsETH() public {
        address donor = makeAddr("donor");
        vm.deal(donor, 5 ether);
        vm.prank(donor);
        (bool ok,) = address(treasury).call{value: 5 ether}("");
        assertTrue(ok);
        assertEq(address(treasury).balance, 105 ether);
    }

    function test_receive_emitsReceived() public {
        address donor = makeAddr("donor");
        vm.deal(donor, 1 ether);
        vm.expectEmit(true, false, false, true, address(treasury));
        emit IOlympiaTreasury.Received(donor, 1 ether);
        vm.prank(donor);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
    }

    // =========================================================================
    // Fuzz
    // =========================================================================

    function testFuzz_withdraw_amountBounds(uint256 amount) public {
        amount = bound(amount, 0, 100 ether);
        uint256 balBefore = recipient.balance;
        executor.executeWithdraw(recipient, amount);
        assertEq(recipient.balance, balBefore + amount);
    }

    function testFuzz_withdraw_unauthorizedCaller(address caller) public {
        vm.assume(caller != address(executor));
        vm.prank(caller);
        vm.expectRevert(OlympiaTreasury.Unauthorized.selector);
        treasury.withdraw(recipient, 1 ether);
    }
}
