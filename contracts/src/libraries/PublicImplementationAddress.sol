// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

abstract contract PublicImplementationAddress {
    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
