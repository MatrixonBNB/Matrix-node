// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/utils/LibString.sol";
import "solady/src/utils/LibRLP.sol";

abstract contract LegacyAddressable {
    using LibRLP for LibRLP.List;

    struct LegacyAddressStorage {
        address legacyContractAddress;
    }
    
    function getLegacyAddressStorage() internal pure returns (LegacyAddressStorage storage fs) {
        bytes32 position = keccak256("LegacyAddressStorage.contract.storage.v1");
        assembly {
            fs.slot := position
        }
    }
    
    function _initializeLegacyAddress() internal {
        require(getLegacyContractAddress() == address(0), "Legacy address already set");
        
        if (msg.sender != tx.origin) {
            return;
        }
        
        getLegacyAddressStorage().legacyContractAddress = address(this);
    }
    
    function getLegacyContractAddress() public view returns (address) {
        return getLegacyAddressStorage().legacyContractAddress;
    }
}
