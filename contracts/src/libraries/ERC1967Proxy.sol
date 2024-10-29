// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

pragma solidity 0.8.24;

contract ERC1967Proxy is Proxy {
    constructor(address implementation, bytes memory _data) payable {
        ERC1967Utils.upgradeToAndCall(implementation, _data);
    }
    
    function _implementation() internal view virtual override returns (address) {
        return ERC1967Utils.getImplementation();
    }
    
    function __getImplementation__() external view returns (address) {
        return _implementation();
    }
    
    receive() external payable virtual {
        _fallback();
    }
}
