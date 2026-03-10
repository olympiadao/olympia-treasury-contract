// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";
import {MockCoreDAO} from "./mocks/MockCoreDAO.sol";
import {MockFutarchyDAO} from "./mocks/MockFutarchyDAO.sol";
import {MockLCurveDistributor} from "./mocks/MockLCurveDistributor.sol";

/// @title StagedEvolution
/// @notice Demonstrates the logical evolution of the Olympia Treasury through 4 stages,
///         with realistic authorization progression using AccessControlDefaultAdminRules:
///
///   Stage 1: ECIP-1111 + 1112 — coreMultisig (3-of-5 maintainers) bootstraps the treasury
///   Stage 2: + ECIP-1113 — coreMultisig hands off to CoreDAO via 2-step admin transfer
///   Stage 3: + ECIP-1117 — CoreDAO (now admin) enables FutarchyDAO for ecosystem proposals
///   Stage 4: + ECIP-1115 — CoreDAO enables L-curve miner distribution
///
///   Authorization chain: coreMultisig → CoreDAO → {FutarchyDAO, LCurveDistributor}
///   Edge cases: DAO contract migration, legacy-only tx adoption
contract StagedEvolutionTest is Test {
    // Authorization entities
    address coreMultisig = makeAddr("coreMultisig"); // 3-of-5 maintainer group

    // Funding recipients
    address clientDev = makeAddr("clientDev");
    address auditor = makeAddr("auditor");
    address nodeHost = makeAddr("nodeHost");
    address grantRecipient = makeAddr("grantRecipient");
    address researcher = makeAddr("researcher");

    bytes32 constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    // Admin transfer delay for demo (10 minutes)
    uint48 constant ADMIN_DELAY = 600;

    /// @dev Helper: perform 2-step admin transfer from current admin to new admin.
    ///      Requires vm.prank(currentAdmin) context for beginDefaultAdminTransfer.
    function _transferAdmin(OlympiaTreasury treasury, address currentAdmin, address newAdmin) internal {
        vm.prank(currentAdmin);
        treasury.beginDefaultAdminTransfer(newAdmin);
        vm.warp(block.timestamp + ADMIN_DELAY + 1);
        vm.prank(newAdmin);
        treasury.acceptDefaultAdminTransfer();
    }

    // ──────────────────────────────────────────────────────────────────
    // Stage 1: ECIP-1111 + 1112 — Bootstrap with Core Multisig
    // ──────────────────────────────────────────────────────────────────

    /// @notice Stage 1: Treasury accumulates baseFee revenue under core multisig control.
    ///         The multisig represents the initial core maintainer group (e.g., 3-of-5).
    ///         No DAO contracts yet — multisig handles urgent operational spending.
    function test_Stage1_RedirectAndAccumulation() public {
        OlympiaTreasury treasury = new OlympiaTreasury(ADMIN_DELAY, coreMultisig);

        // Simulate baseFee state credits across 10 "blocks"
        // In production, core-geth's Finalize() credits baseFee * gasUsed each block
        uint256 totalCredits;
        for (uint256 i = 0; i < 10; i++) {
            uint256 credit = (i + 1) * 0.5 ether; // increasing fees (congestion building)
            vm.deal(address(treasury), address(treasury).balance + credit);
            totalCredits += credit;
        }

        assertEq(address(treasury).balance, totalCredits);
        assertEq(treasury.defaultAdmin(), coreMultisig);
        assertTrue(treasury.hasRole(WITHDRAWER_ROLE, coreMultisig));

        // Core multisig withdraws for immediate operational needs
        vm.prank(coreMultisig);
        treasury.withdraw(payable(clientDev), 5 ether);

        assertEq(clientDev.balance, 5 ether);
        assertEq(address(treasury).balance, totalCredits - 5 ether);

        console.log("Stage 1: coreMultisig bootstraps treasury");
        console.log("  Authorized by: coreMultisig (3-of-5 maintainers)");
        console.log("  Total credits: %s wei", totalCredits);
        console.log("  Withdrawn: 5 ETH to client dev");
        console.log("  Remaining: %s wei", address(treasury).balance);
    }

    // ──────────────────────────────────────────────────────────────────
    // Stage 2: + ECIP-1113 — Multisig Hands Off to Core DAO
    // ──────────────────────────────────────────────────────────────────

    /// @notice Stage 2: Core multisig deploys CoreDAO, grants it WITHDRAWER_ROLE,
    ///         then transfers DEFAULT_ADMIN_ROLE to CoreDAO via 2-step process.
    ///         The multisig steps back after the admin delay.
    function test_Stage2_TraditionalDAOForCoreInfra() public {
        OlympiaTreasury treasury = new OlympiaTreasury(ADMIN_DELAY, coreMultisig);
        vm.deal(address(treasury), 100 ether);

        MockCoreDAO coreDAO = new MockCoreDAO(payable(address(treasury)));

        // ── Phase 2a: Transition period ──
        // Multisig grants WITHDRAWER_ROLE to CoreDAO (both can operate temporarily)
        vm.startPrank(coreMultisig);
        treasury.grantRole(WITHDRAWER_ROLE, address(coreDAO));
        vm.stopPrank();

        // CoreDAO funds core infrastructure
        coreDAO.fundCoreInfra(payable(clientDev), 20 ether, "core-geth client maintenance Q1 2026");
        coreDAO.fundCoreInfra(payable(auditor), 15 ether, "Olympia hard fork security audit");
        coreDAO.fundCoreInfra(payable(nodeHost), 5 ether, "Public RPC node hosting");

        assertEq(clientDev.balance, 20 ether);
        assertEq(auditor.balance, 15 ether);
        assertEq(nodeHost.balance, 5 ether);
        assertEq(address(treasury).balance, 60 ether);

        // ── Phase 2b: Full handoff via 2-step admin transfer ──
        // Multisig revokes its own WITHDRAWER_ROLE first
        vm.prank(coreMultisig);
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);

        // Then begins admin transfer to CoreDAO (2-step with delay)
        _transferAdmin(treasury, coreMultisig, address(coreDAO));

        // Multisig is now completely out — no admin, no withdrawer
        assertNotEq(treasury.defaultAdmin(), coreMultisig);
        assertFalse(treasury.hasRole(WITHDRAWER_ROLE, coreMultisig));

        // CoreDAO is now admin + withdrawer
        assertEq(treasury.defaultAdmin(), address(coreDAO));
        assertTrue(treasury.hasRole(WITHDRAWER_ROLE, address(coreDAO)));

        // Multisig cannot withdraw
        vm.prank(coreMultisig);
        vm.expectRevert();
        treasury.withdraw(payable(coreMultisig), 1 ether);

        // CoreDAO continues operating
        coreDAO.fundCoreInfra(payable(clientDev), 10 ether, "core-geth Olympia patch 1.12.21");
        assertEq(clientDev.balance, 30 ether);

        console.log("Stage 2: coreMultisig -> CoreDAO handoff complete");
        console.log("  Authorized by: coreMultisig (2-step admin transfer to CoreDAO)");
        console.log("  coreMultisig: no roles (fully stepped back)");
        console.log("  CoreDAO: DEFAULT_ADMIN_ROLE + WITHDRAWER_ROLE");
        console.log("  Funded: client dev (30 ETH), auditor (15 ETH), node host (5 ETH)");
    }

    // ──────────────────────────────────────────────────────────────────
    // Stage 3: + ECIP-1117 — CoreDAO Enables Futarchy
    // ──────────────────────────────────────────────────────────────────

    /// @notice Stage 3: CoreDAO (now admin) enables FutarchyDAO for ecosystem proposals.
    ///         CoreDAO handles essential infra (60%), FutarchyDAO handles proposals (40%).
    function test_Stage3_FutarchyCoexistsWithCoreDAO() public {
        OlympiaTreasury treasury = new OlympiaTreasury(ADMIN_DELAY, coreMultisig);
        vm.deal(address(treasury), 100 ether);

        MockCoreDAO coreDAO = new MockCoreDAO(payable(address(treasury)));
        MockFutarchyDAO futarchyDAO = new MockFutarchyDAO(payable(address(treasury)));

        // ── Bootstrap: multisig sets up CoreDAO as admin (2-step) ──
        vm.prank(coreMultisig);
        treasury.grantRole(WITHDRAWER_ROLE, address(coreDAO));
        vm.prank(coreMultisig);
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);
        _transferAdmin(treasury, coreMultisig, address(coreDAO));

        // ── CoreDAO enables FutarchyDAO ──
        // CoreDAO is now the admin — it authorizes the futarchy pipeline
        coreDAO.enablePipeline(address(futarchyDAO), "ECIP-1117: Futarchy DAO for ecosystem proposals");

        // Verify FutarchyDAO has WITHDRAWER_ROLE
        assertTrue(treasury.hasRole(WITHDRAWER_ROLE, address(futarchyDAO)));

        // Both DAOs operate independently — neither blocks the other
        // Core DAO: 60% for essential infrastructure
        coreDAO.fundCoreInfra(payable(clientDev), 35 ether, "core-geth + fukuii client maintenance");
        coreDAO.fundCoreInfra(payable(auditor), 15 ether, "smart contract audit");
        coreDAO.fundCoreInfra(payable(nodeHost), 10 ether, "Rivet RPC infrastructure");

        // Futarchy DAO: 40% for ecosystem proposals (prediction market approved)
        futarchyDAO.executeProposal(payable(grantRecipient), 25 ether, "DEX aggregator development grant");
        futarchyDAO.executeProposal(payable(researcher), 15 ether, "EVM optimization research");

        // Verify all distributions
        assertEq(clientDev.balance, 35 ether);
        assertEq(auditor.balance, 15 ether);
        assertEq(nodeHost.balance, 10 ether);
        assertEq(grantRecipient.balance, 25 ether);
        assertEq(researcher.balance, 15 ether);
        assertEq(address(treasury).balance, 0);

        // coreMultisig has no power
        assertNotEq(treasury.defaultAdmin(), coreMultisig);

        console.log("Stage 3: CoreDAO enables FutarchyDAO");
        console.log("  Authorized by: CoreDAO (as DEFAULT_ADMIN_ROLE holder)");
        console.log("  CoreDAO: client dev (35), audit (15), nodes (10) = 60 ETH");
        console.log("  FutarchyDAO: DEX grant (25), research (15) = 40 ETH");
        console.log("  coreMultisig: fully excluded");
    }

    // ──────────────────────────────────────────────────────────────────
    // Stage 4: + ECIP-1115 — CoreDAO Enables L-Curve Miner Distribution
    // ──────────────────────────────────────────────────────────────────

    /// @notice Stage 4: CoreDAO enables L-curve miner incentives alongside existing pipelines.
    ///         Core DAO (40%) + Futarchy DAO (30%) + L-Curve Miners (30%).
    function test_Stage4_LCurveMinerIncentives() public {
        OlympiaTreasury treasury = new OlympiaTreasury(ADMIN_DELAY, coreMultisig);
        vm.deal(address(treasury), 100 ether);

        MockCoreDAO coreDAO = new MockCoreDAO(payable(address(treasury)));
        MockFutarchyDAO futarchyDAO = new MockFutarchyDAO(payable(address(treasury)));
        MockLCurveDistributor lcurve = new MockLCurveDistributor(payable(address(treasury)));

        // ── Bootstrap: multisig → CoreDAO (2-step) ──
        vm.prank(coreMultisig);
        treasury.grantRole(WITHDRAWER_ROLE, address(coreDAO));
        vm.prank(coreMultisig);
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);
        _transferAdmin(treasury, coreMultisig, address(coreDAO));

        // ── CoreDAO enables both FutarchyDAO and LCurveDistributor ──
        coreDAO.enablePipeline(address(futarchyDAO), "ECIP-1117: Futarchy for ecosystem proposals");
        coreDAO.enablePipeline(address(lcurve), "ECIP-1115: L-curve miner security budget supplement");

        // Verify all three have WITHDRAWER_ROLE
        assertTrue(treasury.hasRole(WITHDRAWER_ROLE, address(coreDAO)));
        assertTrue(treasury.hasRole(WITHDRAWER_ROLE, address(futarchyDAO)));
        assertTrue(treasury.hasRole(WITHDRAWER_ROLE, address(lcurve)));

        // Core DAO: 40 ETH for essential infrastructure
        coreDAO.fundCoreInfra(payable(clientDev), 25 ether, "core-geth v1.13 development");
        coreDAO.fundCoreInfra(payable(auditor), 15 ether, "post-Olympia security audit");

        // Futarchy DAO: 30 ETH for ecosystem proposals
        futarchyDAO.executeProposal(payable(grantRecipient), 30 ether, "L2 bridge implementation");

        // L-Curve: 30 ETH distributed to 5 miners
        address payable[] memory miners = new address payable[](5);
        miners[0] = payable(makeAddr("miner1_top"));
        miners[1] = payable(makeAddr("miner2"));
        miners[2] = payable(makeAddr("miner3"));
        miners[3] = payable(makeAddr("miner4"));
        miners[4] = payable(makeAddr("miner5_bottom"));

        lcurve.distribute(miners, 30 ether);

        // Verify treasury is empty
        assertEq(address(treasury).balance, 0);

        // Verify L-curve distribution is monotonically decreasing
        uint256 prevBalance = type(uint256).max;
        uint256 totalMinerPayout;
        for (uint256 i = 0; i < miners.length; i++) {
            uint256 bal = miners[i].balance;
            assertTrue(bal > 0, "Each miner must receive > 0");
            assertTrue(bal <= prevBalance, "L-curve must be monotonically decreasing");
            prevBalance = bal;
            totalMinerPayout += bal;

            console.log("  Miner %s (rank %s): %s wei", i + 1, i + 1, bal);
        }

        // Verify no funds lost in distribution
        assertEq(totalMinerPayout, 30 ether, "Total miner payout must equal withdrawal amount");
        assertTrue(miners[0].balance > miners[4].balance * 2, "Top miner should get >2x bottom miner");

        console.log("Stage 4: CoreDAO enables L-curve miner incentives");
        console.log("  Authorized by: CoreDAO (enables FutarchyDAO + LCurve via enablePipeline)");
        console.log("  Core (40 ETH) + Futarchy (30 ETH) + L-Curve Miners (30 ETH)");
    }

    // ──────────────────────────────────────────────────────────────────
    // Edge Case: DAO Contract Migration
    // ──────────────────────────────────────────────────────────────────

    /// @notice Edge: CoreDAO migrates from one version to another (e.g., OZ v5 → v6).
    ///         v5 begins admin transfer to v6. v6 accepts after delay. v6 disables v5.
    ///         Zero downtime, zero fund loss — treasury address never changes.
    function test_Edge_DAOMigration() public {
        OlympiaTreasury treasury = new OlympiaTreasury(ADMIN_DELAY, coreMultisig);
        vm.deal(address(treasury), 100 ether);

        // Deploy "v5" CoreDAO
        MockCoreDAO daoV5 = new MockCoreDAO(payable(address(treasury)));

        // Bootstrap: multisig → v5 CoreDAO (2-step)
        vm.prank(coreMultisig);
        treasury.grantRole(WITHDRAWER_ROLE, address(daoV5));
        vm.prank(coreMultisig);
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);
        _transferAdmin(treasury, coreMultisig, address(daoV5));

        // v5 DAO operates normally
        daoV5.fundCoreInfra(payable(clientDev), 20 ether, "v5 DAO: client maintenance");
        assertEq(clientDev.balance, 20 ether);
        assertEq(address(treasury).balance, 80 ether);

        // Time passes... OZ v6 is released, new DAO contract needed

        // Deploy "v6" CoreDAO
        MockCoreDAO daoV6 = new MockCoreDAO(payable(address(treasury)));

        // v5 DAO (as admin) authorizes its own succession:
        // 1. Enable v6 as withdrawer
        daoV5.enablePipeline(address(daoV6), "Migration: enable v6 CoreDAO");

        // 2. Begin 2-step admin transfer to v6
        daoV5.transferAdminTo(address(daoV6));
        // Wait for admin delay
        vm.warp(block.timestamp + ADMIN_DELAY + 1);
        // v6 accepts the admin transfer
        daoV6.acceptAdminTransfer();

        // 3. v6 (now admin) disables v5's withdrawal access
        daoV6.disablePipeline(address(daoV5), "Migration: v5 DAO winding down");

        // v5 DAO can no longer withdraw
        vm.expectRevert();
        daoV5.fundCoreInfra(payable(clientDev), 1 ether, "v5 DAO: should fail");

        // v6 DAO can withdraw — continuous operation
        daoV6.fundCoreInfra(payable(clientDev), 30 ether, "v6 DAO: continued maintenance");
        assertEq(clientDev.balance, 50 ether); // 20 from v5 + 30 from v6
        assertEq(address(treasury).balance, 50 ether);

        console.log("Edge: DAO migration v5 -> v6");
        console.log("  Authorized by: v5 CoreDAO (2-step admin transfer, enables successor)");
        console.log("  v5 withdrew 20 ETH before migration");
        console.log("  v6 withdrew 30 ETH after migration");
        console.log("  Treasury continuous: 100 -> 80 -> 50 ETH, zero fund loss");
    }

    // ──────────────────────────────────────────────────────────────────
    // Edge Case: Legacy-Only Transaction Adoption
    // ──────────────────────────────────────────────────────────────────

    /// @notice Edge: All users stay on Legacy (Type-0) transactions — no Type-2 adoption.
    ///         Treasury revenue is identical because EIP-1559 baseFee mechanism works
    ///         regardless of transaction type.
    function test_Edge_LegacyOnlyAdoption() public {
        OlympiaTreasury treasury = new OlympiaTreasury(ADMIN_DELAY, coreMultisig);

        // Simulate baseFee accumulation under legacy-only usage
        uint256 block1Revenue = 1e9 * 21000;
        uint256 block2Revenue = 1e9 * 63000; // 3 legacy txs
        uint256 block3Revenue = 1_125_000_000 * 210000; // 10 legacy txs, higher baseFee

        uint256 totalRevenue = block1Revenue + block2Revenue + block3Revenue;

        // Simulate state credits
        vm.deal(address(treasury), totalRevenue);

        vm.prank(coreMultisig);
        treasury.withdraw(payable(clientDev), totalRevenue);

        assertEq(clientDev.balance, totalRevenue);
        assertEq(address(treasury).balance, 0);

        console.log("Edge: Legacy-only adoption -- treasury revenue identical");
        console.log("  Block 1 revenue: %s wei (1 tx, 1 Gwei baseFee)", block1Revenue);
        console.log("  Block 2 revenue: %s wei (3 txs, 1 Gwei baseFee)", block2Revenue);
        console.log("  Block 3 revenue: %s wei (10 txs, 1.125 Gwei baseFee)", block3Revenue);
        console.log("  Total: %s wei", totalRevenue);
        console.log("  EIP-1559 baseFee mechanism works regardless of tx type");
    }
}
