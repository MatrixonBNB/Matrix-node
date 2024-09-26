// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "./LegacyAddressable.sol";

pragma solidity 0.8.24;

contract ERC1967Proxy is Proxy, LegacyAddressable {
    constructor(address implementation, bytes memory _data) payable {
        ERC1967Utils.upgradeToAndCall(implementation, _data);
        _initializeLegacyAddress();
    }
    
    function _implementation() internal view virtual override returns (address) {
        return ERC1967Utils.getImplementation();
    }
    
    receive() external payable virtual {
        _fallback();
    }
}
