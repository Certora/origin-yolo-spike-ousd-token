// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {OUSD} from "../src/token/OUSD.sol";

contract CounterTest is Test {
    OUSD public ousd;

    address public matt = makeAddr("Matt");
    address public labs = makeAddr("NonRebasing");
    address public pool = makeAddr("Pool");
    address public collector = makeAddr("Collector");
    address public attacker = makeAddr("Attacker");
    address[] accounts = [matt, attacker, labs, pool, collector];

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

        vm.prank(labs);
        ousd.rebaseOptOut();

        vm.prank(pool);
        ousd.rebaseOptOut();

        vm.prank(collector);
        ousd.rebaseOptOut();
        vm.prank(collector);
        ousd.rebaseOptIn();

        assertEq(ousd.nonRebasingSupply(), 2000 ether);
        ousd.delegateYield(pool, collector);
        assertEq(ousd.nonRebasingSupply(), 1000 ether, "delegate should decrease rebasing");
        assertEq(ousd.totalSupply(), 5000 ether);
    }

    function test_ChangeSupply() public {
        assertEq(ousd.totalSupply(), 6000 ether);
        assertEq(ousd.nonRebasingSupply(), 1000 ether);
        ousd.changeSupply(7000 ether);
        assertEq(ousd.totalSupply(), 7000 ether);
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
        vm.expectRevert("Blocked by existing yield delegation");
        ousd.delegateYield(matt, pool);
    }

    function test_NoDelegateYieldFromReceiver() public {
        vm.expectRevert("Blocked by existing yield delegation");
        ousd.delegateYield(collector, matt);
    }

    function test_CanUndelegeteYield() public {
        assertEq(ousd.yieldTo(pool), collector);
        ousd.undelegateYield(pool);
        assertEq(ousd.yieldTo(pool), address(0));
    }

    function testDelegateYield() public {
        
        ousd.changeSupply(ousd.totalSupply() + 1000 ether);
        assertEq(ousd.balanceOf(matt), 100);
        
    }

    function test_Transfers() external {
        for (uint256 i = 0; i < accounts.length; i++) {
            for (uint256 j = 0; j < accounts.length; j++) {
                console.log("Transferring from ", accounts[i], " to ", accounts[j]);
                address from = accounts[i];
                address to = accounts[j];
                uint256 amount = 7 ether + 1231231203815;
                uint256 fromBefore = ousd.balanceOf(from);
                uint256 toBefore = ousd.balanceOf(to);
                uint256 totalSupplyBefore = ousd.totalSupply();
                vm.prank(from);
                ousd.transfer(to, amount);
                if (from == to) {
                    assertEq(ousd.balanceOf(from), fromBefore);
                } else {
                    assertEq(ousd.balanceOf(from), fromBefore - amount, "From account balance should decrease");
                    assertEq(ousd.balanceOf(to), toBefore + amount, "To account balance should increase");
                }
                assertEq(ousd.totalSupply(), totalSupplyBefore);
            }
        }
    }
}
