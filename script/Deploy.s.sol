// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";

contract DeployScript is Script {
    // CREATE2 salt for deterministic address across chains (demo v0.1)
    bytes32 constant SALT = keccak256("OLYMPIA_DEMO_V0_1");

    // Admin transfer delay: 10 minutes for demo
    uint48 constant ADMIN_DELAY = 600;

    function run() public {
        address deployer = msg.sender;
        console.log("Deployer:", deployer);
        console.log("Salt: OLYMPIA_DEMO_V0_1");
        console.log("Admin delay: %s seconds", uint256(ADMIN_DELAY));

        vm.startBroadcast();

        // Deploy via CREATE2 for deterministic address
        OlympiaTreasury treasury = new OlympiaTreasury{salt: SALT}(ADMIN_DELAY, deployer);

        vm.stopBroadcast();

        console.log("OlympiaTreasury (demo v0.1) deployed at:", address(treasury));
        console.log("Admin:", deployer);
        console.log("");
        console.log("Next steps:");
        console.log("  1. Update OlympiaTreasuryAddress in all 3 client olympia branches");
        console.log("  2. core-geth: params/config_mordor.go + params/config_etc.go");
        console.log("  3. besu: config/src/main/resources/mordor.json + etc.json");
        console.log("  4. fukuii: mordor-chain.conf + etc-chain.conf");
    }
}
