// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/predeploys/FacetBuddyFactoryVef8.sol";

library FacetBuddyLib {
    address constant canonicalBuddyFactory = 0x5Ae4Dd90B59d2607cf35DC061E47b63189487871;
    
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
