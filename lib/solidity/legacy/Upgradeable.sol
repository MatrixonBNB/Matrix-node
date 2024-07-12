// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "solady/src/utils/LibString.sol";
import "../contracts/Console.sol";

abstract contract Upgradeable {
    using LibString for *;
    
    uint256 public immutable __myAddress = uint256(uint160(address(this)));
    
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

    function upgradeAndCall(bytes32 newHash, string calldata newSource, bytes calldata migrationCalldata) external {
        address newImplementation = address(uint160(uint256(newHash)));
        _authorizeUpgrade(newImplementation);
        
        console.log("__myAddress: ".concat(__myAddress.toHexString()));
        console.log("address(this): ".concat(address(this).toHexString()));
        
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
