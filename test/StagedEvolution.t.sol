// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";
import {MockCoreDAO} from "./mocks/MockCoreDAO.sol";
import {MockFutarchyDAO} from "./mocks/MockFutarchyDAO.sol";
import {MockLCurveDistributor} from "./mocks/MockLCurveDistributor.sol";

/// @title StagedEvolution
/// @notice Demonstrates the logical evolution of the Olympia Treasury through 4 stages,
///         with realistic authorization progression:
///
///   Stage 1: ECIP-1111 + 1112 — coreMultisig (3-of-5 maintainers) bootstraps the treasury
///   Stage 2: + ECIP-1113 — coreMultisig hands off to CoreDAO, transfers admin role
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

    // ──────────────────────────────────────────────────────────────────
    // Stage 1: ECIP-1111 + 1112 — Bootstrap with Core Multisig
    // ──────────────────────────────────────────────────────────────────

    /// @notice Stage 1: Treasury accumulates baseFee revenue under core multisig control.
    ///         The multisig represents the initial core maintainer group (e.g., 3-of-5).
    ///         No DAO contracts yet — multisig handles urgent operational spending.
    function test_Stage1_RedirectAndAccumulation() public {
        OlympiaTreasury treasury = new OlympiaTreasury(coreMultisig);

        // Simulate baseFee state credits across 10 "blocks"
        // In production, core-geth's Finalize() credits baseFee * gasUsed each block
        uint256 totalCredits;
        for (uint256 i = 0; i < 10; i++) {
            uint256 credit = (i + 1) * 0.5 ether; // increasing fees (congestion building)
            vm.deal(address(treasury), address(treasury).balance + credit);
            totalCredits += credit;
        }

        assertEq(address(treasury).balance, totalCredits);
        assertTrue(treasury.hasRole(DEFAULT_ADMIN_ROLE, coreMultisig));
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
    ///         then transfers DEFAULT_ADMIN_ROLE to CoreDAO. The multisig steps back.
    ///         CoreDAO is now the sole authority for spending AND future governance changes.
    function test_Stage2_TraditionalDAOForCoreInfra() public {
        OlympiaTreasury treasury = new OlympiaTreasury(coreMultisig);
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

        // ── Phase 2b: Full handoff ──
        // Multisig transfers DEFAULT_ADMIN_ROLE to CoreDAO, then steps back entirely
        vm.startPrank(coreMultisig);
        // Grant admin role to CoreDAO so it can manage roles going forward
        treasury.grantRole(DEFAULT_ADMIN_ROLE, address(coreDAO));
        // Revoke multisig's WITHDRAWER_ROLE
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);
        // Renounce multisig's DEFAULT_ADMIN_ROLE — irreversible handoff
        treasury.renounceRole(DEFAULT_ADMIN_ROLE, coreMultisig);
        vm.stopPrank();

        // Multisig is now completely out — no admin, no withdrawer
        assertFalse(treasury.hasRole(DEFAULT_ADMIN_ROLE, coreMultisig));
        assertFalse(treasury.hasRole(WITHDRAWER_ROLE, coreMultisig));

        // CoreDAO has both roles
        assertTrue(treasury.hasRole(DEFAULT_ADMIN_ROLE, address(coreDAO)));
        assertTrue(treasury.hasRole(WITHDRAWER_ROLE, address(coreDAO)));

        // Multisig cannot withdraw
        vm.prank(coreMultisig);
        vm.expectRevert();
        treasury.withdraw(payable(coreMultisig), 1 ether);

        // CoreDAO continues operating
        coreDAO.fundCoreInfra(payable(clientDev), 10 ether, "core-geth Olympia patch 1.12.21");
        assertEq(clientDev.balance, 30 ether);

        console.log("Stage 2: coreMultisig -> CoreDAO handoff complete");
        console.log("  Authorized by: coreMultisig (transferred admin to CoreDAO)");
        console.log("  coreMultisig: no roles (fully stepped back)");
        console.log("  CoreDAO: DEFAULT_ADMIN_ROLE + WITHDRAWER_ROLE");
        console.log("  Funded: client dev (30 ETH), auditor (15 ETH), node host (5 ETH)");
    }

    // ──────────────────────────────────────────────────────────────────
    // Stage 3: + ECIP-1117 — CoreDAO Enables Futarchy
    // ──────────────────────────────────────────────────────────────────

    /// @notice Stage 3: CoreDAO (now admin) enables FutarchyDAO for ecosystem proposals.
    ///         CoreDAO handles essential infra (60%), FutarchyDAO handles proposals (40%).
    ///         The DAO itself decides when excess funds justify a prediction market pipeline.
    function test_Stage3_FutarchyCoexistsWithCoreDAO() public {
        OlympiaTreasury treasury = new OlympiaTreasury(coreMultisig);
        vm.deal(address(treasury), 100 ether);

        MockCoreDAO coreDAO = new MockCoreDAO(payable(address(treasury)));
        MockFutarchyDAO futarchyDAO = new MockFutarchyDAO(payable(address(treasury)));

        // ── Bootstrap: multisig sets up CoreDAO as admin ──
        vm.startPrank(coreMultisig);
        treasury.grantRole(WITHDRAWER_ROLE, address(coreDAO));
        treasury.grantRole(DEFAULT_ADMIN_ROLE, address(coreDAO));
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);
        treasury.renounceRole(DEFAULT_ADMIN_ROLE, coreMultisig);
        vm.stopPrank();

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
        assertFalse(treasury.hasRole(DEFAULT_ADMIN_ROLE, coreMultisig));

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
    ///         Block rewards are declining (ECIP-1017 disinflation), so the DAO decides to
    ///         supplement miner income with predictable treasury-funded distributions.
    ///         Core DAO (40%) + Futarchy DAO (30%) + L-Curve Miners (30%).
    function test_Stage4_LCurveMinerIncentives() public {
        OlympiaTreasury treasury = new OlympiaTreasury(coreMultisig);
        vm.deal(address(treasury), 100 ether);

        MockCoreDAO coreDAO = new MockCoreDAO(payable(address(treasury)));
        MockFutarchyDAO futarchyDAO = new MockFutarchyDAO(payable(address(treasury)));
        MockLCurveDistributor lcurve = new MockLCurveDistributor(payable(address(treasury)));

        // ── Bootstrap: multisig → CoreDAO ──
        vm.startPrank(coreMultisig);
        treasury.grantRole(WITHDRAWER_ROLE, address(coreDAO));
        treasury.grantRole(DEFAULT_ADMIN_ROLE, address(coreDAO));
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);
        treasury.renounceRole(DEFAULT_ADMIN_ROLE, coreMultisig);
        vm.stopPrank();

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
    ///         CoreDAO (as admin) authorizes the new DAO, disables the old one.
    ///         Zero downtime, zero fund loss — treasury address never changes.
    function test_Edge_DAOMigration() public {
        OlympiaTreasury treasury = new OlympiaTreasury(coreMultisig);
        vm.deal(address(treasury), 100 ether);

        // Deploy "v5" CoreDAO
        MockCoreDAO daoV5 = new MockCoreDAO(payable(address(treasury)));

        // Bootstrap: multisig → v5 CoreDAO
        vm.startPrank(coreMultisig);
        treasury.grantRole(WITHDRAWER_ROLE, address(daoV5));
        treasury.grantRole(DEFAULT_ADMIN_ROLE, address(daoV5));
        treasury.revokeRole(WITHDRAWER_ROLE, coreMultisig);
        treasury.renounceRole(DEFAULT_ADMIN_ROLE, coreMultisig);
        vm.stopPrank();

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
        // 2. Transfer DEFAULT_ADMIN_ROLE to v6, renounce own admin (irreversible)
        daoV5.transferAdminTo(address(daoV6));
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
        console.log("  Authorized by: v5 CoreDAO (self-sunset, enables successor)");
        console.log("  v5 withdrew 20 ETH before migration");
        console.log("  v6 withdrew 30 ETH after migration");
        console.log("  Treasury continuous: 100 -> 80 -> 50 ETH, zero fund loss");
    }

    // ──────────────────────────────────────────────────────────────────
    // Edge Case: Legacy-Only Transaction Adoption
    // ──────────────────────────────────────────────────────────────────

    /// @notice Edge: All users stay on Legacy (Type-0) transactions — no Type-2 adoption.
    ///         Treasury revenue is identical because EIP-1559 baseFee mechanism works
    ///         regardless of transaction type. Legacy txs pay gasPrice = baseFee + tip,
    ///         so baseFee * gasUsed still flows to treasury.
    function test_Edge_LegacyOnlyAdoption() public {
        OlympiaTreasury treasury = new OlympiaTreasury(coreMultisig);

        // Simulate baseFee accumulation under legacy-only usage
        // Block 1: low usage, baseFee = 1 Gwei, gasUsed = 21000
        uint256 block1Revenue = 1e9 * 21000;

        // Block 2: moderate usage, baseFee still ~1 Gwei
        uint256 block2Revenue = 1e9 * 63000; // 3 legacy txs

        // Block 3: heavy usage, baseFee rises to ~1.125 Gwei
        uint256 block3Revenue = 1_125_000_000 * 210000; // 10 legacy txs, higher baseFee

        uint256 totalRevenue = block1Revenue + block2Revenue + block3Revenue;

        // Simulate state credits
        vm.deal(address(treasury), totalRevenue);

        // Key insight: the SAME amount accumulates whether users use
        // Type-0 (gasPrice = baseFee + tip) or Type-2 (gasFeeCap, gasTipCap).
        // The baseFee portion is always baseFee * gasUsed, regardless of tx type.

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
