// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IBuddyFactory {
    function isBuddyOfUser(address potentialBuddy, address forUser) external view returns (bool);
}

abstract contract BuddyEnabled {
    address public constant v1BuddyFactory = 0xbEFa89a61c00730FF003854376148200b8F00E0a;
        
    struct BuddyEnabledStorage {
        mapping(address => address) userToBuddyFactory;
    }
    
    function _BuddyEnabledStorage() internal pure returns (BuddyEnabledStorage storage cs) {
        bytes32 position = keccak256("BuddyEnabledStorage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    function buddyFactoryForUser(address user) public view returns (address) {
        return _BuddyEnabledStorage().userToBuddyFactory[user];
    }
    
    function _setBuddyFactory(address user, address buddyFactory) internal {
        require(buddyFactory != address(0), "Buddy factory cannot be the zero address");
        _BuddyEnabledStorage().userToBuddyFactory[user] = buddyFactory;
    }
    
    function _initializeBuddyFactory(address user, address buddyFactory) internal {
        _setBuddyFactory(user, buddyFactory);
    }
        
    function updateBuddyFactory(address user, address buddyFactory) public {
        require(msg.sender == user, "Only the user can update the buddy factory");
        
        _setBuddyFactory(user, buddyFactory);
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
}
