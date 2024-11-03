// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {OUSD} from "../src/token/OUSD.sol";

contract CounterTest is Test {
    OUSD public ousd;

    address public matt = makeAddr("Matt");
    address public nonrebasing = makeAddr("NonRebasing");
    address public pool = makeAddr("Pool");
    address public collector = makeAddr("Collector");
    address public attacker = makeAddr("Attacker");
    address[] accounts = [matt, attacker, nonrebasing, pool, collector];

    function setUp() public {
        ousd = new OUSD();
        ousd.initialize("", "", address(this), 314159265358979323846264333);

        ousd.mint(matt, 1000 ether);
        assertEq(ousd.totalSupply(), 1000 ether);
        ousd.mint(nonrebasing, 1000 ether);
        ousd.mint(pool, 1000 ether);
        ousd.mint(collector, 1000 ether);
        ousd.mint(attacker, 1000 ether);
        assertEq(ousd.totalSupply(), 5000 ether);

        vm.prank(nonrebasing);
        ousd.rebaseOptOut();

        vm.prank(pool);
        ousd.rebaseOptOut();

        vm.prank(collector);
        ousd.rebaseOptOut();
        vm.prank(collector);
        ousd.rebaseOptIn();
        

        assertEq(ousd.nonRebasingSupply(), 2000 ether);
        ousd.delegateYield(pool, collector);
        assertEq(ousd.nonRebasingSupply(), 1000 ether, "delegate should decrease nonrebasing");
        assertEq(ousd.totalSupply(), 5000 ether);
        assertEq(ousd.balanceOf(pool), 1000 ether);
        assertEq(ousd.balanceOf(collector), 1000 ether);
    }

    function _show() internal {
        console.log("  ..totalSupply: ", ousd.totalSupply());
        console.log("  ..nonRebasingSupply: ", ousd.nonRebasingSupply());
        console.log("  ..rebasingCredits: ", ousd.rebasingCreditsHighres());
        console.log("  ..rebasingCreditsPerToken: ", ousd.rebasingCreditsPerTokenHighres());
    }

    function test_ChangeSupply() public {
        assertEq(ousd.totalSupply(), 5000 ether);
        assertEq(ousd.nonRebasingSupply(), 1000 ether);
        ousd.changeSupply(7000 ether);
        assertEq(ousd.totalSupply(), 7000 ether);
        assertEq(ousd.nonRebasingSupply(), 1000 ether);
    }

    function test_SimpleRebasingCredits() public {
        // Create an OUSD with a very simple credits to token ratio.
        // This doesn't test rouding, but does make for nice human readable numbers
        // to check the directions of things

        ousd = new OUSD();
        ousd.initialize("", "", address(this), 1e27 / 2);

        ousd.mint(matt, 1000 ether);
        assertEq(ousd.rebasingCredits(), 500 ether);
        
        ousd.mint(nonrebasing, 1000 ether);
        assertEq(ousd.rebasingCredits(), 1000 ether);        

        vm.prank(nonrebasing);
        ousd.rebaseOptOut();
        assertEq(ousd.rebasingCredits(), 500 ether, "rebaseOptOut should reducing total rebasing credits");

        ousd.burn(matt, 500 ether);
        assertEq(ousd.rebasingCredits(), 250 ether, "rebasing burn should reduce rebasing credits");

        ousd.burn(nonrebasing, 500 ether);
        assertEq(ousd.rebasingCredits(), 250 ether);

        // Add yield
        assertEq(ousd.balanceOf(matt), 500 ether, "matt should have 500 OUSD");
        ousd.changeSupply(2000 ether);
        assertEq(ousd.balanceOf(matt), 1500 ether, "all yield should go to matt");
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
        
        console.log(ousd.totalSupply()/1e18);
        console.log(ousd.balanceOf(matt)*1/1e18);
        
        ousd.changeSupply(ousd.totalSupply() + 1000 ether);
        assertEq(ousd.balanceOf(matt), 1250 ether);
        assertEq(ousd.balanceOf(collector), 1500 ether, "Collecter should have earned both yields");
        
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
