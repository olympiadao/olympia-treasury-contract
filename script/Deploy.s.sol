// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";

contract DeployScript is Script {
    // CREATE2 salt for deterministic address (demo v0.2)
    bytes32 constant SALT = keccak256("OLYMPIA_DEMO_V0_2");

    // Pre-computed OlympiaExecutor CREATE2 address (OZ 5.1 bytecode).
    // Set after running PrecomputeAddresses.s.sol. The executor contract
    // does not exist yet — governance deploys it later at this exact address.
    address constant EXECUTOR = address(0); // TODO: set after PrecomputeAddresses

    function run() public {
        require(EXECUTOR != address(0), "Set EXECUTOR address before deploying");

        address deployer = msg.sender;
        console.log("Deployer:", deployer);
        console.log("Salt: OLYMPIA_DEMO_V0_2");
        console.log("Executor (pre-computed):", EXECUTOR);

        vm.startBroadcast();

        OlympiaTreasury treasury = new OlympiaTreasury{salt: SALT}(EXECUTOR);

        vm.stopBroadcast();

        console.log("OlympiaTreasury (demo v0.2) deployed at:", address(treasury));
        console.log("");
        console.log("Verify:");
        console.log("  treasury.executor() == EXECUTOR");
        console.log("  Executor has NO code yet (governance not deployed)");
    }
}
