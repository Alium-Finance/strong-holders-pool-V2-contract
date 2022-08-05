/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StrongHoldersPoolV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant MAX_POOL_USERS = 10;
    uint8 public constant MAX_UNLOCKS = 10;

    struct GeneralPoolInfo {
        IERC20 token;
        uint256 initialBalance;
        uint256[MAX_UNLOCKS] rewards;
        address[MAX_POOL_USERS] accounts;
        uint256[MAX_UNLOCKS] unlocks;
    }

    // global packed pool info
    GeneralPoolInfo public generalPoolInfo;

    struct Pool {
        uint256 balance;
        uint8 lastWithdrawPosition;
        mapping(address => bool) rewardAccepted; // set if user accept reward from pool yet
    }

    // pool stored info by pool id
    Pool[MAX_UNLOCKS] public pools;

    event Initialized();
    event Withdrawn(
        uint256 indexed poolId,
        uint256 position,
        address account,
        uint256 amount
    );

    // @dev Initializer.
    function initialize(
        IERC20 _token,
        uint256 _initialBalance,
        uint256[MAX_UNLOCKS] calldata _unlocksDate,
        uint256[MAX_UNLOCKS] calldata _rewards,
        address[MAX_POOL_USERS] calldata _accounts
    ) external onlyOwner {
        generalPoolInfo = GeneralPoolInfo({
            token: _token,
            initialBalance: _initialBalance,
            rewards: _rewards,
            accounts: _accounts,
            unlocks: _unlocksDate
        });

        for (uint8 i; i < MAX_UNLOCKS; i++) {
            pools[i].balance = _initialBalance;
        }

        emit Initialized();
    }

    // @dev Leave from pool
    function leave(uint8 _poolId)
        external
        checkAccess()
        nonReentrant
    {
        require(isPoolUnlocked(_poolId), "SHP: pool is locked");

        Pool storage pool = pools[_poolId];

        require(MAX_POOL_USERS - pool.lastWithdrawPosition != 0, "SHP: pool is closed");

        GeneralPoolInfo memory generalPool = generalPoolInfo;

        uint256 reward;
        if (block.timestamp >= distributionEnd(_poolId)) {
            if (MAX_POOL_USERS - pool.lastWithdrawPosition != 0) {
                reward = pools[_poolId].balance / (MAX_POOL_USERS - pool.lastWithdrawPosition);
            }
        } else {
            require(!pool.rewardAccepted[msg.sender], "SHP: no reward!");

            reward = generalPool.rewards[pool.lastWithdrawPosition];
        }

        pools[_poolId].balance -= reward;

        uint256 withdrawPosition = pool.lastWithdrawPosition;
        pool.lastWithdrawPosition++;

        _withdraw(msg.sender, reward);
        emit Withdrawn(_poolId, withdrawPosition, msg.sender, reward);
    }

    function getAccounts()
        external
        view
        returns (address[MAX_POOL_USERS] memory accounts)
    {
        accounts = generalPoolInfo.accounts;
    }

    // @dev Returns rewards.
    function getRewards()
        external
        view
        returns (uint256[MAX_POOL_USERS] memory rewards)
    {
        rewards = generalPoolInfo.rewards;
    }

    // @dev Returns rewards.
    function getUnlocks()
        external
        view
        returns (uint256[MAX_UNLOCKS] memory unlocks)
    {
        unlocks = generalPoolInfo.unlocks;
    }

    function calcExitReward(uint8 _poolId) public view returns (uint256 reward) {
        require(_poolId < MAX_UNLOCKS, "SHP: pool not exist");

        GeneralPoolInfo memory generalPool = generalPoolInfo;
        Pool storage pool = pools[_poolId];

        if (block.timestamp >= distributionEnd(_poolId)) {
            if (MAX_POOL_USERS - pool.lastWithdrawPosition != 0) {
                reward = pools[_poolId].balance / (MAX_POOL_USERS - pool.lastWithdrawPosition);
            }
            return reward;
        }

        if (
            block.timestamp >= generalPoolInfo.unlocks[_poolId] &&
            !pool.rewardAccepted[msg.sender]
        ) {
            reward = generalPool.rewards[pool.lastWithdrawPosition];
        }
    }

    // @dev Return timestamp of the end of SHP distribution.
    // After that time will be honest distribution.
    function distributionEnd(uint _poolId) public view returns (uint256 timestamp) {
        require(_poolId < MAX_UNLOCKS, "SHP: pool not exist");

        timestamp = generalPoolInfo.unlocks[_poolId] + 15 * 31 days;
    }

    // @dev Check status of the pool.
    function isPoolUnlocked(uint256 _poolId) public view returns (bool result) {
        require(_poolId < MAX_UNLOCKS, "SHP: pool not exist");

        result = block.timestamp >= generalPoolInfo.unlocks[_poolId];
    }

    function _withdraw(address _account, uint256 _balance) internal {
        require(_balance != 0, "Nothing withdraw");

        IERC20(generalPoolInfo.token).safeTransfer(_account, _balance);
    }

    modifier checkAccess() {
        GeneralPoolInfo memory pool = generalPoolInfo;
        bool accessGranted;
        for (uint8 i; i < MAX_POOL_USERS; i++) {
            if (msg.sender == pool.accounts[i]) {
                accessGranted = true;
            }
        }
        require(accessGranted, "Account not found");
        _;
    }
}
