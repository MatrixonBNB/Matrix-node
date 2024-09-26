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
    
    function getDeployerNonce() internal view returns (uint256 nonce) {
        address deployer = msg.sender;
        address computedAddress;
        uint256 maxAttempts = 100_000;
        
        // Iterate until we find the nonce that produces this contract's address
        while (true) {
            computedAddress = compAddr(deployer, nonce);
            
            if (computedAddress == address(this)) {
                return nonce;
            }
            
            // Prevent infinite loop in case of an error
            require(nonce <= maxAttempts, "Nonce not found");
            
            nonce++;
        }
    }
    
    function compAddr(address deployer, uint256 nonce) pure internal returns (address) {
        return address(uint160(uint256(keccak256(LibRLP.p(deployer).p(nonce).encode()))));
    }
    
    function compAddrLegacy(address deployer, uint256 nonce) pure internal returns (address) {
        return address(uint160(uint256(keccak256(LibRLP.p(deployer).p(nonce).p('facet').encode()))));
    }
    
    function computeLegacyAddress() internal view returns (address) {
        return compAddrLegacy(msg.sender, getDeployerNonce());
    }
    
    function _initializeLegacyAddress() internal {
        require(getLegacyContractAddress() == address(0), "Legacy address already set");
        
        if (msg.sender != tx.origin) {
            return;
        }
        
        getLegacyAddressStorage().legacyContractAddress = computeLegacyAddress();
    }
    
    function getLegacyContractAddress() public view returns (address) {
        return getLegacyAddressStorage().legacyContractAddress;
    }
}
