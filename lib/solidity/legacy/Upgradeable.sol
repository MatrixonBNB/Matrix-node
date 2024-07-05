// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "solady/src/utils/UUPSUpgradeable.sol";
import "solady/src/utils/Initializable.sol";

abstract contract Upgradeable is UUPSUpgradeable, Initializable {
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
        require(newUpgradeAdmin != address(0), "New admin address cannot be zero");
        _upgradeStorage().upgradeAdmin = newUpgradeAdmin;
        emit UpgradeAdminChanged(newUpgradeAdmin);
    }
    
    function initUpgradeAdmin(address newUpgradeAdmin) internal onlyInitializing {
        require(_upgradeStorage().upgradeAdmin == address(0), "Upgrade admin already set");
        _upgradeStorage().upgradeAdmin = newUpgradeAdmin;
        emit UpgradeAdminChanged(newUpgradeAdmin);
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == _upgradeStorage().upgradeAdmin, "NOT_AUTHORIZED");
    }

    function upgradeAndCall(address newImplementation, bytes calldata migrationCalldata) external {
        upgradeToAndCall(newImplementation, migrationCalldata);
        emit ContractUpgraded(newImplementation);
    }

    function upgrade(address newImplementation) external {
        this.upgradeToAndCall(newImplementation, bytes(''));
        emit ContractUpgraded(newImplementation);
    }
}
