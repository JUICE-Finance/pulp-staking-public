// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SageStaking} from "../src/SageStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DepositSimpleScript is Script {
    // Deployed contract address on Base mainnet
    address constant SAGE_STAKING = 0x413D15aFe510cD1003540E8EF57A29eF9a086Efc;
    
    function setUp() public {}

    function run() public {
        // Get SAGE token address from environment
        address sageTokenAddress = vm.envAddress("SAGE_TOKEN_ADDRESS");
        
        // Amount to deposit: 10 SAGE tokens (assuming 18 decimals)
        uint256 depositAmount = 10 * 1e18;
        
        console.log("Depositing SAGE tokens into staking contract...");
        console.log("Staking Contract:", SAGE_STAKING);
        console.log("SAGE Token:", sageTokenAddress);
        console.log("Deposit Amount:", depositAmount / 1e18, "SAGE");
        
        // Start broadcasting - during actual broadcast, this uses your keystore account
        vm.startBroadcast();
        
        IERC20 sageToken = IERC20(sageTokenAddress);
        SageStaking staking = SageStaking(SAGE_STAKING);
        
        // Approve and deposit in one go
        // The actual balance check happens on-chain during broadcast
        sageToken.approve(SAGE_STAKING, depositAmount);
        staking.deposit(depositAmount);
        
        console.log("Successfully deposited", depositAmount / 1e18, "SAGE tokens!");
        
        vm.stopBroadcast();
    }
}
