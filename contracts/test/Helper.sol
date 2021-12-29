/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

contract Helper {
    function getAddress(uint256 _num) public pure returns (address) {
        return address(uint160(_num));
    }
}
