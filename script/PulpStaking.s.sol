// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Staking} from "../src/PulpStaking.sol";

contract PulpStakingScript is Script {
    Staking public staking;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // TODO: Replace with actual token address before deployment
        address tokenAddress = 0x0000000000000000000000000000000000000000;
        uint256 cooldownPeriod = 2 weeks;
        
        staking = new Staking(cooldownPeriod, tokenAddress);

        vm.stopBroadcast();
    }
}
