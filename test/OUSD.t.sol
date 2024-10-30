// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {OUSD} from "../src/token/OUSD.sol";

contract CounterTest is Test {
    OUSD public ousd;

    address public matt = makeAddr("Matt");
    address public labs = makeAddr("Labs");
    address public pool = makeAddr("Pool");
    address public collector = makeAddr("Collector");
    address public attacker = makeAddr("Attacker");



    function setUp() public {
        ousd = new OUSD();
        ousd.initialize("", "", address(this), 314159265358979323846264333);
        
        ousd.mint(matt, 1000 ether);
        ousd.mint(labs, 1000 ether);
        ousd.mint(pool, 1000 ether);
        ousd.mint(collector, 1000 ether);
        ousd.mint(attacker, 1000 ether);
    }

    function test_ChangeSupply() public {
        ousd.changeSupply(1000 ether);
        assertEq(ousd.totalSupply(), 1000 ether);
    }

    // function testFuzz_SetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
