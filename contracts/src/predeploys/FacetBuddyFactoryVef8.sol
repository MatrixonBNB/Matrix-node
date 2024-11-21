// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./FacetBuddyVe5c.sol";
import "solady/utils/Initializable.sol";
import "src/libraries/ERC1967Proxy.sol";

contract FacetBuddyFactoryVef8 is Initializable {
    event BuddyCreated(address indexed forUser, address buddy);

    struct FacetBuddyFactoryStorage {
        address erc20Bridge;
        mapping(address => address) buddyForUser;
        mapping(address => address) userForBuddy;
    }

    function s() internal pure returns (FacetBuddyFactoryStorage storage ns) {
        bytes32 position = keccak256("FacetBuddyFactory.contract.storage.v1");
        assembly {
            ns.slot := position
        }
    }

    function buddyForUser(address forUser) public view returns (address) {
        return s().buddyForUser[forUser];
    }
    
    function initialize(address erc20Bridge) public initializer {
        require(erc20Bridge != address(0), "Invalid smart contract");
        s().erc20Bridge = erc20Bridge;
    }
    
    function findOrCreateBuddy(address forUser) public returns (address) {
        address existingBuddy = s().buddyForUser[forUser];
        if (existingBuddy != address(0)) {
            return existingBuddy;
        }

        bytes32 salt = keccak256(abi.encodePacked(forUser));
        address implementationAddress = MigrationLib.predeployAddrFromName("FacetBuddyVe5c");
        bytes memory initBytes = abi.encodeCall(FacetBuddyVe5c.initialize, (s().erc20Bridge, forUser));

        address buddy = address(new ERC1967Proxy{salt: salt}(implementationAddress, initBytes));
        require(s().userForBuddy[buddy] == address(0), "Buddy already exists for user");

        s().buddyForUser[forUser] = buddy;
        s().userForBuddy[buddy] = forUser;

        emit BuddyCreated(forUser, buddy);
        return buddy;
    }

    function callBuddyForUser(uint256 amountToSpend, address addressToCall, bytes memory userCalldata) public {
        address buddy = findOrCreateBuddy(msg.sender);
        FacetBuddyVe5c(buddy).callForUser(amountToSpend, addressToCall, userCalldata);
    }

    function predictBuddyAddress(address forUser) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(forUser));
        address implementationAddress = MigrationLib.predeployAddrFromName("FacetBuddyVe5c");
        bytes memory initBytes = abi.encodeCall(FacetBuddyVe5c.initialize, (s().erc20Bridge, forUser));

        bytes32 bytecodeHash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementationAddress, initBytes)
            ))
        ));

        return address(uint160(uint256(bytecodeHash)));
    }
    
    event UpgradeAdminChanged(address indexed newUpgradeAdmin);
    function setUpgradeAdmin(address newUpgradeAdmin) public {
        if (MigrationLib.isInMigration()) {
            emit UpgradeAdminChanged(newUpgradeAdmin);
        } else {
            revert("Contract not upgradeable");
        }
    }
}
