/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISHP {
	function initialize(
		IERC20 token,
		uint256 _initialBalance,
		uint256[10] calldata _unlocksDate,
		uint256[10] calldata _rewards,
		address[10] calldata _accounts
	) external;
}
