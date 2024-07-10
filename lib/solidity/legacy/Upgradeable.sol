// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "solady/src/utils/UUPSUpgradeable.sol";

abstract contract Upgradeable is UUPSUpgradeable {
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

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == _upgradeStorage().upgradeAdmin, "NOT_AUTHORIZED");
    }

    function upgradeAndCall(bytes32 newHash, string calldata, bytes calldata migrationCalldata) external {
        address newImplementation = address(uint160(uint256(newHash)));
        upgradeToAndCall(newImplementation, migrationCalldata);
        emit ContractUpgraded(newImplementation);
    }

    function upgrade(bytes32 newHash, string calldata) external {
        address newImplementation = address(uint160(uint256(newHash)));
        
        this.upgradeToAndCall(newImplementation, bytes(''));
        emit ContractUpgraded(newImplementation);
    }
    
    function upgradeAdmin() public view returns (address) {
        return _upgradeStorage().upgradeAdmin;
    }
}
