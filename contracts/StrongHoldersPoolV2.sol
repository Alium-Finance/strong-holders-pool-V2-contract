/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StrongHoldersPoolV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant MAX_POOL_USERS = 10;
    uint8 public constant MAX_POOLS = 3;
    uint8 public constant UNLOCKS = 10;
    uint256 public immutable DISTRIBUTION_END; // 18 month's after first unlock

    struct GeneralPoolInfo {
        uint256 poolId;
        uint256 initialBalance;
        uint256 balance;
        uint256[MAX_POOL_USERS] rewards; // reward
        address[MAX_POOL_USERS] accounts;
    }

    struct Pool {
        uint8 lastWithdrawPosition;
        mapping (address => bool) rewardAccepted; // set if user accept reward from pool yet
    }

    // pool stored info by pool id
    mapping (uint8 => Pool[UNLOCKS]) public pools;
    mapping (uint8 => GeneralPoolInfo) public generalPoolInfo;

    IERC20 public token;
    uint256[UNLOCKS] public unlocksDate;

    bool private _initialized;
    uint8 private _poolsAmount;

    event Initialized();
    event PoolCreated(uint256 poolId);
    event Withdrawn(uint256 indexed poolId, uint256 position, address account, uint256 amount);

    constructor(
        IERC20 _token,
        uint256[UNLOCKS] memory _unlocksDate
    ) {
        token = _token;
        unlocksDate = _unlocksDate;

        // set end of the normal distribution, 18 months after start
        DISTRIBUTION_END = _unlocksDate[0] + 18 * 31 days;
    }

    // @dev Initialize contract
    function initialize() external onlyOwner {
        require(!_initialized, "SHP: already initialized");

        // excluding TGE balance
        GeneralPoolInfo storage pool1 = generalPoolInfo[0];
        GeneralPoolInfo storage pool2 = generalPoolInfo[1];
        GeneralPoolInfo storage pool3 = generalPoolInfo[2];

        pool1.poolId = 0;
        pool1.initialBalance = 5_000_000e18 - 50_000e18;
        pool1.balance = pool1.initialBalance;

        pool2.poolId = 1;
        pool2.initialBalance = 8_000_000e18 - 80_000e18;
        pool2.balance = pool2.initialBalance;

        pool3.poolId = 2;
        pool3.initialBalance = 12_000_000e18 - 120_000e18;
        pool3.balance = pool3.initialBalance;

        require(
            token.balanceOf(address(this)) >=
            pool1.balance +
            pool2.balance +
            pool3.balance,
            "Not enough balance for activate"
        );
        require(_poolsAmount == MAX_POOLS, "Pools not set");

        _initialized = true;

        emit Initialized();
    }

    function setPool(
        uint256[MAX_POOL_USERS] calldata _rewards,
        address[MAX_POOL_USERS] calldata _accounts
    )
        external
        onlyOwner
    {
        uint8 _poolId = _poolsAmount;

        require(_poolId < MAX_POOLS, "SHP: can't create this pool");

        GeneralPoolInfo storage pool = generalPoolInfo[_poolId];
        pool.rewards = _rewards;
        pool.accounts = _accounts;

        _poolsAmount++;

        emit PoolCreated(_poolId);
    }

    function nextClaim()
        external
        view
        returns (uint256 timestamp)
    {
        for (uint i; i < UNLOCKS; i++) {
            if (block.timestamp < unlocksDate[i]) {
                timestamp = unlocksDate[i];
                return timestamp;
            }
        }
    }

    function getAccounts(uint8 _poolId) external view returns (address[MAX_POOL_USERS] memory accounts) {
        GeneralPoolInfo memory pool = generalPoolInfo[_poolId];
        accounts = pool.accounts;
    }

    // @dev Returns reward per position by pool id
    function getReward(uint8 _poolId, uint8 _position) external view returns (uint256 reward) {
        reward = generalPoolInfo[_poolId].rewards[_position];
    }

    function countReward(uint8 _poolId)
        external
        view
        returns (uint256 reward)
    {
        require(_poolId < MAX_POOLS, "SHP: pool not exist");

        GeneralPoolInfo memory generalPool = generalPoolInfo[_poolId];
        Pool storage pool;

        if (block.timestamp >= DISTRIBUTION_END) {
            reward = generalPool.balance / MAX_POOL_USERS;
        } else {
            for (uint8 i; i < UNLOCKS; i++) {
                pool = pools[_poolId][i];
                if (block.timestamp >= unlocksDate[i] && !pool.rewardAccepted[msg.sender]) {
                    uint8 lastWithdrawPosition = pool.lastWithdrawPosition;
                    reward += generalPool.rewards[lastWithdrawPosition];
                }
            }
        }
    }

    // @dev Leave from pool
    function leave(uint8 _poolId)
        external
        checkAccess(_poolId)
        isActive
        nonReentrant
    {
        require(_poolId < MAX_POOLS, "SHP: pool not exist");

        GeneralPoolInfo storage generalPool = generalPoolInfo[_poolId];
        Pool storage pool;

        uint256 reward;
        if (block.timestamp >= DISTRIBUTION_END) {
            require(generalPool.balance >= uint256(MAX_POOL_USERS), "Pool closed");

            for (uint8 i; i < MAX_POOL_USERS; i++) {
                if (i == MAX_POOL_USERS - 1) {
                    reward = generalPool.balance;
                } else {
                    reward = generalPool.balance/ MAX_POOL_USERS;
                }

                generalPool.balance -= reward;
                if (reward != 0) {
                    emit Withdrawn(
                        _poolId,
                        0, // position
                        generalPool.accounts[i],
                        reward
                    );
                    _withdraw(generalPool.accounts[i], reward);
                }
            }
        } else {
            for (uint8 i; i < UNLOCKS; i++) {
                pool = pools[_poolId][i];
                if (block.timestamp >= unlocksDate[i] && !pool.rewardAccepted[msg.sender]) {
                    pool.rewardAccepted[msg.sender] = true;
                    uint8 lastWithdrawPosition = pool.lastWithdrawPosition;
                    reward += generalPool.rewards[lastWithdrawPosition];
                    pool.lastWithdrawPosition++;
                    emit Withdrawn(
                        _poolId,
                        lastWithdrawPosition,
                        msg.sender,
                        generalPool.rewards[lastWithdrawPosition]
                    );
                }
            }

            generalPool.balance -= reward;
            _withdraw(msg.sender, reward);
        }
    }

    // +
    function _withdraw(address _account, uint256 _balance) internal {
        require(_balance != 0, "Nothing withdraw");

        IERC20(token).safeTransfer(_account, _balance);
    }

    modifier checkAccess(uint8 _poolId) {
        GeneralPoolInfo memory pool = generalPoolInfo[_poolId];

        bool accessGranted;
        for (uint8 i; i < MAX_POOL_USERS; i++) {
            if (msg.sender == pool.accounts[i]) {
                accessGranted = true;
            }
        }

        require(accessGranted, "Account not found");

        _;
    }

    // +
    modifier isActive() {
        require(
            _initialized && block.timestamp >= unlocksDate[0],
            "SHP: distribution impossible"
        );
        _;
    }
}