// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/predeploys/FacetBuddyFactoryVef8.sol";

library FacetBuddyLib {
    address public constant v1BuddyFactory = 0xbEFa89a61c00730FF003854376148200b8F00E0a;

    function isBuddyOfUser(address potentialBuddy, address user) internal view returns (bool) {
        if (v1BuddyFactory.code.length == 0) return false;

        try FacetBuddyFactoryVef8(v1BuddyFactory).buddyForUser(user) returns (address buddy) {
            return buddy == potentialBuddy;
        } catch {
            return false;
        }
    }
}
