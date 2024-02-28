// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ClosestGuess} from "src/ClosestGuess.sol";

contract DeployClosestGuess is Script {
    function run() external returns (ClosestGuess) {
        vm.startBroadcast();
        ClosestGuess closestGuess = new ClosestGuess();
        vm.stopBroadcast();
        return closestGuess;
    }
}
