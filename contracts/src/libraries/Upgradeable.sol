// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

abstract contract Upgradeable {
    struct UpgradeStorage {
        address upgradeAdmin;
    }
    
    function _upgradeStorage() internal pure returns (UpgradeStorage storage cs) {
        bytes32 position = keccak256("UpgradeStorage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
  
    event ContractUpgraded(address indexed newImplementation);
    event UpgradeAdminChanged(address indexed newUpgradeAdmin);

    function setUpgradeAdmin(address newUpgradeAdmin) external {
        require(msg.sender == _upgradeStorage().upgradeAdmin, "NOT_AUTHORIZED");
        _upgradeStorage().upgradeAdmin = newUpgradeAdmin;
        emit UpgradeAdminChanged(newUpgradeAdmin);
    }
    
    function _initializeUpgradeAdmin(address newUpgradeAdmin) internal {
        require(_upgradeStorage().upgradeAdmin == address(0), "Upgrade admin already set");
        _upgradeStorage().upgradeAdmin = newUpgradeAdmin;
        emit UpgradeAdminChanged(newUpgradeAdmin);
    }

    function _authorizeUpgrade(address) internal view {
        require(msg.sender == _upgradeStorage().upgradeAdmin, "NOT_AUTHORIZED TO UPGRADE");
    }
    
    modifier onlyUpgradeAdmin() {
        require(msg.sender == _upgradeStorage().upgradeAdmin, "NOT_AUTHORIZED TO UPGRADE");
        _;
    }
    
    function upgradeToAndCall(address newImplementation, bytes calldata migrationCalldata) external {
        _authorizeUpgrade(newImplementation);
        ERC1967Utils.upgradeToAndCall(newImplementation, migrationCalldata);
        emit ContractUpgraded(newImplementation);
    }
    
    function upgradeTo(address newImplementation) external {
        _authorizeUpgrade(newImplementation);
        ERC1967Utils.upgradeToAndCall(newImplementation, bytes(''));
        emit ContractUpgraded(newImplementation);
    }

    function upgradeAndCall(bytes32 newHash, string calldata newSource, bytes calldata migrationCalldata) external {
        address newImplementation = address(uint160(uint256(newHash)));
        _authorizeUpgrade(newImplementation);
        
        ERC1967Utils.upgradeToAndCall(newImplementation, migrationCalldata);
        emit ContractUpgraded(newImplementation);
    }

    function upgrade(bytes32 newHash, string calldata newSource) external {
        address newImplementation = address(uint160(uint256(newHash)));
        _authorizeUpgrade(newImplementation);
        
        ERC1967Utils.upgradeToAndCall(newImplementation, bytes(''));
        emit ContractUpgraded(newImplementation);
    }
    
    function upgradeAdmin() public view returns (address) {
        return _upgradeStorage().upgradeAdmin;
    }
}
