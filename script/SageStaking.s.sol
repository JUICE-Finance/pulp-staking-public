// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SageStaking} from "../src/SageStaking.sol";

contract SageStakingScript is Script {
    function setUp() public {}

    function run() public returns (SageStaking) {
        // Read configuration from environment variables
        address tokenAddress = vm.envAddress("SAGE_TOKEN_ADDRESS");
        uint256 cooldownDays = vm.envUint("COOLDOWN_PERIOD_DAYS");
        uint256 cooldownPeriod = cooldownDays * 1 days;
        
        console.log("Deploying SageStaking contract...");
        console.log("Token Address:", tokenAddress);
        console.log("Cooldown Period (days):", cooldownDays);
        
        // Start broadcasting - this will use the private key from --private-key flag or --interactives
        vm.startBroadcast();
        
        SageStaking staking = new SageStaking(cooldownPeriod, tokenAddress);
        
        console.log("SageStaking deployed at:", address(staking));
        
        vm.stopBroadcast();
        
        return staking;
    }
}
