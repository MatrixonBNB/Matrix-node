// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/tokens/ERC721.sol";
import "./FacetBuddyLib.sol";
import "src/libraries/PublicImplementationAddress.sol";
import "solady/src/utils/EnumerableSetLib.sol";
import "./MigrationLib.sol";

abstract contract FacetERC721 is ERC721, PublicImplementationAddress {
    using FacetBuddyLib for address;
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    struct FacetERC721Storage {
        string name;
        string symbol;
        EnumerableSetLib.Uint256Set tokensToInit;
    }
    
    function _FacetERC721Storage() internal pure returns (FacetERC721Storage storage cs) {
        bytes32 position = keccak256("FacetERC721Storage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    function _initializeERC721(string memory name, string memory symbol) internal {
        _FacetERC721Storage().name = name;
        _FacetERC721Storage().symbol = symbol;
    }
    
    function name() public view virtual override returns (string memory) {
        return _FacetERC721Storage().name;
    }
    
    function symbol() public view virtual override returns (string memory) {
        return _FacetERC721Storage().symbol;
    }
    
    function transferFrom(address from, address to, uint256 id) public payable virtual override {
        if (msg.sender.isBuddyOfUser(from)) {
            setApprovalForAll(msg.sender, true);
        }
        
        return super.transferFrom(from, to, id);
    }
    
    function setApprovalForAll(address operator, bool approved) public virtual override {
        super.setApprovalForAll(operator, approved);
    }
    
    function approve(address spender, uint256 id) public payable virtual override {
        super.approve(spender, id);
    }
    
    function isApprovedOrOwner(address spender, uint256 id) public view virtual returns (bool) {
        bool baseCase = super._isApprovedOrOwner(spender, id);
        
        if (baseCase) return true;
        
        address owner = ownerOf(id);
        
        return spender.isBuddyOfUser(owner);
    }
    
    function _beforeTokenTransfer(address, address, uint256 id) internal virtual override {
        if (MigrationLib.isInMigration()) {
            _FacetERC721Storage().tokensToInit.add(id);
        } else {
            require(allTokensInitialized(), "Tokens not initialized");
        }
    }
    
    function allTokensInitialized() public view returns (bool) {
        return _FacetERC721Storage().tokensToInit.length() == 0;
    }
    
    function initAllTokens() public {
        require(MigrationLib.isNotInMigration(), "Migration in progress");
                
        FacetERC721Storage storage fs = _FacetERC721Storage();
        
        for (uint256 i = 0; i < fs.tokensToInit.length(); i++) {
            uint256 tokenId = fs.tokensToInit.at(i);
            address owner = _ownerOf(tokenId);
            
            if (owner != address(0)) {
                emit Transfer(address(0), owner, tokenId);
            }
            
            fs.tokensToInit.remove(tokenId);
        }
    }
}
