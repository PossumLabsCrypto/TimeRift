// SPDX-License-Identifier: GPL-2.0-only
pragma solidity =0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ============================================
// ==          CUSTOM ERROR MESSAGES         ==
// ============================================
error InvalidInput();
error InvalidOutput();
error InsufficientRewards();
error MinimumStakeTime();

contract TimeRift is ReentrancyGuard, Ownable {
    constructor(
        address _FLASH_ADDRESS,
        address _PSM_ADDRESS,
        address _FLASH_TREASURY,
        address _PSM_TREASURY,
        uint256 _MINIMUM_STAKE_DURATION,
        uint256 _ENERGY_BOLTS_ACCRUAL_RATE,
        uint256 _WITHDRAW_PENALTY_PERCENT
    ) Ownable() {
        if (_FLASH_ADDRESS == address(0)) {
            revert InvalidInput();
        }
        if (_PSM_ADDRESS == address(0)) {
            revert InvalidInput();
        }
        if (_FLASH_TREASURY == address(0)) {
            revert InvalidInput();
        }
        if (_PSM_TREASURY == address(0)) {
            revert InvalidInput();
        }
        if (
            _MINIMUM_STAKE_DURATION < 2592000 ||
            _MINIMUM_STAKE_DURATION > 31536000
        ) {
            revert InvalidInput();
        }
        if (
            _ENERGY_BOLTS_ACCRUAL_RATE < 10 || _ENERGY_BOLTS_ACCRUAL_RATE > 1000
        ) {
            revert InvalidInput();
        }
        if (_WITHDRAW_PENALTY_PERCENT > 50) {
            revert InvalidInput();
        }

        FLASH_ADDRESS = _FLASH_ADDRESS;
        PSM_ADDRESS = _PSM_ADDRESS;
        FLASH_TREASURY = _FLASH_TREASURY;
        PSM_TREASURY = _PSM_TREASURY;
        MINIMUM_STAKE_DURATION = _MINIMUM_STAKE_DURATION;
        ENERGY_BOLTS_ACCRUAL_RATE = _ENERGY_BOLTS_ACCRUAL_RATE;
        WITHDRAW_PENALTY_PERCENT = _WITHDRAW_PENALTY_PERCENT;
    }

    // ============================================
    // ==            GLOBAL VARIABLES            ==
    // ============================================
    using SafeERC20 for IERC20;

    address public immutable FLASH_ADDRESS;
    address public immutable PSM_ADDRESS;
    address public immutable FLASH_TREASURY;
    address public immutable PSM_TREASURY;

    uint256 public immutable MINIMUM_STAKE_DURATION;
    uint256 public immutable ENERGY_BOLTS_ACCRUAL_RATE;
    uint256 public immutable WITHDRAW_PENALTY_PERCENT;

    uint256 private constant SECONDS_PER_YEAR = 31536000;

    uint256 public stakedTokensTotal;
    uint256 public PSM_distributed;
    uint256 public conversionBalanceTotal;
    uint256 public available_PSM;

    struct Stake {
        uint256 lastStakeTime;
        uint256 lastCollectTime;
        uint256 stakedTokens;
        uint256 energyBolts;
        uint256 conversionBalance;
    }

    mapping(address => Stake) public stakes;
    mapping(address => bool) public whitelist;

    // ============================================
    // ==                 EVENTS                 ==
    // ============================================
    event WhitelistAdded(address destination);
    event WhitelistRemoved(address destination);

    event TokenStaked(address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed user, uint256 amount);

    event Converted(address indexed user, uint256 amount);
    event EnergyBoltsCollected(
        address indexed user,
        uint256 amount,
        uint256 balance
    );
    event EnergyBoltsDistributed(
        address indexed user,
        address indexed destination,
        uint256 amount
    );

    // ============================================
    // ==           STAKING & UNSTAKING          ==
    // ============================================
    function stake(uint256 _amount) external nonReentrant {
        if (_amount == 0) {
            revert InvalidInput();
        }

        available_PSM =
            IERC20(PSM_ADDRESS).balanceOf(address(this)) -
            conversionBalanceTotal;
        if (available_PSM == 0) {
            revert InsufficientRewards();
        }
        if (_amount > available_PSM) {
            _amount = available_PSM;
        }

        _collectEnergyBolts(msg.sender);

        Stake storage userStake = stakes[msg.sender];
        userStake.lastStakeTime = block.timestamp;
        userStake.stakedTokens += _amount;
        userStake.conversionBalance += _amount;

        stakedTokensTotal += _amount;

        IERC20(FLASH_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        emit TokenStaked(msg.sender, _amount);
    }

    function withdrawAndExit() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        uint256 userStakedTokens = userStake.stakedTokens;
        if (userStakedTokens == 0) {
            revert InvalidOutput();
        }

        uint256 penalty = (WITHDRAW_PENALTY_PERCENT * userStakedTokens) / 100;
        uint256 withdrawAmount = userStakedTokens - penalty;
        uint256 userConversionBalance = userStake.conversionBalance;

        stakedTokensTotal -= userStakedTokens;
        delete stakes[msg.sender];

        IERC20(FLASH_ADDRESS).safeTransfer(msg.sender, withdrawAmount);
        IERC20(FLASH_ADDRESS).safeTransfer(FLASH_TREASURY, penalty);

        IERC20(PSM_ADDRESS).safeTransfer(PSM_TREASURY, userConversionBalance);

        emit TokenWithdrawn(msg.sender, userStakedTokens);
    }

    // ============================================
    // ==       DISTRIBUTION & CONVERSION        ==
    // ============================================
    function _collectEnergyBolts(address _user) private {
        Stake storage userStake = stakes[_user];

        uint256 time = block.timestamp;
        uint256 energyBoltsCollected = ((time - userStake.lastCollectTime) *
            userStake.stakedTokens *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        userStake.lastCollectTime = time;
        userStake.energyBolts += energyBoltsCollected;

        emit EnergyBoltsCollected(
            _user,
            energyBoltsCollected,
            userStake.energyBolts
        );
    }

    function distributeEnergyBolts(
        address _destination,
        uint256 _amount
    ) external nonReentrant {
        if (_amount == 0) {
            revert InvalidInput();
        }
        if (_destination == address(0)) {
            revert InvalidInput();
        }

        available_PSM =
            IERC20(PSM_ADDRESS).balanceOf(address(this)) -
            conversionBalanceTotal;
        if (available_PSM == 0) {
            revert InsufficientRewards();
        }

        _collectEnergyBolts(msg.sender);

        Stake storage userStake = stakes[msg.sender];
        if (userStake.energyBolts < _amount) {
            revert InvalidInput();
        }

        if (available_PSM <= _amount * 2) {
            if (available_PSM <= _amount) {
                _amount = available_PSM;
                userStake.conversionBalance += _amount;
                conversionBalanceTotal += _amount;
            } else {
                uint256 rest = available_PSM - _amount;

                userStake.conversionBalance += _amount;
                conversionBalanceTotal += _amount;
                PSM_distributed += rest;
                IERC20(PSM_ADDRESS).safeTransfer(_destination, rest);
            }
        } else {
            userStake.conversionBalance += _amount;
            conversionBalanceTotal += _amount;
            PSM_distributed += _amount;
            IERC20(PSM_ADDRESS).safeTransfer(_destination, _amount);
        }

        emit EnergyBoltsDistributed(msg.sender, _destination, _amount);
    }

    function convertToPSM() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        uint256 conversionBalance = userStake.conversionBalance;
        uint256 stakedTokens = userStake.stakedTokens;

        if (conversionBalance == 0) {
            revert InvalidInput();
        }
        if (
            userStake.lastStakeTime + MINIMUM_STAKE_DURATION > block.timestamp
        ) {
            revert MinimumStakeTime();
        }

        conversionBalanceTotal -= conversionBalance;
        stakedTokensTotal -= stakedTokens;
        delete stakes[msg.sender];

        IERC20(FLASH_ADDRESS).safeTransfer(FLASH_TREASURY, stakedTokens);
        IERC20(PSM_ADDRESS).safeTransfer(msg.sender, conversionBalance);

        emit Converted(msg.sender, conversionBalance);
    }

    // ============================================
    // ==            OWNER FUNCTIONS             ==
    // ============================================
    function addToWhitelist(address _destination) external onlyOwner {
        whitelist[_destination] = true;

        emit WhitelistAdded(_destination);
    }

    function removeFromWhitelist(address _destination) external onlyOwner {
        whitelist[_destination] = false;

        emit WhitelistRemoved(_destination);
    }

    function rescueToken(address _token) external onlyOwner {
        if (_token == FLASH_ADDRESS || _token == PSM_ADDRESS) {
            revert InvalidInput();
        }

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) {
            revert InvalidOutput();
        }

        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    // ============================================
    // ==                GENERAL                 ==
    // ============================================
    function getAvailablePSM()
        external
        view
        returns (uint256 availableBalance)
    {
        availableBalance =
            IERC20(PSM_ADDRESS).balanceOf(address(this)) -
            conversionBalanceTotal;
    }

    function getUserEnergyBolts(
        address _user
    ) external view returns (uint256 userEnergyBolts) {
        Stake storage userStake = stakes[_user];

        uint256 time = block.timestamp;
        uint256 energyBoltsCollected = ((time - userStake.lastCollectTime) *
            userStake.stakedTokens *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        userEnergyBolts = userStake.energyBolts + energyBoltsCollected;
    }

    function getBalanceOfToken(
        address _token
    ) external view returns (uint256 balance) {
        balance = IERC20(_token).balanceOf(address(this));
    }
}
