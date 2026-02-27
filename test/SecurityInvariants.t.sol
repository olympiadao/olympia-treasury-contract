// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title SecurityInvariants
/// @notice Proves the OlympiaTreasury contract is immutable, safe from unauthorized
///         access, resistant to reentrancy, and handles edge cases correctly.
///         These tests serve as security proofs for the ECIP-1112 treasury vault.
contract SecurityInvariantsTest is Test {
    OlympiaTreasury treasury;
    address admin = makeAddr("admin");
    address attacker = makeAddr("attacker");
    address recipient = makeAddr("recipient");

    bytes32 constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        treasury = new OlympiaTreasury(admin);
        vm.deal(address(treasury), 100 ether);
    }

    // ──────────────────────────────────────────────────────────────────
    // A. Immutability Proofs
    // ──────────────────────────────────────────────────────────────────

    /// @notice Verify deployed bytecode contains no SELFDESTRUCT (0xFF) opcode.
    ///         This proves the contract cannot be destroyed after deployment.
    function test_NoSelfdestructOpcode() public view {
        bytes memory code = address(treasury).code;
        for (uint256 i = 0; i < code.length; i++) {
            // SELFDESTRUCT = 0xFF. Skip PUSH data by advancing past push operands.
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7F) {
                // PUSH1-PUSH32: skip the next (op - 0x5F) bytes (immediate data)
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xFF, "SELFDESTRUCT opcode found in bytecode");
        }
    }

    /// @notice Verify deployed bytecode contains no DELEGATECALL (0xF4) opcode.
    ///         This proves the contract cannot execute arbitrary external code.
    function test_NoDelegatecallOpcode() public view {
        bytes memory code = address(treasury).code;
        for (uint256 i = 0; i < code.length; i++) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL opcode found in bytecode");
        }
    }

    /// @notice Verify no EIP-1967 proxy storage slot exists.
    ///         Slot 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
    ///         is the standard implementation slot for UUPS/TransparentProxy.
    function test_NoProxyStorageSlot() public view {
        bytes32 proxySlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 value = vm.load(address(treasury), proxySlot);
        assertEq(value, bytes32(0), "EIP-1967 proxy slot is non-zero");
    }

    /// @notice Verify ERC-165 interface support is correct.
    function test_ERC165InterfaceSupport() public view {
        // Must support IAccessControl
        assertTrue(treasury.supportsInterface(type(IAccessControl).interfaceId));
        // Must support IERC165 itself
        assertTrue(treasury.supportsInterface(type(IERC165).interfaceId));
        // Must NOT support random interfaces
        assertFalse(treasury.supportsInterface(0xdeadbeef));
    }

    // ──────────────────────────────────────────────────────────────────
    // B. Access Control Hardening
    // ──────────────────────────────────────────────────────────────────

    /// @notice Non-admin cannot grant WITHDRAWER_ROLE to themselves or others.
    function test_NonAdminCannotGrantRole() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.grantRole(WITHDRAWER_ROLE, attacker);
    }

    /// @notice Non-admin cannot revoke roles from authorized addresses.
    function test_NonAdminCannotRevokeRole() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.revokeRole(WITHDRAWER_ROLE, admin);
    }

    /// @notice Cannot renounce another account's role (OZ enforces caller == account).
    function test_CannotRenounceForAnother() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.renounceRole(WITHDRAWER_ROLE, admin);
    }

    /// @notice WITHDRAWER_ROLE's admin role is DEFAULT_ADMIN_ROLE.
    function test_WithdrawerRoleAdminIsDefaultAdmin() public view {
        assertEq(treasury.getRoleAdmin(WITHDRAWER_ROLE), DEFAULT_ADMIN_ROLE);
    }

    /// @notice After full governance transition, the original deployer has zero authority.
    function test_DeployerHasNoPowerAfterTransition() public {
        address dao = makeAddr("dao");

        vm.startPrank(admin);
        treasury.grantRole(WITHDRAWER_ROLE, dao);
        treasury.grantRole(DEFAULT_ADMIN_ROLE, dao);
        treasury.revokeRole(WITHDRAWER_ROLE, admin);
        treasury.renounceRole(DEFAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        // Admin has zero roles
        assertFalse(treasury.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertFalse(treasury.hasRole(WITHDRAWER_ROLE, admin));

        // Admin cannot withdraw
        vm.prank(admin);
        vm.expectRevert();
        treasury.withdraw(payable(recipient), 1 ether);

        // Admin cannot grant roles
        vm.prank(admin);
        vm.expectRevert();
        treasury.grantRole(WITHDRAWER_ROLE, admin);

        // Admin cannot revoke DAO's roles
        vm.prank(admin);
        vm.expectRevert();
        treasury.revokeRole(WITHDRAWER_ROLE, dao);

        // DAO still works
        vm.prank(dao);
        treasury.withdraw(payable(recipient), 1 ether);
        assertEq(recipient.balance, 1 ether);
    }

    // ──────────────────────────────────────────────────────────────────
    // C. Reentrancy Resistance
    // ──────────────────────────────────────────────────────────────────

    /// @notice A malicious recipient that re-enters withdraw() during the call
    ///         cannot double-spend. The revert chain:
    ///         1. Inner withdraw() reverts with "insufficient balance"
    ///         2. Attacker's receive() reverts (propagates inner revert)
    ///         3. Outer withdraw()'s call{value} fails → "transfer failed"
    ///         4. Entire outer call reverts — no funds moved.
    function test_ReentrancyCannotDoublespend() public {
        ReentrantAttacker attk = new ReentrantAttacker(treasury);

        // Grant attacker contract the WITHDRAWER_ROLE
        vm.prank(admin);
        treasury.grantRole(WITHDRAWER_ROLE, address(attk));

        // Attacker tries to re-enter and drain entire balance
        // First call: 60 ether. Re-entrant call: 60 ether again.
        // Second call fails (insufficient balance), which reverts the receive(),
        // which causes the outer call{value} to fail → "transfer failed"
        vm.expectRevert("OlympiaTreasury: transfer failed");
        attk.attack(60 ether);

        // Treasury balance is unchanged — the entire outer call reverted
        assertEq(address(treasury).balance, 100 ether);
    }

    /// @notice A re-entrant attacker attempting the exact remaining balance
    ///         on each re-entry still cannot exceed total balance.
    function test_ReentrancyExactBalanceAttempt() public {
        ReentrantAttacker attk = new ReentrantAttacker(treasury);

        vm.prank(admin);
        treasury.grantRole(WITHDRAWER_ROLE, address(attk));

        // Try to withdraw 51 ether twice (102 total > 100 balance)
        vm.expectRevert("OlympiaTreasury: transfer failed");
        attk.attack(51 ether);

        assertEq(address(treasury).balance, 100 ether);
    }

    // ──────────────────────────────────────────────────────────────────
    // D. Fund Safety
    // ──────────────────────────────────────────────────────────────────

    /// @notice Withdrawing zero amount succeeds (0 <= balance is always true).
    function test_ZeroAmountWithdrawal() public {
        uint256 balBefore = address(treasury).balance;
        vm.prank(admin);
        treasury.withdraw(payable(recipient), 0);
        assertEq(address(treasury).balance, balBefore);
    }

    /// @notice If all roles are renounced, funds are permanently locked.
    ///         This is by design — the immutability guarantee.
    function test_FundsLockedWhenAllRolesRenounced() public {
        vm.startPrank(admin);
        treasury.revokeRole(WITHDRAWER_ROLE, admin);
        treasury.renounceRole(DEFAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        // No one holds any role
        assertFalse(treasury.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertFalse(treasury.hasRole(WITHDRAWER_ROLE, admin));

        // Cannot withdraw
        vm.prank(admin);
        vm.expectRevert();
        treasury.withdraw(payable(admin), 1 ether);

        // Cannot grant new roles (no admin exists)
        vm.prank(admin);
        vm.expectRevert();
        treasury.grantRole(WITHDRAWER_ROLE, admin);

        // Funds remain in treasury
        assertEq(address(treasury).balance, 100 ether);
    }

    /// @notice receive() accepts ETC via call, transfer, and send.
    function test_ReceiveAcceptsAllTransferMethods() public {
        vm.deal(attacker, 15 ether);
        uint256 balBefore = address(treasury).balance;

        // via call
        vm.prank(attacker);
        (bool ok1,) = address(treasury).call{value: 5 ether}("");
        assertTrue(ok1);

        // via transfer (2300 gas stipend)
        vm.prank(attacker);
        payable(address(treasury)).transfer(5 ether);

        // via send (2300 gas stipend, returns bool)
        vm.prank(attacker);
        bool ok3 = payable(address(treasury)).send(5 ether);
        assertTrue(ok3);

        assertEq(address(treasury).balance, balBefore + 15 ether);
    }

    // ──────────────────────────────────────────────────────────────────
    // E. Fuzz Tests
    // ──────────────────────────────────────────────────────────────────

    /// @notice Fuzz: any amount in [0, balance] can be withdrawn by authorized caller.
    function testFuzz_WithdrawAmount(uint256 amount) public {
        uint256 balance = address(treasury).balance;
        amount = bound(amount, 0, balance);

        vm.prank(admin);
        treasury.withdraw(payable(recipient), amount);

        assertEq(address(treasury).balance, balance - amount);
        assertEq(recipient.balance, amount);
    }

    /// @notice Fuzz: any unauthorized caller is rejected.
    function testFuzz_UnauthorizedCallerReverts(address caller) public {
        vm.assume(caller != admin);
        vm.assume(caller != address(0));

        vm.prank(caller);
        vm.expectRevert();
        treasury.withdraw(payable(recipient), 1 ether);
    }

    /// @notice Fuzz: withdrawal to any EOA address succeeds for authorized caller.
    function testFuzz_WithdrawToAnyAddress(address to) public {
        vm.assume(to != address(0));
        // Skip precompiles (addresses 1-9)
        vm.assume(uint160(to) > 9);
        // Skip addresses with code (contracts, VM cheats, console) — they may reject transfers
        vm.assume(to.code.length == 0);

        vm.prank(admin);
        treasury.withdraw(payable(to), 1 ether);
        assertEq(to.balance, 1 ether);
    }
}

/// @notice Malicious contract that attempts reentrancy on OlympiaTreasury.withdraw().
contract ReentrantAttacker {
    OlympiaTreasury public treasury;
    uint256 public attackAmount;
    bool public attacking;

    constructor(OlympiaTreasury _treasury) {
        treasury = _treasury;
    }

    function attack(uint256 amount) external {
        attackAmount = amount;
        attacking = true;
        treasury.withdraw(payable(address(this)), amount);
    }

    receive() external payable {
        if (attacking) {
            attacking = false;
            // Re-enter: try to withdraw the same amount again
            treasury.withdraw(payable(address(this)), attackAmount);
        }
    }
}
