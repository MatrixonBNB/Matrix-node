// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./FacetBuddyFactoryVef8.sol";

library FacetBuddyLib {
    address constant canonicalBuddyFactory = 0xbEFa89a61c00730FF003854376148200b8F00E0a;
    
    function isBuddyOfUser(address potentialBuddy, address user) internal view returns (bool) {
        uint256 codeSize;
        assembly { codeSize := extcodesize(canonicalBuddyFactory) }
        if (codeSize == 0) return false;
        
        try FacetBuddyFactoryVef8(canonicalBuddyFactory).buddyForUser(user) returns (address buddy) {
            return buddy == potentialBuddy;
        } catch {
            return false;
        }
    }
}
