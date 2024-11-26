// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

abstract contract Upgradeable {
    event ContractUpgraded(address indexed newImplementation);
    event UpgradeAdminChanged(address indexed newUpgradeAdmin);
    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
    
    modifier onlyUpgradeAdmin() {
        require(msg.sender == ERC1967Utils.getAdmin(), "NOT_AUTHORIZED TO UPGRADE");
        _;
    }
    
    function _initializeUpgradeAdmin(address newUpgradeAdmin) internal {
        ERC1967Utils.changeAdmin(newUpgradeAdmin);
        emit UpgradeAdminChanged(newUpgradeAdmin);
    }
}
