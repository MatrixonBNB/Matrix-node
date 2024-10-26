// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IBuddyFactory {
    function isBuddyOfUser(address potentialBuddy, address forUser) external view returns (bool);
    function findOrCreateBuddy(address forUser) external returns (address);
    function predictBuddyAddress(address forUser) external view returns (address);
}

interface IBuddy {
    function callFromBridge(address addressToCall, bytes memory userCalldata) external;
}

abstract contract BuddyEnabled {
    address public constant v1BuddyFactory = 0xbEFa89a61c00730FF003854376148200b8F00E0a;
        
    struct BuddyEnabledStorage {
        address defaultBuddyFactory;
        mapping(address => address) userToBuddyFactory;
    }
    
    function _BuddyEnabledStorage() internal pure returns (BuddyEnabledStorage storage cs) {
        bytes32 position = keccak256("BuddyEnabledStorage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    function buddyFactoryForUser(address user) public view returns (address) {
        address userSet = _BuddyEnabledStorage().userToBuddyFactory[user];
        if (userSet != address(0)) return userSet;
        return _BuddyEnabledStorage().defaultBuddyFactory;
    }
    
    function _setUserBuddyFactory(address user, address buddyFactory) internal {
        _BuddyEnabledStorage().userToBuddyFactory[user] = buddyFactory;
    }
    
    function _initializeDefaultBuddyFactory(address buddyFactory) internal {
        _setDefaultBuddyFactory(buddyFactory);
    }
    
    function _setDefaultBuddyFactory(address buddyFactory) internal {
        _BuddyEnabledStorage().defaultBuddyFactory = buddyFactory;
    }
    
    function _getDefaultBuddyFactory() internal view returns (address) {
        return _BuddyEnabledStorage().defaultBuddyFactory;
    }
    
    function updateUserBuddyFactory(address user, address buddyFactory) public {
        require(msg.sender == user, "Only the user can update the buddy factory");
        
        _setUserBuddyFactory(user, buddyFactory);
    }
    
    function findOrCreateBuddy(address forUser) public returns (IBuddy) {
        address buddyFactory = buddyFactoryForUser(forUser);
        return IBuddy(IBuddyFactory(buddyFactory).findOrCreateBuddy(forUser));
    }
    
    function isBuddyOfUser(address potentialBuddy, address user) public view returns (bool) {
        address buddyFactory = buddyFactoryForUser(user);
        
        if (buddyFactory.code.length == 0) return false;
        
        try IBuddyFactory(buddyFactory).isBuddyOfUser(potentialBuddy, user) returns (bool isBuddy) {
            return isBuddy;
        } catch {
            return false;
        }
    }
    
    function predictBuddyAddress(address forUser) public view returns (address) {
        return IBuddyFactory(buddyFactoryForUser(forUser)).predictBuddyAddress(forUser);
    }
}
