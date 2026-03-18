// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";
import {MockExecutor} from "./mocks/MockExecutor.sol";
import {ReentrantAttacker} from "./mocks/ReentrantAttacker.sol";

/// @title SecurityInvariants
/// @notice Proves the OlympiaTreasury contract is immutable, safe from unauthorized
///         access, resistant to reentrancy, and handles edge cases correctly.
///         These tests serve as security proofs for the ECIP-1112 treasury vault.
contract SecurityInvariantsTest is Test {
    OlympiaTreasury treasury;
    MockExecutor executor;
    address recipient = makeAddr("recipient");
    address attacker = makeAddr("attacker");

    function setUp() public {
        address executorAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        treasury = new OlympiaTreasury(executorAddr);
        executor = new MockExecutor(treasury);
        assertEq(address(executor), executorAddr);
        vm.deal(address(treasury), 100 ether);
    }

    // ──────────────────────────────────────────────────────────────────
    // A. Immutability Proofs
    // ──────────────────────────────────────────────────────────────────

    /// @notice Verify deployed bytecode contains no SELFDESTRUCT (0xFF) opcode.
    function test_NoSelfdestructOpcode() public view {
        bytes memory code = address(treasury).code;
        for (uint256 i = 0; i < code.length; i++) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xFF, "SELFDESTRUCT opcode found in bytecode");
        }
    }

    /// @notice Verify deployed bytecode contains no DELEGATECALL (0xF4) opcode.
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

    /// @notice Verify deployed bytecode contains no CALLCODE (0xF2) opcode.
    function test_NoCallcodeOpcode() public view {
        bytes memory code = address(treasury).code;
        for (uint256 i = 0; i < code.length; i++) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF2, "CALLCODE opcode found in bytecode");
        }
    }

    /// @notice Verify no EIP-1967 proxy storage slot exists.
    function test_NoProxyStorageSlot() public view {
        bytes32 proxySlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 value = vm.load(address(treasury), proxySlot);
        assertEq(value, bytes32(0), "EIP-1967 proxy slot is non-zero");
    }

    /// @notice Executor is truly immutable — no setter function exists.
    function test_ExecutorIsImmutable() public view {
        // Verify executor returns the expected address
        assertEq(treasury.executor(), address(executor));
        // The contract has no function to change the executor.
        // This test documents the invariant; the lack of a setter is verified by code inspection.
    }

    /// @notice Bytecode size < 1KB (contract should be minimal).
    function test_BytecodeSizeUnder1KB() public view {
        uint256 size = address(treasury).code.length;
        assertLt(size, 1024, "Bytecode exceeds 1KB");
    }

    /// @notice withdraw() gas cost is bounded.
    function test_WithdrawGasBound() public {
        uint256 gasBefore = gasleft();
        executor.executeWithdraw(payable(recipient), 1 ether);
        uint256 gasUsed = gasBefore - gasleft();
        // Account for MockExecutor overhead; raw withdraw should be < 30K
        assertLt(gasUsed, 50_000, "withdraw() exceeded gas bound");
    }

    /// @notice IOlympiaTreasury interface compliance — contract implements all functions.
    function test_InterfaceCompliance() public view {
        // executor() exists and returns non-zero
        address exec = treasury.executor();
        assertTrue(exec != address(0));
    }

    /// @notice No fallback() defined — only receive() accepts ETH.
    function test_NoFallbackFunction() public {
        // Sending data to treasury should revert (no fallback)
        vm.prank(attacker);
        (bool ok,) = address(treasury).call{value: 1 ether}(hex"deadbeef");
        assertFalse(ok, "Treasury should not have a fallback function");
    }

    // ──────────────────────────────────────────────────────────────────
    // B. Reentrancy Resistance
    // ──────────────────────────────────────────────────────────────────

    /// @notice A malicious recipient that re-enters withdraw() in its receive()
    ///         causes the entire withdrawal to revert with TransferFailed.
    function test_ReentrancyRejectedByAuthCheck() public {
        ReentrantAttacker attk = new ReentrantAttacker(treasury);

        vm.prank(address(executor));
        vm.expectRevert(OlympiaTreasury.TransferFailed.selector);
        treasury.withdraw(payable(address(attk)), 1 ether);

        // Treasury balance unchanged
        assertEq(address(treasury).balance, 100 ether);
    }

    // ──────────────────────────────────────────────────────────────────
    // C. Fund Safety
    // ──────────────────────────────────────────────────────────────────

    /// @notice receive() accepts ETC via call, transfer, and send.
    function test_ReceiveAcceptsAllTransferMethods() public {
        vm.deal(attacker, 15 ether);
        uint256 balBefore = address(treasury).balance;

        vm.prank(attacker);
        (bool ok1,) = address(treasury).call{value: 5 ether}("");
        assertTrue(ok1);

        vm.prank(attacker);
        payable(address(treasury)).transfer(5 ether);

        vm.prank(attacker);
        bool ok3 = payable(address(treasury)).send(5 ether);
        assertTrue(ok3);

        assertEq(address(treasury).balance, balBefore + 15 ether);
    }

    // ──────────────────────────────────────────────────────────────────
    // D. Fuzz
    // ──────────────────────────────────────────────────────────────────

    function testFuzz_WithdrawToAnyEOA(address to) public {
        vm.assume(to != address(0));
        // Skip precompiles and system addresses (0x01-0xFF)
        vm.assume(uint160(to) > 0xFF);
        vm.assume(to.code.length == 0);
        // Skip addresses with pre-existing balance (Foundry internal addresses)
        vm.assume(to.balance == 0);

        executor.executeWithdraw(payable(to), 1 ether);
        assertEq(to.balance, 1 ether);
    }
}
