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
error InsufficientEnergyBolts();
error InsufficientExchangeBalance();
error MinimumStakeTime();
error NotWhitelisted();

/// @title TimeRift
/// @dev This contract allows users to stake, unstake, exchange and distribute tokens.
/// @author Possum Labs

contract TimeRift is ReentrancyGuard, Ownable {
    /// @notice The constructor function initializes the contract.
    /// @dev The constructor function is only called once when the contract is deployed.
    /// @param _MINIMUM_STAKE_DURATION The minimum stake duration in seconds.
    /// @param _ENERGY_BOLTS_ACCRUAL_RATE The APR rate at which Energy Bolts accrue based on the exchange balance.
    /// @param _WITHDRAW_PENALTY_PERCENT The percentage penalty for withdrawing staked tokens.
    constructor(
        uint256 _MINIMUM_STAKE_DURATION,
        uint256 _ENERGY_BOLTS_ACCRUAL_RATE,
        uint256 _WITHDRAW_PENALTY_PERCENT
    ) Ownable() {
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

        MINIMUM_STAKE_DURATION = _MINIMUM_STAKE_DURATION;
        ENERGY_BOLTS_ACCRUAL_RATE = _ENERGY_BOLTS_ACCRUAL_RATE;
        WITHDRAW_PENALTY_PERCENT = _WITHDRAW_PENALTY_PERCENT;
        whitelist[PSM_TREASURY] = true;

        emit WhitelistAdded(PSM_TREASURY);
    }

    // ============================================
    // ==            GLOBAL VARIABLES            ==
    // ============================================
    using SafeERC20 for IERC20;

    address public constant FLASH_ADDRESS =
        0xc628534100180582E43271448098cb2c185795BD;
    address public constant PSM_ADDRESS =
        0x17A8541B82BF67e10B0874284b4Ae66858cb1fd5;
    address public constant FLASH_TREASURY =
        0xEeB3f4E245aC01792ECd549d03b91541BC800b31;
    address public constant PSM_TREASURY =
        0xAb845D09933f52af5642FC87Dd8FBbf553fd7B33;

    uint256 public immutable MINIMUM_STAKE_DURATION;
    uint256 public immutable ENERGY_BOLTS_ACCRUAL_RATE;
    uint256 public immutable WITHDRAW_PENALTY_PERCENT;

    uint256 private constant SECONDS_PER_YEAR = 31536000;

    uint256 public stakedTokensTotal;
    uint256 public PSM_distributed;
    uint256 public exchangeBalanceTotal;

    struct Stake {
        uint256 lastStakeTime;
        uint256 lastCollectTime;
        uint256 stakedTokens;
        uint256 energyBolts;
        uint256 exchangeBalance;
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

    event Exchanged(address indexed user, uint256 amount);
    event EnergyBoltsCollected(
        address indexed user,
        uint256 amount,
        uint256 balance
    );
    event EnergyBoltsDistributed(
        address indexed user,
        uint256 amountToUser,
        address indexed destination,
        uint256 amountToDestination
    );

    // ============================================
    // ==           STAKING & UNSTAKING          ==
    // ============================================
    /// @notice Stakes tokens for the user.
    /// @dev The function collects energy bolts for the user and updates their stake.
    /// @param _amount The amount of tokens to stake.
    function stake(uint256 _amount) external nonReentrant {
        /// @dev Check if the inputs are valid and if enough PSM is available to serve the stake.
        if (_amount == 0) {
            revert InvalidInput();
        }

        uint256 available_PSM = getAvailablePSM();
        if (_amount > available_PSM) {
            revert InsufficientRewards();
        }

        /// @dev Collect the user's energy bolts.
        _collectEnergyBolts(msg.sender);

        /// @dev Update the user's stake information.
        Stake storage userStake = stakes[msg.sender];
        userStake.lastStakeTime = block.timestamp;
        userStake.stakedTokens += _amount;
        userStake.exchangeBalance += _amount;

        /// @dev Update the global stake information.
        stakedTokensTotal += _amount;
        exchangeBalanceTotal += _amount;

        /// @dev Transfer the staked token fro the user to the contract.
        IERC20(FLASH_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        /// @dev Emit the event that tokens have been staked successfully.
        emit TokenStaked(msg.sender, _amount);
    }

    /// @notice Withdraws staked tokens for the user.
    /// @dev The function calculates the penalty for withdrawing staked tokens and updates the user's stake.
    function withdrawAndExit() external nonReentrant {
        /// @dev Read the user's stake into storage and check if amount is larger than zero.
        Stake storage userStake = stakes[msg.sender];
        uint256 userStakedTokens = userStake.stakedTokens;
        if (userStakedTokens == 0) {
            revert InvalidOutput();
        }

        /// @dev Calculate the withdrawal penalty and amounts of tokens to be sent out by the contract.
        uint256 penalty = (WITHDRAW_PENALTY_PERCENT * userStakedTokens) / 100;
        uint256 withdrawAmount = userStakedTokens - penalty;
        uint256 userExchangeBalance = userStake.exchangeBalance;

        /// @dev Update the global and user specific staking information.
        stakedTokensTotal -= userStakedTokens;
        exchangeBalanceTotal -= userExchangeBalance;
        delete stakes[msg.sender];

        /// @dev Transfer the staked token to the user and the penalty to the external destination
        IERC20(FLASH_ADDRESS).safeTransfer(msg.sender, withdrawAmount);
        IERC20(FLASH_ADDRESS).safeTransfer(FLASH_TREASURY, penalty);

        /// @dev Transfer the accumulated exchange balance in PSM to the Possum Treasury.
        IERC20(PSM_ADDRESS).safeTransfer(PSM_TREASURY, userExchangeBalance);

        /// @dev Emit the event that a user has withdrawn their stake.
        emit TokenWithdrawn(msg.sender, userStakedTokens);
    }

    // ============================================
    // ==       DISTRIBUTION & EXCHANGE        ==
    // ============================================
    /// @notice Collects energy bolts for the user.
    /// @dev The function calculates the energy bolts collected by the user and updates their stake.
    /// @param _user The address of the user.
    function _collectEnergyBolts(address _user) private {
        Stake storage userStake = stakes[_user];

        uint256 time = block.timestamp;
        uint256 energyBoltsCollected = ((time - userStake.lastCollectTime) *
            userStake.exchangeBalance *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        userStake.lastCollectTime = time;
        userStake.energyBolts += energyBoltsCollected;

        emit EnergyBoltsCollected(
            _user,
            energyBoltsCollected,
            userStake.energyBolts
        );
    }

    /// @notice Distributes PSM tokens (energy bolts) to a destination.
    /// @dev The function calculates the energy bolts to distribute and updates the user's stake.
    /// @param _destination The address of the destination.
    /// @param _amount The amount of energy bolts to distribute.
    function distributeEnergyBolts(
        address _destination,
        uint256 _amount
    ) external nonReentrant {
        /// @dev Check if the inputs are valid and if the destination is whitelisted.
        if (_amount == 0) {
            revert InvalidInput();
        }
        if (!whitelist[_destination]) {
            revert NotWhitelisted();
        }

        /// @dev Check if there is still PSM available in the contract to be distributed.
        uint256 available_PSM = getAvailablePSM();

        if (available_PSM == 0) {
            revert InsufficientRewards();
        }

        /// @dev Collect the user's energy bolts.
        _collectEnergyBolts(msg.sender);

        /// @dev Check if the user has sufficient energy bolts
        Stake storage userStake = stakes[msg.sender];
        if (userStake.energyBolts < _amount) {
            revert InsufficientEnergyBolts();
        }

        /// @dev Calculate the correct amount of exchange balance increase and distributed tokens.
        /// @dev The increase of the user's exchange balance has priority over distributing tokens to the destination.
        if (available_PSM < _amount * 2) {
            if (available_PSM <= _amount) {
                userStake.exchangeBalance += available_PSM;
                exchangeBalanceTotal += available_PSM;
                userStake.energyBolts -= available_PSM;

                emit EnergyBoltsDistributed(
                    msg.sender,
                    available_PSM,
                    _destination,
                    0
                );
            } else {
                uint256 rest = available_PSM - _amount;

                userStake.exchangeBalance += _amount;
                exchangeBalanceTotal += _amount;
                userStake.energyBolts -= _amount;
                PSM_distributed += rest;
                IERC20(PSM_ADDRESS).safeTransfer(_destination, rest);

                emit EnergyBoltsDistributed(
                    msg.sender,
                    _amount,
                    _destination,
                    rest
                );
            }
        } else {
            userStake.exchangeBalance += _amount;
            exchangeBalanceTotal += _amount;
            userStake.energyBolts -= _amount;
            PSM_distributed += _amount;
            IERC20(PSM_ADDRESS).safeTransfer(_destination, _amount);

            emit EnergyBoltsDistributed(
                msg.sender,
                _amount,
                _destination,
                _amount
            );
        }
    }

    /// @notice Exchange staked tokens to PSM tokens.
    /// @dev The function sends the user's staked tokens to external treasury and PSM to the user's wallet.
    function exchangeToPSM() external nonReentrant {
        /// @dev Load the user's data into storage and check if the exchange conditions are met.
        Stake storage userStake = stakes[msg.sender];
        uint256 exchangeBalance = userStake.exchangeBalance;
        uint256 stakedTokens = userStake.stakedTokens;

        if (exchangeBalance == 0) {
            revert InsufficientExchangeBalance();
        }
        if (
            userStake.lastStakeTime + MINIMUM_STAKE_DURATION > block.timestamp
        ) {
            revert MinimumStakeTime();
        }

        /// @dev Update global and user's stake information.
        exchangeBalanceTotal -= exchangeBalance;
        stakedTokensTotal -= stakedTokens;
        delete stakes[msg.sender];

        /// @dev Transfer the staked token to the external destination and PSM to the user.
        IERC20(FLASH_ADDRESS).safeTransfer(FLASH_TREASURY, stakedTokens);
        IERC20(PSM_ADDRESS).safeTransfer(msg.sender, exchangeBalance);

        /// @dev Emit the event that the exchange was successful.
        emit Exchanged(msg.sender, exchangeBalance);
    }

    // ============================================
    // ==            OWNER FUNCTIONS             ==
    // ============================================
    /// @notice Adds an address to the whitelist.
    /// @dev The function updates the whitelist mapping.
    /// @param _destination The address to add to the whitelist.
    function addToWhitelist(address _destination) external onlyOwner {
        if (whitelist[_destination]) {
            revert InvalidInput();
        }
        if (_destination == address(0)) {
            revert InvalidInput();
        }

        whitelist[_destination] = true;

        emit WhitelistAdded(_destination);
    }

    /// @notice Removes an address from the whitelist.
    /// @dev The function updates the whitelist mapping.
    /// @param _destination The address to remove from the whitelist.
    function removeFromWhitelist(address _destination) external onlyOwner {
        if (!whitelist[_destination]) {
            revert InvalidInput();
        }

        whitelist[_destination] = false;

        emit WhitelistRemoved(_destination);
    }

    /// @notice Withdraws an ERC20 token that is not the staked token nor the reward token.
    /// @dev The function transfers a token from the contract to the owner.
    /// @param _token The address of the token to rescue.
    function rescueToken(address _token) external onlyOwner {
        if (
            _token == FLASH_ADDRESS ||
            _token == PSM_ADDRESS ||
            _token == address(0)
        ) {
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
    /// @notice Gets the available PSM balance of the contract.
    /// @dev The function calculates the available PSM balance for staking or distributing.
    /// @return availableBalance The available PSM balance.
    function getAvailablePSM() public view returns (uint256 availableBalance) {
        availableBalance =
            IERC20(PSM_ADDRESS).balanceOf(address(this)) -
            exchangeBalanceTotal;
    }

    /// @notice Gets the energy bolts of a user at the current moment.
    /// @dev The function calculates the energy bolts of a user.
    /// @param _user The address of the user.
    /// @return userEnergyBolts The energy bolts of the user.
    function getUserEnergyBolts(
        address _user
    ) external view returns (uint256 userEnergyBolts) {
        Stake storage userStake = stakes[_user];

        uint256 time = block.timestamp;
        uint256 energyBoltsCollected = ((time - userStake.lastCollectTime) *
            userStake.exchangeBalance *
            ENERGY_BOLTS_ACCRUAL_RATE) / (100 * SECONDS_PER_YEAR);

        userEnergyBolts = userStake.energyBolts + energyBoltsCollected;
    }

    /// @notice Gets the balance of a token in the contract.
    /// @dev The function retrieves the balance of a token.
    /// @param _token The address of the token.
    /// @return balance The balance of the token.
    function getBalanceOfToken(
        address _token
    ) external view returns (uint256 balance) {
        balance = IERC20(_token).balanceOf(address(this));
    }
}
