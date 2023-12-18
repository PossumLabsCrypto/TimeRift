// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {TimeRift} from "../src/TimeRift.sol";
import {MintBurnToken} from "../src/MintBurnToken.sol";

contract TimeRiftTest is Test {
    MintBurnToken FLASH_Token;
    MintBurnToken PSM_Token;
    MintBurnToken randomToken;
    TimeRift timeRift;

    address FLASH_Treasury;
    address PSM_Treasury;

    address F_token;
    address P_token;
    address R_token;

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
        randomToken = new MintBurnToken("Rando", "RND");

        // define the constructor inputs
        FLASH_Treasury = 0xEeB3f4E245aC01792ECd549d03b91541BC800b31;
        PSM_Treasury = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

        F_token = address(FLASH_Token);
        P_token = address(PSM_Token);
        R_token = address(randomToken);

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
        assertEq(timeRift.exchangeBalanceTotal(), 0);
        assertEq(timeRift.available_PSM(), 0);
    }

    // // ============================================
    // // Test Staking success and failure cases including _collectEnergyBolts test
    // function testStake_Success() public {

    // }

    // // ============================================
    // function testStake_Failure() public {

    // }

    // // ============================================
    // function test_collectEnergyBolts_Success() public {

    // }

    // // ============================================
    // function test_collectEnergyBolts_Failure() public {

    // }

    // // ============================================
    // // Test withdraw/Exit success and failure cases
    // function testWithdrawAndExit_Success() public {

    // }

    // // ============================================
    // function testWithdrawAndExit_Failure() public {

    // }

    // // ============================================
    // // Test distributeEnergyBolts success and failure cases
    // function testDistributeEnergyBolts_Success() public {

    // }

    // // ============================================
    // function testDistributeEnergyBolts_Failure() public {

    // }

    // // ============================================
    // // Test exchangeToPSM success and failure cases
    // function testExchangeToPSM_Success() public {
    //     vm.startPrank(owner);

    //     uint256 FLASH_amount = 123000;

    //     FLASH_Token.mint(address(timeRift), FLASH_amount);

    //     uint256 user_exchangeBalance = 12;

    //     // Call the function using low-level call
    //     (bool success, ) = address(timeRift).call(
    //         abi.encodeWithSignature("exchangeToPSM()")
    //     );

    //     // Check that the call was successful
    //     assertTrue(success, "Reverted the token transaction");
    //     assertEq(
    //         FLASH_Token.balanceOf(address(timeRift)),
    //         FLASH_amount - user_exchangeBalance
    //     );
    //     assertEq(PSM_Token.balanceOf(address(this)), FLASH_amount);

    //     vm.stopPrank();
    // }

    // // ============================================
    // function testExchangeToPSM_Failure() public {

    // }

    // ================================================
    // Test addToWhitelist success and failure cases
    function testAddToWhitelist_Success() public {
        vm.prank(owner);
        timeRift.addToWhitelist(whitelistOne);
        assertTrue(
            timeRift.whitelist(whitelistOne),
            "whitelistOne was not added to the whitelist"
        );
    }

    // ============================================
    function testAddToWhitelist_Failure() public {
        vm.startPrank(alice);

        // Check that Bob is not whitelisted before the function call
        assertTrue(!timeRift.whitelist(bob), "Bob was already whitelisted");

        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature("addToWhitelist(address)", bob)
        );

        // Check that the call was not successful
        assertTrue(!success, "Reverted because non-owner");

        // Check that Bob is still not whitelisted after the function call
        assertTrue(!timeRift.whitelist(bob), "Bob was added to the whitelist");

        vm.stopPrank();
    }

    // ================================================
    // Test removeFromWhitelist success and failure cases
    function testRemoveFromWhitelist_Success() public {
        testAddToWhitelist_Success();

        vm.startPrank(owner);

        // Check that whitelistOne is whitelisted before the function call
        assertTrue(timeRift.whitelist(whitelistOne), "Address not whitelisted");

        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "removeFromWhitelist(address)",
                whitelistOne
            )
        );

        // Check that the call was successful
        assertTrue(success, "Reverted the removal / caller not owner");

        assertFalse(
            timeRift.whitelist(whitelistOne),
            "whitelistOne was not removed from the whitelist"
        );

        vm.stopPrank();
    }

    // // ============================================
    function testRemoveFromWhitelist_Failure() public {
        testAddToWhitelist_Success();

        vm.startPrank(alice);

        // Check that whitelistOne is whitelisted before the function call
        assertTrue(timeRift.whitelist(whitelistOne), "Address not whitelisted");

        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "removeFromWhitelist(address)",
                whitelistOne
            )
        );

        // Check that the call was not successful
        assertTrue(!success, "Reverted because non-owner");

        // Check that whitelistOne is still on the whitelisted
        assertTrue(
            timeRift.whitelist(whitelistOne),
            "WhitelistOne was removed from the whitelist"
        );

        vm.stopPrank();
    }

    // ============================================
    // Test rescueToken success and failure cases
    function testRescueToken_Success() public {
        vm.startPrank(owner);

        uint256 RND_amount = 1000;

        randomToken.mint(address(timeRift), RND_amount);

        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature("rescueToken(address)", randomToken)
        );

        // Check that the call was successful
        assertTrue(success, "Reverted the token transaction");
        assertEq(randomToken.balanceOf(address(timeRift)), 0);
        assertEq(randomToken.balanceOf(address(this)), RND_amount);

        vm.stopPrank();
    }

    // ================================================
    function testRescueToken_Failure() public {
        vm.startPrank(owner);

        // Test case: zero amount
        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature("rescueToken(address)", randomToken)
        );

        // Check that the call was not successful
        assertTrue(!success, "Token transfer was executed");
        assertEq(randomToken.balanceOf(address(timeRift)), 0);
        assertEq(randomToken.balanceOf(address(this)), 0);

        // Test case: is PSM token
        uint256 PSM_amount = 333;
        PSM_Token.mint(address(timeRift), PSM_amount);

        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("rescueToken(address)", PSM_Token)
        );

        // Check that the call was not successful
        assertTrue(!success, "Token transfer was executed");
        assertEq(PSM_Token.balanceOf(address(timeRift)), PSM_amount);
        assertEq(PSM_Token.balanceOf(address(this)), 0);

        // Test case: is FLASH token
        uint256 FLASH_amount = 555;
        FLASH_Token.mint(address(timeRift), FLASH_amount);

        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("rescueToken(address)", FLASH_Token)
        );

        // Check that the call was not successful
        assertTrue(!success, "Token transfer was executed");
        assertEq(FLASH_Token.balanceOf(address(timeRift)), FLASH_amount);
        assertEq(FLASH_Token.balanceOf(address(this)), 0);

        // Test case: is not owner
        uint256 RND_Amount = 1000;
        randomToken.mint(address(timeRift), RND_Amount);
        vm.stopPrank();

        vm.startPrank(alice);
        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("rescueToken(address)", randomToken)
        );

        // Check that the call was not successful
        assertTrue(!success, "Token transfer was executed");

        assertEq(randomToken.balanceOf(address(timeRift)), RND_Amount);
        assertEq(randomToken.balanceOf(address(this)), 0);

        vm.stopPrank();
    }

    // // ============================================
    // // Test getUserEnergyBolts success and failure cases
    // function testGetUserEnergyBolts_Success() public {

    // }

    // // ============================================
    // function testGetUserEnergyBolts_Failure() public {

    // }
}
