pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrongHoldersPoolV2 is Ownable {

    uint256 public constant TOTAL_LOCKED_TOKENS = 25_000_000e18;
    uint16 public constant MAX_POOL_USERS = 10;
    uint8 public constant MAX_POOLS = 3;
    uint16 public constant UNLOCKS = 10;
    uint16 public constant DISTRIBUTION_END = 18; // 18 month's

    struct User {
        address account;
        uint16 withdrawPosition; // [1...10]
    }

    struct Pool {
        uint256 balance;
        uint256[MAX_POOL_USERS] rewards; // reward
        User[MAX_POOL_USERS] accounts;
        // index -> w.position
        mapping(uint256 => uint256) withdrawPosition;
    }

    // reward pool id -> index -> Pool
    mapping (uint8 => Pool) public pools;

    IERC20 public token;
    uint256 public startFrom;
    uint256[UNLOCKS] public unlocksDate;

    bool private _activated;

    constructor(
        IERC20 _token,
        uint256 _activationAt,
        uint256[UNLOCKS] memory _unlocksDate
    ) {
        token = _token;
        startFrom = _activationAt;
        unlocksDate = _unlocksDate;
    }

    function activate() external {
        require(
            token.balanceOf(address(this)) == TOTAL_LOCKED_TOKENS,
            "Not enough balance for activate"
        );

        pools[0].balance = 5_000_000e18;
        pools[1].balance = 8_000_000e18;
        pools[2].balance = 12_000_000e18;

        _activated = true;
    }

    function setPool(
        uint8 _poolId,
        uint16[MAX_POOL_USERS] calldata _rewards,
        address[MAX_POOL_USERS] calldata _accounts
    )
        external
        onlyOwner
    {
        require(_poolId < MAX_POOLS, "SHP: can't create this pool");

        Pool storage pool = pools[_poolId];
        pool.rewards = _rewards;
        uint16 i;
        while (i < 10) {
            pool.accounts[i].account = _accounts[i];
            i++;
        }
    }

    function countReward(address _account, uint8 _poolId)
        external
        view
        returns (uint256 reward)
    {
        return reward;
    }

    // @dev Leave from pool
    function leave(uint8 _poolId) external isActive {
        Pool storage pool = pools[_poolId];

        bool accessGranted;
        for (uint16 i; i < MAX_POOL_USERS; i++) {
            if (msg.sender == pool.accounts[i].account) {
                accessGranted = true;
            }
        }

        require(accessGranted, "Account not found");

        uint256 reward;
        if (block.timestamp > DISTRIBUTION_END * 31 days) {
            // distribute to all
            uint stillInPool = pool.withdrawPosition[_poolId];
            reward = pool.balance / stillInPool;
        } else {
            for (uint16 i; i < UNLOCKS; i++) {
                if (block.timestamp > unlocksDate[i]) {
                    uint lastWithdrawPosition = pool.withdrawPosition[i];
                    pool.withdrawPosition[i]++;
                    reward = pool.rewards[lastWithdrawPosition];
                }
            }
        }
    }

    modifier isActive() {
        require(
            _activated && block.timestamp > startFrom,
            "SHP: distribution impossible"
        );
        _;
    }
}