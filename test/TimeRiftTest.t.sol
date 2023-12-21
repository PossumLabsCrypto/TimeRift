// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {TimeRift} from "../src/TimeRift.sol";
import {MintBurnToken} from "../src/MintBurnToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TimeRiftTest is Test {
    MintBurnToken FLASH_Token = new MintBurnToken("FLASH", "FLASH");
    MintBurnToken PSM_Token = new MintBurnToken("PSM", "PSM");
    MintBurnToken randomToken;
    TimeRift timeRift;

    address FLASH_Treasury;
    address PSM_Treasury;

    uint256 minStakeDuration;
    uint256 energyBoltsAccrualRate;
    uint256 withdrawPenaltyPercent;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = address(this);

    uint256 constant PSM_AMOUNT_RIFT = 5e26;
    uint256 constant FLASH_AMOUNT_ALICE = 1e30;
    uint256 constant FLASH_AMOUNT_BOB = 1e26;

    uint256 constant ENERGY_BOLTS_ACCRUAL_RATE = 150;
    uint256 constant SECONDS_PER_YEAR = 31536000;

    struct Stake {
        uint256 lastStakeTime;
        uint256 lastCollectTime;
        uint256 stakedTokens;
        uint256 energyBolts;
        uint256 exchangeBalance;
    }

    // Set initial conditions
    function setUp() external {
        // deploy the test tokens
        FLASH_Token = new MintBurnToken("Flashstake", "FLASH");
        PSM_Token = new MintBurnToken("Possum", "PSM");
        randomToken = new MintBurnToken("Rando", "RND");

        // define the constructor inputs
        FLASH_Treasury = 0xEeB3f4E245aC01792ECd549d03b91541BC800b31;
        PSM_Treasury = 0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

        minStakeDuration = 7776000;
        energyBoltsAccrualRate = 150;
        withdrawPenaltyPercent = 2;

        // deploy the dummy TimeRift
        timeRift = new TimeRift(
            address(FLASH_Token),
            address(PSM_Token),
            FLASH_Treasury,
            PSM_Treasury,
            minStakeDuration,
            energyBoltsAccrualRate,
            withdrawPenaltyPercent
        );

        // distribute tokens to addresses
        PSM_Token.mint(address(timeRift), PSM_AMOUNT_RIFT);
        FLASH_Token.mint(alice, FLASH_AMOUNT_ALICE);
        FLASH_Token.mint(bob, FLASH_AMOUNT_BOB);
    }

    // ============================================
    // Test initialisation values of parameters
    function testGlobalVariables_Start() public {
        assertEq(timeRift.FLASH_ADDRESS(), address(FLASH_Token));
        assertEq(timeRift.PSM_ADDRESS(), address(PSM_Token));
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

        assertEq(timeRift.getAvailablePSM(), PSM_AMOUNT_RIFT);
    }

    // ============================================
    // Test Staking success and failure cases including _collectEnergyBolts
    function testStake_Success() public {
        uint256 timeStamp = block.timestamp;
        uint256 stakeAmount = 1e22;
        uint256 timePassed = 31536000;

        // test case: FIRST STAKE
        vm.startPrank(alice);

        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);

        vm.stopPrank();

        (
            uint256 user_lastStakeTime,
            uint256 user_lastCollectTime,
            uint256 user_stakedTokens,
            uint256 user_energyBolts,
            uint256 user_exchangeBalance
        ) = timeRift.stakes(alice);

        assertEq(FLASH_Token.balanceOf(address(timeRift)), stakeAmount);
        assertEq(
            FLASH_Token.balanceOf(address(alice)),
            FLASH_AMOUNT_ALICE - stakeAmount
        );
        assertEq(timeRift.stakedTokensTotal(), stakeAmount);
        assertEq(timeRift.exchangeBalanceTotal(), stakeAmount);

        assertEq(user_lastStakeTime, timeStamp);
        assertEq(user_lastCollectTime, timeStamp);
        assertEq(user_stakedTokens, stakeAmount);
        assertEq(user_energyBolts, 0);
        assertEq(user_exchangeBalance, stakeAmount);

        assertEq(timeRift.getAvailablePSM(), PSM_AMOUNT_RIFT - stakeAmount);

        // test case: RESTAKE
        vm.warp(timePassed);
        timeStamp = block.timestamp;

        uint256 energyBoltsCollected = ((timeStamp - user_lastCollectTime) *
            user_stakedTokens *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        vm.startPrank(alice);

        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);

        vm.stopPrank();

        (
            user_lastStakeTime,
            user_lastCollectTime,
            user_stakedTokens,
            user_energyBolts,
            user_exchangeBalance
        ) = timeRift.stakes(alice);

        uint256 expectedEnergyBolts = energyBoltsCollected;

        assertEq(FLASH_Token.balanceOf(address(timeRift)), stakeAmount * 2);
        assertEq(
            FLASH_Token.balanceOf(address(alice)),
            FLASH_AMOUNT_ALICE - stakeAmount * 2
        );
        assertEq(timeRift.stakedTokensTotal(), stakeAmount * 2);
        assertEq(timeRift.exchangeBalanceTotal(), stakeAmount * 2);

        assertEq(user_lastStakeTime, timeStamp);
        assertEq(user_lastCollectTime, timeStamp);
        assertEq(user_stakedTokens, stakeAmount * 2);
        assertEq(user_energyBolts, expectedEnergyBolts);
        assertEq(user_exchangeBalance, stakeAmount * 2);

        assertEq(timeRift.getAvailablePSM(), PSM_AMOUNT_RIFT - stakeAmount * 2);

        // test case: STAKE MORE THAN AVAILABLE
        stakeAmount = timeRift.getAvailablePSM() + 1e25;

        vm.startPrank(alice);

        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);

        vm.stopPrank();

        (
            user_lastStakeTime,
            user_lastCollectTime,
            user_stakedTokens,
            user_energyBolts,
            user_exchangeBalance
        ) = timeRift.stakes(alice);

        assertEq(FLASH_Token.balanceOf(address(timeRift)), PSM_AMOUNT_RIFT);
        assertEq(
            FLASH_Token.balanceOf(address(alice)),
            FLASH_AMOUNT_ALICE - PSM_AMOUNT_RIFT
        );
        assertEq(timeRift.stakedTokensTotal(), PSM_AMOUNT_RIFT);
        assertEq(timeRift.exchangeBalanceTotal(), PSM_AMOUNT_RIFT);

        assertEq(user_lastStakeTime, timeStamp);
        assertEq(user_lastCollectTime, timeStamp);
        assertEq(user_stakedTokens, PSM_AMOUNT_RIFT);
        assertEq(user_energyBolts, expectedEnergyBolts);
        assertEq(user_exchangeBalance, PSM_AMOUNT_RIFT);

        assertEq(timeRift.getAvailablePSM(), 0);
    }

    // ============================================
    function testStake_Failure() public {
        bool success;

        vm.startPrank(alice);

        // test case: NO APPROVAL
        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("stake(uint256)", 1e23)
        );

        // Check that the call was not successful
        assertTrue(!success, "Tx confirmed albeit missing approval");

        // test case: ZERO INPUT
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("stake(uint256)", 0)
        );

        // Check that the call was not successful
        assertTrue(!success, "Tx confirmed albeit zero input");

        // test case: ZERO PSM AVAILABLE
        testStake_Success();

        FLASH_Token.approve(address(timeRift), 1000);

        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("stake(uint256)", 1000)
        );

        // Check that the call was not successful
        assertTrue(!success, "Tx confirmed albeit no PSM available");

        vm.stopPrank();
    }

    // ============================================
    // Test withdraw/Exit success and failure cases
    function testWithdrawAndExit_Success() public {
        uint256 timeStamp = block.timestamp;
        uint256 stakeAmount = 1e22;

        // STAKE
        vm.startPrank(alice);

        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);

        vm.stopPrank();

        (
            uint256 user_lastStakeTime,
            uint256 user_lastCollectTime,
            uint256 user_stakedTokens,
            uint256 user_energyBolts,
            uint256 user_exchangeBalance
        ) = timeRift.stakes(alice);

        assertEq(FLASH_Token.balanceOf(address(timeRift)), stakeAmount);
        assertEq(
            FLASH_Token.balanceOf(address(alice)),
            FLASH_AMOUNT_ALICE - stakeAmount
        );
        assertEq(timeRift.stakedTokensTotal(), stakeAmount);
        assertEq(timeRift.exchangeBalanceTotal(), stakeAmount);

        assertEq(user_lastStakeTime, timeStamp);
        assertEq(user_lastCollectTime, timeStamp);
        assertEq(user_stakedTokens, stakeAmount);
        assertEq(user_energyBolts, 0);
        assertEq(user_exchangeBalance, stakeAmount);

        assertEq(timeRift.getAvailablePSM(), PSM_AMOUNT_RIFT - stakeAmount);

        // WITHDRAW AND EXIT
        vm.prank(alice);
        timeRift.withdrawAndExit();

        (
            user_lastStakeTime,
            user_lastCollectTime,
            user_stakedTokens,
            user_energyBolts,
            user_exchangeBalance
        ) = timeRift.stakes(alice);

        uint256 penalty = (stakeAmount * 2) / 100;

        assertEq(FLASH_Token.balanceOf(address(timeRift)), 0);
        assertEq(
            FLASH_Token.balanceOf(address(alice)),
            FLASH_AMOUNT_ALICE - penalty
        );
        assertEq(timeRift.getAvailablePSM(), PSM_AMOUNT_RIFT - stakeAmount);
        assertEq(FLASH_Token.balanceOf(FLASH_Treasury), penalty);

        assertEq(timeRift.stakedTokensTotal(), 0);
        assertEq(timeRift.exchangeBalanceTotal(), 0);

        assertEq(user_lastStakeTime, 0);
        assertEq(user_lastCollectTime, 0);
        assertEq(user_stakedTokens, 0);
        assertEq(user_energyBolts, 0);
        assertEq(user_exchangeBalance, 0);
    }

    // ============================================
    function testWithdrawAndExit_Failure() public {
        vm.startPrank(alice);

        // test case: USER HAS ZERO STAKED TOKENS
        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature("withdrawAndExit()")
        );

        vm.stopPrank();

        // Check that the call was not successful
        assertTrue(!success, "Tx confirmed but user has no stake");
    }

    // ============================================
    // Test distributeEnergyBolts success and failure cases
    function testDistributeEnergyBolts_Success1() public {
        // Staking action
        uint256 timeStampStake = block.timestamp;
        uint256 stakeAmount = PSM_AMOUNT_RIFT / 2;

        vm.startPrank(alice);
        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);
        vm.stopPrank();

        // Whitelist PSM Treasury
        testAddToWhitelist_Success();

        // Distribution testing case 1: Full distribution and exchangeBalance increase
        address destination = PSM_Treasury;
        uint256 PSMdistributable = timeRift.getAvailablePSM();
        uint256 distributionAmount_1 = PSMdistributable / 5; // 2*0.2 = 40% < 100% -> have PSM leftover, can serve full distr + exchangeBal

        vm.warp(SECONDS_PER_YEAR);

        vm.prank(alice);
        timeRift.distributeEnergyBolts(destination, distributionAmount_1);

        (
            uint256 user_lastStakeTime,
            uint256 user_lastCollectTime,
            uint256 user_stakedTokens,
            uint256 user_energyBolts,
            uint256 user_exchangeBalance
        ) = timeRift.stakes(alice);

        uint256 energyBoltsAccrued = ((user_lastCollectTime -
            user_lastStakeTime) *
            user_stakedTokens *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        uint256 timeStampCollect = block.timestamp;
        // uint256 timeRiftBalancePSM = PSM_Token.balanceOf(address(timeRift));
        // uint256 destinationBalance = PSM_Token.balanceOf(destination);
        // uint256 newTimeRiftBalPSM = PSM_AMOUNT_RIFT - distributionAmount_1;
        // uint256 remainingAvailablePSM = (PSM_AMOUNT_RIFT / 2) -
        //     (distributionAmount_1 * 2);
        uint256 newExchangeBalTotal = stakeAmount + distributionAmount_1;

        // assertEq(destinationBalance, distributionAmount_1);
        // assertEq(timeRiftBalancePSM, newTimeRiftBalPSM);
        // assertEq(timeRift.PSM_distributed(), distributionAmount_1);
        // assertEq(timeRift.exchangeBalanceTotal(), newExchangeBalTotal);
        // assertEq(timeRift.getAvailablePSM(), remainingAvailablePSM);

        assertTrue(timeStampStake < timeStampCollect);
        assertEq(user_lastStakeTime, timeStampStake);
        assertEq(user_lastCollectTime, timeStampCollect);
        assertEq(user_stakedTokens, stakeAmount);
        assertEq(user_energyBolts, energyBoltsAccrued - distributionAmount_1);
        assertEq(user_exchangeBalance, newExchangeBalTotal);
    }

    // ============================================
    function testDistributeEnergyBolts_Success2() public {
        // Staking action
        uint256 timeStampStake = block.timestamp;
        uint256 stakeAmount = PSM_AMOUNT_RIFT / 2;

        vm.startPrank(alice);
        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);
        vm.stopPrank();

        // Whitelist PSM Treasury
        testAddToWhitelist_Success();

        // Distribution testing case 2: Full exchangeBalance increase + distribute partly
        address destination = PSM_Treasury;
        uint256 PSMdistributable = timeRift.getAvailablePSM();
        uint256 inputAmount = (PSMdistributable * 3) / 5; // 2*60% = 120% > 100% -> use all remaining PSM, reduce distribution

        vm.warp(SECONDS_PER_YEAR);

        vm.prank(alice);
        timeRift.distributeEnergyBolts(destination, inputAmount);

        (
            uint256 user_lastStakeTime,
            uint256 user_lastCollectTime,
            uint256 user_stakedTokens,
            uint256 user_energyBolts,
            uint256 user_exchangeBalance
        ) = timeRift.stakes(alice);

        uint256 energyBoltsAccrued = ((user_lastCollectTime -
            user_lastStakeTime) *
            user_stakedTokens *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        uint256 timeStampCollect = block.timestamp;
        // uint256 rest = (PSMdistributable * 2) / 5;
        // uint256 destinationBalance = PSM_Token.balanceOf(destination);
        // uint256 newTimeRiftBalPSM = PSM_AMOUNT_RIFT - rest;
        // uint256 timeRiftBalancePSM = PSM_Token.balanceOf(address(timeRift));
        uint256 newExchangeBalTotal = stakeAmount + inputAmount;

        // assertEq(destinationBalance, rest);
        // assertEq(timeRift.PSM_distributed(), rest);
        // assertEq(timeRiftBalancePSM, newTimeRiftBalPSM);
        // assertEq(timeRift.exchangeBalanceTotal(), newExchangeBalTotal);
        // assertEq(timeRift.getAvailablePSM(), 0);

        assertTrue(timeStampStake < timeStampCollect);
        assertEq(user_lastStakeTime, timeStampStake);
        assertEq(user_lastCollectTime, timeStampCollect);
        assertEq(user_stakedTokens, stakeAmount);
        assertEq(user_energyBolts, energyBoltsAccrued - inputAmount);
        assertEq(user_exchangeBalance, newExchangeBalTotal);
    }

    // ============================================
    function testDistributeEnergyBolts_Success3() public {
        // Staking action
        uint256 timeStampStake = block.timestamp;
        uint256 stakeAmount = PSM_AMOUNT_RIFT / 2;

        vm.startPrank(alice);
        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);
        vm.stopPrank();

        // Whitelist PSM Treasury
        testAddToWhitelist_Success();

        // Distribution testing case 3: Partial exchangeBalance increase + no distribution
        address destination = PSM_Treasury;
        uint256 PSMdistributable = timeRift.getAvailablePSM();
        uint256 inputAmount = PSMdistributable * 2; // 2*200% = 400% > 100% -> use all remaining PSM for exchangeBal, no distr.

        vm.warp(SECONDS_PER_YEAR);

        vm.prank(alice);
        timeRift.distributeEnergyBolts(destination, inputAmount);

        (
            uint256 user_lastStakeTime,
            uint256 user_lastCollectTime,
            uint256 user_stakedTokens,
            uint256 user_energyBolts,
            uint256 user_exchangeBalance
        ) = timeRift.stakes(alice);

        uint256 energyBoltsAccrued = ((user_lastCollectTime -
            user_lastStakeTime) *
            user_stakedTokens *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        uint256 timeStampCollect = block.timestamp;
        // uint256 newTimeRiftBalPSM = PSM_AMOUNT_RIFT;
        // uint256 timeRiftBalancePSM = PSM_Token.balanceOf(address(timeRift));
        uint256 newExchangeBalTotal = PSM_AMOUNT_RIFT;

        // assertEq(timeRift.PSM_distributed(), 0);
        // assertEq(timeRiftBalancePSM, newTimeRiftBalPSM);
        // assertEq(timeRift.exchangeBalanceTotal(), newExchangeBalTotal);
        // assertEq(timeRift.getAvailablePSM(), 0);

        assertTrue(timeStampStake < timeStampCollect);
        assertEq(user_lastStakeTime, timeStampStake);
        assertEq(user_lastCollectTime, timeStampCollect);
        assertEq(user_stakedTokens, stakeAmount);
        assertEq(user_energyBolts, energyBoltsAccrued - PSMdistributable);
        assertEq(user_exchangeBalance, newExchangeBalTotal);
    }

    // ============================================
    function testDistributeEnergyBolts_Failure() public {
        // Staking action
        uint256 stakeAmount = PSM_AMOUNT_RIFT / 2;

        vm.startPrank(alice);
        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);
        vm.stopPrank();

        bool success;
        uint256 PSMdistributable = timeRift.getAvailablePSM();
        uint256 inputAmount = PSMdistributable * 20;

        vm.warp(SECONDS_PER_YEAR);
        vm.startPrank(alice);

        // test case: ZERO INPUT
        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "distributeEnergyBolts(address,uint256)",
                PSM_Treasury,
                0
            )
        );

        // Check that the call was not successful because of zero input
        assertTrue(!success, "Call was successful, expected revert");

        // test case: ZERO INPUT
        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "distributeEnergyBolts(address,uint256)",
                address(0),
                inputAmount
            )
        );

        // Check that the call was not successful because of zero address
        assertTrue(!success, "Call was successful, expected revert");

        // test case: ADDRESS NOT WHITELISTED
        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "distributeEnergyBolts(address,uint256)",
                PSM_Treasury,
                inputAmount
            )
        );

        // Check that the call was not successful because destination was not whitelisted
        assertTrue(!success, "Call was successful, expected revert");

        vm.stopPrank();

        // Whitelist PSM Treasury
        testAddToWhitelist_Success();

        vm.startPrank(alice);

        // test case: NO AVAILABLE PSM
        // Call the function the first time successfully, depleting available PSM
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "distributeEnergyBolts(address,uint256)",
                PSM_Treasury,
                inputAmount
            )
        );

        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "distributeEnergyBolts(address,uint256)",
                PSM_Treasury,
                inputAmount
            )
        );

        // Check that the call was not successful because there are no available PSM left
        assertTrue(!success, "Call was successful, expected revert");

        // test case: USER HAS NO ENERGY BOLTS
        (, , , uint256 energyBolts, ) = timeRift.stakes(alice);
        uint256 amountMint = energyBolts * 3;

        vm.stopPrank();
        vm.prank(owner);
        PSM_Token.mint(address(timeRift), amountMint);

        vm.startPrank(alice);
        // Call the function the first time successfully, depleting the user's Energy Bolts
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "distributeEnergyBolts(address,uint256)",
                PSM_Treasury,
                amountMint
            )
        );

        // Call the function the second time with insufficient Energy bolts
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "distributeEnergyBolts(address,uint256)",
                PSM_Treasury,
                amountMint
            )
        );

        // Check that the call was not successful because the user has no Energy Bolts
        assertTrue(!success, "Call was successful, expected revert");

        vm.stopPrank();
    }

    // ============================================
    // Test exchangeToPSM success and failure cases
    function testExchangeToPSM_Success() public {
        vm.startPrank(alice);

        uint256 stakeAmountAlice = 1e22;

        FLASH_Token.approve(address(timeRift), stakeAmountAlice);
        timeRift.stake(stakeAmountAlice);

        uint256 timePassed = 7776001;
        vm.warp(timePassed);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 stakeAmountBob = 1e23;
        FLASH_Token.approve(address(timeRift), stakeAmountBob);
        timeRift.stake(stakeAmountBob);

        vm.stopPrank();
        vm.startPrank(alice);

        timeRift.exchangeToPSM();

        (
            uint256 user_lastStakeTime,
            uint256 user_lastCollectTime,
            uint256 user_stakedTokens,
            uint256 user_energyBolts,
            uint256 user_exchangeBalance
        ) = timeRift.stakes(alice);

        assertEq(timeRift.stakedTokensTotal(), stakeAmountBob);
        assertEq(timeRift.PSM_distributed(), 0);
        assertEq(timeRift.exchangeBalanceTotal(), stakeAmountBob);
        assertEq(
            timeRift.getAvailablePSM(),
            PSM_AMOUNT_RIFT - stakeAmountAlice - stakeAmountBob
        );

        assertEq(user_lastStakeTime, 0);
        assertEq(user_lastCollectTime, 0);
        assertEq(user_stakedTokens, 0);
        assertEq(user_energyBolts, 0);
        assertEq(user_exchangeBalance, 0);

        assertEq(
            PSM_Token.balanceOf(address(timeRift)),
            PSM_AMOUNT_RIFT - stakeAmountAlice
        );
        assertEq(FLASH_Token.balanceOf(address(timeRift)), stakeAmountBob);

        assertEq(PSM_Token.balanceOf(alice), stakeAmountAlice);
        assertEq(
            FLASH_Token.balanceOf(alice),
            FLASH_AMOUNT_ALICE - stakeAmountAlice
        );

        assertEq(PSM_Token.balanceOf(bob), 0);
        assertEq(FLASH_Token.balanceOf(bob), FLASH_AMOUNT_BOB - stakeAmountBob);

        assertEq(PSM_Token.balanceOf(FLASH_Treasury), 0);
        assertEq(FLASH_Token.balanceOf(FLASH_Treasury), stakeAmountAlice);

        assertEq(PSM_Token.balanceOf(PSM_Treasury), 0);
        assertEq(FLASH_Token.balanceOf(PSM_Treasury), 0);

        vm.stopPrank();
    }

    // ============================================
    function testExchangeToPSM_Failure() public {
        bool success;

        // test case: USER HAS NO EXCHANGE BALANCE
        vm.startPrank(alice);

        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("exchangeToPSM()")
        );

        // Check that the call was not successful because the user has no exchange balance
        assertTrue(!success, "Call was successful, expected revert");

        // test case: EXCHANGE CALLED BEFORE MINIMUM STAKE DURATION
        uint256 stakeAmount = 1e22;
        FLASH_Token.approve(address(timeRift), stakeAmount);
        timeRift.stake(stakeAmount);

        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("exchangeToPSM()")
        );

        // Check that the call was not successful because the minimum stake duration has not passed
        assertTrue(!success, "Call was successful, expected revert");

        vm.stopPrank();
    }

    // ================================================
    // Test addToWhitelist success and failure cases
    function testAddToWhitelist_Success() public {
        vm.prank(owner);
        timeRift.addToWhitelist(PSM_Treasury);
        assertTrue(
            timeRift.whitelist(PSM_Treasury),
            "PSM_Treasury was not added to the whitelist"
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
        assertTrue(!success, "Tx went through but should not");

        // Check that Bob is still not whitelisted after the function call
        assertTrue(!timeRift.whitelist(bob), "Bob was added to the whitelist");

        vm.stopPrank();
    }

    // ================================================
    // Test removeFromWhitelist success and failure cases
    function testRemoveFromWhitelist_Success() public {
        testAddToWhitelist_Success();

        vm.startPrank(owner);

        // Check that PSM_Treasury is whitelisted before the function call
        assertTrue(timeRift.whitelist(PSM_Treasury), "Address not whitelisted");

        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "removeFromWhitelist(address)",
                PSM_Treasury
            )
        );

        // Check that the call was successful
        assertTrue(success, "Reverted the removal / caller not owner");

        assertFalse(
            timeRift.whitelist(PSM_Treasury),
            "PSM_Treasury was not removed from the whitelist"
        );

        vm.stopPrank();
    }

    // // ============================================
    function testRemoveFromWhitelist_Failure() public {
        testAddToWhitelist_Success();

        vm.startPrank(alice);

        // Check that PSM_Treasury is whitelisted before the function call
        assertTrue(timeRift.whitelist(PSM_Treasury), "Address not whitelisted");

        // Call the function using low-level call
        (bool success, ) = address(timeRift).call(
            abi.encodeWithSignature(
                "removeFromWhitelist(address)",
                PSM_Treasury
            )
        );

        // Check that the call was not successful
        assertTrue(!success, "Reverted because non-owner");

        // Check that PSM_Treasury is still on the whitelisted
        assertTrue(
            timeRift.whitelist(PSM_Treasury),
            "PSM_Treasury was removed from the whitelist"
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
        // Call the function using low-level call
        (success, ) = address(timeRift).call(
            abi.encodeWithSignature("rescueToken(address)", PSM_Token)
        );

        // Check that the call was not successful
        assertTrue(!success, "Token transfer was executed");
        assertEq(PSM_Token.balanceOf(address(timeRift)), PSM_AMOUNT_RIFT);
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
}
