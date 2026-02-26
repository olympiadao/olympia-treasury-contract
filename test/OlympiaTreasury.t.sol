// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";

contract OlympiaTreasuryTest is Test {
    OlympiaTreasury treasury;
    address admin = makeAddr("admin");
    address withdrawer = makeAddr("withdrawer");
    address recipient = makeAddr("recipient");
    address nobody = makeAddr("nobody");

    function setUp() public {
        treasury = new OlympiaTreasury(admin);
        // Fund the treasury (simulates basefee state credits)
        vm.deal(address(treasury), 100 ether);
    }

    function test_AdminHasRoles() public view {
        assertTrue(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(treasury.hasRole(treasury.WITHDRAWER_ROLE(), admin));
    }

    function test_AdminCanWithdraw() public {
        vm.prank(admin);
        treasury.withdraw(payable(recipient), 10 ether);
        assertEq(recipient.balance, 10 ether);
        assertEq(address(treasury).balance, 90 ether);
    }

    function test_GrantWithdrawerRole() public {
        bytes32 role = treasury.WITHDRAWER_ROLE();
        vm.prank(admin);
        treasury.grantRole(role, withdrawer);

        vm.prank(withdrawer);
        treasury.withdraw(payable(recipient), 5 ether);
        assertEq(recipient.balance, 5 ether);
    }

    function test_RevokeAdminWithdrawer() public {
        // Grant DAO, revoke admin's withdrawal rights
        vm.startPrank(admin);
        treasury.grantRole(treasury.WITHDRAWER_ROLE(), withdrawer);
        treasury.revokeRole(treasury.WITHDRAWER_ROLE(), admin);
        vm.stopPrank();

        // Admin can no longer withdraw
        vm.prank(admin);
        vm.expectRevert();
        treasury.withdraw(payable(recipient), 1 ether);

        // But withdrawer can
        vm.prank(withdrawer);
        treasury.withdraw(payable(recipient), 1 ether);
        assertEq(recipient.balance, 1 ether);
    }

    function test_UnauthorizedCannotWithdraw() public {
        vm.prank(nobody);
        vm.expectRevert();
        treasury.withdraw(payable(recipient), 1 ether);
    }

    function test_CannotWithdrawMoreThanBalance() public {
        vm.prank(admin);
        vm.expectRevert("OlympiaTreasury: insufficient balance");
        treasury.withdraw(payable(recipient), 200 ether);
    }

    function test_CannotWithdrawToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("OlympiaTreasury: zero address");
        treasury.withdraw(payable(address(0)), 1 ether);
    }

    function test_ReceiveETH() public {
        vm.deal(nobody, 5 ether);
        vm.prank(nobody);
        (bool success,) = address(treasury).call{value: 5 ether}("");
        assertTrue(success);
        assertEq(address(treasury).balance, 105 ether);
    }

    function test_WithdrawalEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit OlympiaTreasury.Withdrawal(recipient, 3 ether);
        treasury.withdraw(payable(recipient), 3 ether);
    }

    function test_WithdrawEntireBalance() public {
        vm.prank(admin);
        treasury.withdraw(payable(recipient), 100 ether);
        assertEq(address(treasury).balance, 0);
        assertEq(recipient.balance, 100 ether);
    }
}
