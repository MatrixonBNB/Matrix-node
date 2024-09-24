// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/utils/EIP712.sol";
import "solady/src/utils/ECDSA.sol";
import "solady/src/utils/LibString.sol";
import "solady/src/utils/LibRLP.sol";

abstract contract FacetEIP712 is EIP712 {
    using LibRLP for LibRLP.List;

    struct FacetEIP712Storage {
        address legacyContractAddress;
    }
    
    function getFacetEIP712Storage() internal pure returns (FacetEIP712Storage storage fs) {
        bytes32 position = keccak256("FacetEIP712Storage.contract.storage.v1");
        assembly {
            fs.slot := position
        }
    }
    
    using ECDSA for bytes32;
    using LibString for *;
    
    function getDeployerNonce() internal view returns (uint256 nonce) {
        address deployer = msg.sender;
        address computedAddress;
        uint256 maxAttempts = 1000;
        
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
    
    function computeLegacyAddress(address deployer) internal view returns (address) {
        return compAddrLegacy(deployer, getDeployerNonce());
    }
    
    function _initializeFacetEIP712(address deployer) internal {
        getFacetEIP712Storage().legacyContractAddress = computeLegacyAddress(deployer);
    }
    
    function getLegacyContractAddress() internal view returns (address) {
        return getFacetEIP712Storage().legacyContractAddress;
    }
    
    function verifySignatureAgainstNewAndOldChainId(bytes memory message, bytes memory signature, address signer) internal view {
        uint256 newChainId = block.chainid;
        uint256 oldChainId;
        
        if (newChainId == 0xface7) {
            oldChainId = 1;
        } else if (newChainId == 0xface7a) {
            oldChainId = 11155111;
        }
        
        bytes32 oldTypedDataHash = _hashTypedData(keccak256(message), oldChainId);
        bytes32 newTypedDataHash = _hashTypedData(keccak256(message), newChainId);
        
        bool valid = oldTypedDataHash.recover(signature) == signer || newTypedDataHash.recover(signature) == signer;
        
        require(valid, "FacetEIP712: signature does not match any valid chain id, legacy contract address: ".concat(getLegacyContractAddress().toHexString()));
    }
  
    /// @dev Returns the EIP-712 domain separator.
    function _buildDomainSeparator(uint256 chainId) private view returns (bytes32 separator) {
        // We will use `separator` to store the name hash to save a bit of gas.
        bytes32 versionHash;
        
        address verifyingAddress = getFacetEIP712Storage().legacyContractAddress;
        
        (string memory name, string memory version) = _domainNameAndVersion();
        separator = keccak256(bytes(name));
        versionHash = keccak256(bytes(version));
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Load the free memory pointer.
            mstore(m, _DOMAIN_TYPEHASH)
            mstore(add(m, 0x20), separator) // Name hash.
            mstore(add(m, 0x40), versionHash)
            mstore(add(m, 0x60), chainId)
            mstore(add(m, 0x80), verifyingAddress)
            separator := keccak256(m, 0xa0)
        }
    }
    
     function _hashTypedData(bytes32) internal view virtual override returns (bytes32) {
        revert("Pass in chainId");
     }

    function _hashTypedData(bytes32 structHash, uint256 chainId) internal view virtual returns (bytes32 digest) {
        // We will use `digest` to store the domain separator to save a bit of gas.
        digest = _buildDomainSeparator(chainId);
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the digest.
            mstore(0x00, 0x1901000000000000) // Store "\x19\x01".
            mstore(0x1a, digest) // Store the domain separator.
            mstore(0x3a, structHash) // Store the struct hash.
            digest := keccak256(0x18, 0x42)
            // Restore the part of the free memory slot that was overwritten.
            mstore(0x3a, 0)
        }
    }
    
    function _domainNameAndVersionMayChange() internal pure virtual override returns (bool result) {
        return true;
    }
}
