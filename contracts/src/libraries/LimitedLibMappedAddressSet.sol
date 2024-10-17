// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library LimitedLibMappedAddressSet {
    struct MappedSet {
        mapping(address => bool) isIncluded;
        address[] elements;
    }

    function add(MappedSet storage self, address value) internal {
        if (!self.isIncluded[value]) {
            self.isIncluded[value] = true;
            self.elements.push(value);
        }
    }

    function removeFromMapping(MappedSet storage self, address value) internal {
        delete self.isIncluded[value];
    }

    function contains(MappedSet storage self, address value) internal view returns (bool) {
        return self.isIncluded[value];
    }

    function length(MappedSet storage self) internal view returns (uint256) {
        return self.elements.length;
    }

    function at(MappedSet storage self, uint256 index) internal view returns (address) {
        require(index < self.elements.length, "Index out of bounds");
        return self.elements[index];
    }

    function values(MappedSet storage self) internal view returns (address[] memory) {
        return self.elements;
    }

    function clearArray(MappedSet storage self) internal {
        delete self.elements;
    }
}
