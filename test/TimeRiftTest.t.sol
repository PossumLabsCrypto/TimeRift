// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {TimeRift} from "../src/TimeRift.sol";
import {MintBurnToken} from "../src/MintBurnToken.sol";

contract TimeRiftTest is Test {
    MintBurnToken FLASH_Token;
    MintBurnToken PSM_Token;
    TimeRift timeRift;

    address FLASH_Treasury;
    address PSM_Treasury;

    address F_token;
    address P_token;

    uint256 minStakeDuration;
    uint256 energyBoltsAccrualRate;
    uint256 withdrawPenaltyPercent;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = address(this);

    address whitelistOne = makeAddr("WL1");
    address whitelistTwo = makeAddr("WL2");

    function setUp() external {
        // deploy the test tokens
        FLASH_Token = new MintBurnToken("Flashstake", "FLASH");
        PSM_Token = new MintBurnToken("Possum", "PSM");

        // define the constructor inputs
        FLASH_Treasury = 0xEeB3f4E245aC01792ECd549d03b91541BC800b31;
        PSM_Treasury = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

        F_token = address(FLASH_Token);
        P_token = address(PSM_Token);

        minStakeDuration = 7776000;
        energyBoltsAccrualRate = 150;
        withdrawPenaltyPercent = 2;

        // deploy the dummy TimeRift
        timeRift = new TimeRift(
            F_token,
            P_token,
            FLASH_Treasury,
            PSM_Treasury,
            minStakeDuration,
            energyBoltsAccrualRate,
            withdrawPenaltyPercent
        );
    }

    // ============================================
    // Test initialisation values of parameters
    function testGlobalVariables_Start() public {
        assertEq(timeRift.FLASH_ADDRESS(), F_token);
        assertEq(timeRift.PSM_ADDRESS(), P_token);
        assertEq(
            timeRift.FLASH_TREASURY(),
            0xEeB3f4E245aC01792ECd549d03b91541BC800b31
        );
        assertEq(
            timeRift.PSM_TREASURY(),
            0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33
        );

        assertEq(timeRift.MINIMUM_STAKE_DURATION(), 7776000);
        assertEq(timeRift.ENERGY_BOLTS_ACCRUAL_RATE(), 150);
        assertEq(timeRift.WITHDRAW_PENALTY_PERCENT(), 2);

        assertEq(timeRift.stakedTokensTotal(), 0);
        assertEq(timeRift.PSM_distributed(), 0);
        assertEq(timeRift.conversionBalanceTotal(), 0);
        assertEq(timeRift.available_PSM(), 0);
    }

    // // ============================================
    // // Test Staking success and failure cases including _collectEnergyBolts test
    // function testStake_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // function testStake_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }

    // // ============================================
    // // Test withdraw/Exit success and failure cases
    // function testWithdrawAndExit_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // function testWithdrawAndExit_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }

    // // ============================================
    // // Test distributeEnergyBolts success and failure cases
    // function testDistributeEnergyBolts_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // function testDistributeEnergyBolts_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }

    // // ============================================
    // // Test convertToPSM success and failure cases
    // function testConvertToPSM_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // function testConvertToPSM_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }

    // ============================================
    // Test addToWhitelist success and failure cases
    function testAddToWhitelist_Failure() public {
        vm.startPrank(alice);
        console.log(alice);

        // Check that Bob is not whitelisted before the function call
        assertTrue(!timeRift.whitelist(bob), "Bob was already whitelisted");
        console.log(timeRift.whitelist(bob));

        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature("addToWhitelist(address)", bob)
        );

        // Check that the call was not successful
        assertTrue(!success, "Reverted because non-owner");

        // Check that Bob is still not whitelisted after the function call
        assertTrue(!timeRift.whitelist(bob), "Bob was added to the whitelist");
        console.log(timeRift.whitelist(bob));

        vm.stopPrank();
    }

    function testAddToWhitelist_Success() public {
        vm.prank(owner);
        timeRift.addToWhitelist(whitelistOne);
        assertTrue(
            timeRift.whitelist(whitelistOne),
            "whitelistOne was not added to the whitelist"
        );
    }

    // // ============================================
    // // Test removeFromWhitelist success and failure cases
    // function testRemoveFromWhitelist_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // function testRemoveFromWhitelist_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }

    // // ============================================
    // function testRescueToken_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // // Test rescueToken success and failure cases
    // function testRescueToken_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }

    // // ============================================
    // // Test getAvailablePSM success and failure cases
    // function testGetAvailablePSM_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // function testGetAvailablePSM_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }

    // // ============================================
    // // Test getUserEnergyBolts success and failure cases
    // function testGetUserEnergyBolts_Failure() public {
    //     timeRift.stake(100);

    //     uint256 totalStaked = timeRift.stakedTokensTotal();

    //     assertFalse(totalStaked == 100);
    // }

    // function testGetUserEnergyBolts_Success() public {
    //     timeRift.stake(100);
    //     assertEq(timeRift.stakedTokensTotal(), 100);
    // }
}
