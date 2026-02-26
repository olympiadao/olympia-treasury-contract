// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {OlympiaTreasury} from "../src/OlympiaTreasury.sol";

contract DeployScript is Script {
    // CREATE2 salt for deterministic address across chains
    bytes32 constant SALT = keccak256("OLYMPIA_TREASURY_V1");

    function run() public {
        address deployer = msg.sender;
        console.log("Deployer:", deployer);

        vm.startBroadcast();

        // Deploy via CREATE2 for deterministic address
        OlympiaTreasury treasury = new OlympiaTreasury{salt: SALT}(deployer);

        vm.stopBroadcast();

        console.log("OlympiaTreasury deployed at:", address(treasury));
        console.log("Admin:", deployer);
        console.log("");
        console.log("Next steps:");
        console.log("  1. Update OlympiaTreasuryAddress in core-geth config_mordor.go");
        console.log("  2. Rebuild geth: make geth");
        console.log("  3. Restart node with updated binary");
    }
}
