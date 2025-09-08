// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SageStaking} from "../src/SageStaking.sol";

contract ChangeCooldownScript is Script {
    // Deployed contract address on Base mainnet
    address constant SAGE_STAKING = 0x413D15aFe510cD1003540E8EF57A29eF9a086Efc;
    
    function setUp() public {}

    function run() public {
        // New cooldown period: 1 minute
        uint256 newCooldownPeriod = 1 minutes;
        
        console.log("Changing cooldown period on SageStaking contract...");
        console.log("Contract Address:", SAGE_STAKING);
        console.log("New Cooldown Period:", newCooldownPeriod, "seconds");
        
        // Start broadcasting - this will use the owner's private key
        vm.startBroadcast();
        
        SageStaking staking = SageStaking(SAGE_STAKING);
        
        // Get current cooldown period for reference
        uint256 currentCooldown = staking.cooldownPeriod();
        console.log("Current Cooldown Period:", currentCooldown, "seconds");
        
        // Change the cooldown period
        staking.adminChangeCooldownPeriod(newCooldownPeriod);
        
        console.log("Cooldown period changed successfully!");
        
        vm.stopBroadcast();
    }
}
