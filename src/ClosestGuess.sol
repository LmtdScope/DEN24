// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract ClosestGuess {
    uint256 public number;

    function closestGuess(uint256) public {}

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
