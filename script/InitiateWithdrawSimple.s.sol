// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SageStaking, StakingPositionStatus} from "../src/SageStaking.sol";

contract InitiateWithdrawSimpleScript is Script {
    // Deployed contract address on Base mainnet
    address constant SAGE_STAKING = 0x413D15aFe510cD1003540E8EF57A29eF9a086Efc;
    
    function setUp() public {}

    function run() public {
        // Get nonce from environment variable, default to 0 if not set
        uint256 nonce;
        try vm.envUint("WITHDRAW_NONCE") returns (uint256 _nonce) {
            nonce = _nonce;
        } catch {
            nonce = 0; // Default to first deposit
        }
        
        console.log("Initiating withdrawal from SageStaking contract...");
        console.log("Contract Address:", SAGE_STAKING);
        console.log("Position Nonce:", nonce);
        
        // Start broadcasting - this will use your keystore account
        vm.startBroadcast();
        
        SageStaking staking = SageStaking(SAGE_STAKING);
        
        // Get current cooldown period for display
        uint256 cooldownPeriod = staking.cooldownPeriod();
        console.log("Cooldown period:", cooldownPeriod, "seconds");
        
        // Initiate the withdrawal
        // The on-chain contract will validate the position exists and is Active
        console.log("Initiating withdrawal...");
        staking.initiateWithdraw(nonce);
        
        console.log("Withdrawal initiated successfully!");
        console.log("You can withdraw after the cooldown period");
        
        vm.stopBroadcast();
    }
}
