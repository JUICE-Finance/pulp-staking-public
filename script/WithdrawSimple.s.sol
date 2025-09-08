// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SageStaking} from "../src/SageStaking.sol";

contract WithdrawSimpleScript is Script {
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
        
        console.log("Withdrawing from SageStaking contract...");
        console.log("Contract Address:", SAGE_STAKING);
        console.log("Position Nonce:", nonce);
        
        // Start broadcasting - this will use your keystore account
        vm.startBroadcast();
        
        SageStaking staking = SageStaking(SAGE_STAKING);
        
        // Execute the withdrawal
        // The on-chain contract will validate the cooldown has expired
        console.log("Executing withdrawal...");
        staking.withdraw(nonce);
        
        console.log("Withdrawal successful!");
        console.log("Your SAGE tokens have been returned to your wallet");
        
        vm.stopBroadcast();
    }
}
