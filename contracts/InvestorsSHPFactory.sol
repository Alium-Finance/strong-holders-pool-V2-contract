/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./StrongHoldersPoolV2.sol";
import "./ISHP.sol";

contract InvestorsSHPFactory is Ownable {
    uint8 public constant MAX_UNLOCKS = 10;
    uint8 public constant MAX_POOL_USERS = 10;

    IERC20 public immutable token;
    uint256 public nonce;

    event PoolCreated(uint256 poolId);

    constructor(IERC20 _token) {
        token = _token;
    }

    // @dev Deploy pool contract.
    function deployPool(
        uint256 _initialBalance,
        uint256[MAX_UNLOCKS] calldata _unlocksDate,
        uint256[MAX_UNLOCKS] calldata _rewards,
        address[MAX_POOL_USERS] calldata _accounts
    ) external returns (address pool) {
        bytes memory bytecode = type(StrongHoldersPoolV2).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(nonce));
        nonce++;
        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
            if iszero(extcodesize(pool)) { revert(0, 0) }
        }
        ISHP(pool).initialize(token, _initialBalance, _unlocksDate, _rewards, _accounts);
        emit PoolCreated(nonce-1);
    }

    // @dev Returns pre-computed pool address by `_nonce`.
    function getPool(uint256 _nonce) external view returns (address pool) {
        bytes memory bytecode = type(StrongHoldersPoolV2).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_nonce));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), salt, keccak256(bytecode)
            )
        );
        return address (uint160(uint(hash)));
    }
}
