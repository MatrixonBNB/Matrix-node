// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "./Upgradeable.sol";

pragma solidity 0.8.24;

contract ERC1967Proxy is Proxy, Upgradeable {
    constructor(address implementation, bytes memory _data) payable {
        ERC1967Utils.upgradeToAndCall(implementation, _data);
    }
    
    function _implementation() internal view virtual override returns (address) {
        return ERC1967Utils.getImplementation();
    }
    
    function __getImplementation__() external view returns (address) {
        return _implementation();
    }
    
    function setUpgradeAdmin(address newUpgradeAdmin) external onlyUpgradeAdmin {
        ERC1967Utils.changeAdmin(newUpgradeAdmin);
        emit UpgradeAdminChanged(newUpgradeAdmin);
    }
    
    function upgradeToAndCall(address newImplementation, bytes calldata _data) external onlyUpgradeAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation, _data);
        emit ContractUpgraded(newImplementation);
    }
    
    function upgradeTo(address newImplementation) external onlyUpgradeAdmin {
        ERC1967Utils.upgradeToAndCall(newImplementation, bytes(''));
        emit ContractUpgraded(newImplementation);
    }
    
    function upgradeAdmin() public view returns (address) {
        return ERC1967Utils.getAdmin();
    }
    
    receive() external payable virtual {
        _fallback();
    }
}
