// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {GoalPledgeEscrow} from "../contracts/GoalPledgeEscrow.sol";

contract Deploy is Script {
    function run() external {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint64 minBuffer = uint64(vm.envUint("MIN_DEADLINE_BUFFER"));
        address usdc = vm.envAddress("USDC_ADDRESS");

        vm.startBroadcast();
        GoalPledgeEscrow escrow = new GoalPledgeEscrow(usdc, treasury, minBuffer);
        vm.stopBroadcast();

        console2.log("GoalPledgeEscrow:", address(escrow));
    }
}

