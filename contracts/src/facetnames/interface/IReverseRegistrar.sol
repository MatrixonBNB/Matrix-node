// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IReverseRegistrar {
    function claim(address claimant) external;
    function node(address addr) external view returns (bytes32);

    function setNameForAddr(address addr, address owner, address resolver, string memory name)
        external
        returns (bytes32);
}
