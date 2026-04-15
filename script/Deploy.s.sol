// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";

contract DeployScript is Script {
    // Pre-computed OlympiaExecutor CREATE2 address (OZ 5.1 bytecode, salt OLYMPIA_DEMO_V0_4).
    // Fill in after running PrecomputeAddresses.s.sol (demo_v0.4) in the governance repo:
    //   forge script script/PrecomputeAddresses.s.sol \
    //     --rpc-url $MORDOR_RPC_URL \
    //     DEPLOYER=<deployer_address> DEPLOYER_NONCE=<nonce>
    // The executor contract does not exist yet — governance deploys it later
    // at this exact CREATE2 address.
    // demo_v0.4 address: pending (run PrecomputeAddresses.s.sol to compute)
    address constant EXECUTOR = address(0); // TODO: fill in before deploying

    function run() public {
        require(EXECUTOR != address(0), "Set EXECUTOR address before deploying");

        address deployer = msg.sender;
        uint64 nonce = vm.getNonce(deployer);

        // CRITICAL: Treasury address = keccak256(rlp(deployer, nonce)).
        // PrecomputeAddresses.s.sol was run with DEPLOYER_NONCE=0.
        // If nonce != 0, the treasury will land at a different address than
        // what is baked into the executor's immutable constructor arg — the
        // deployment will be broken and irrecoverable without redeploying all 9 contracts.
        // Use a FRESH address that has never sent a transaction on this chain.
        require(nonce == 0, "Deployer must be a fresh address (nonce=0). Treasury CREATE address must match precomputation.");

        console.log("Deployer:", deployer);
        console.log("Nonce:", nonce, "(confirmed 0 -- treasury address is deterministic)");
        console.log("Executor (pre-computed):", EXECUTOR);

        // Treasury uses CREATE (nonce-based), not CREATE2.
        // This breaks the circular dependency with Executor:
        // - Treasury address = f(deployer, nonce=0) — no dependency on constructor args
        // - Executor uses CREATE2 with Treasury address as constructor arg
        // Both addresses are pre-computed by PrecomputeAddresses.s.sol.
        vm.startBroadcast();

        OlympiaTreasury treasury = new OlympiaTreasury(EXECUTOR);

        vm.stopBroadcast();

        console.log("OlympiaTreasury (demo v0.4) deployed at:", address(treasury));
        console.log("");
        console.log("Verify:");
        console.log("  treasury.executor() == EXECUTOR");
        console.log("  Executor has NO code yet (governance not deployed)");
    }
}
