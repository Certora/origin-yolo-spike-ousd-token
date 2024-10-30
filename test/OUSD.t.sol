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
        assertEq(ousd.totalSupply(), 1000 ether);
        ousd.mint(labs, 1000 ether);
        ousd.mint(pool, 1000 ether);
        ousd.mint(collector, 1000 ether);
        ousd.mint(attacker, 1000 ether);
        assertEq(ousd.totalSupply(), 5000 ether);

        vm.prank(pool);
        ousd.rebaseOptOut();

        vm.prank(collector);
        ousd.rebaseOptOut();
        vm.prank(collector);
        ousd.rebaseOptIn();
        
        ousd.delegateYield(pool, collector);
        assertEq(ousd.totalSupply(), 5000 ether);
        assertEq(ousd.nonRebasingSupply(), 1000 ether);
    }

    function test_ChangeSupply() public {
        assertEq(ousd.totalSupply(), 5000 ether);
        assertEq(ousd.nonRebasingSupply(), 1000 ether);
        ousd.changeSupply(6000 ether);
        assertEq(ousd.totalSupply(), 6000 ether);
        assertEq(ousd.nonRebasingSupply(), 1000 ether);
    }


    function test_CanDelegateYield() public {
        vm.prank(matt);
        ousd.rebaseOptOut();
        ousd.delegateYield(matt, attacker);
    }

    function test_NoDelegateYieldToSelf() public {
        vm.expectRevert("Cannot delegate to self");
        ousd.delegateYield(matt, matt);
    }

    function test_NoDelegateYieldToDelegator() public {
        vm.expectRevert("Cannot delegate to delegator");
        ousd.delegateYield(matt, pool);
    }

    function test_NoDelegateYieldFromReceiver() public {
        assertEq(ousd.yieldDelegateeCount(collector),1);
        vm.expectRevert("Cannot delegate from delegatee");
        ousd.delegateYield(collector, matt);
    }
    
    function test_CanUndelegeteYield() public {
        ousd.undelegateYield(pool);
        assertEq(ousd.yieldDelegate(pool), address(0));
    }
}
