// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/src/tokens/ERC721.sol";
import "./FacetBuddyLib.sol";
import "src/libraries/PublicImplementationAddress.sol";
import "./MigrationLib.sol";

abstract contract FacetERC721 is ERC721, PublicImplementationAddress {
    using FacetBuddyLib for address;
    struct FacetERC721Storage {
        string name;
        string symbol;
        mapping(uint256 => bool) ownerInitialized;
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
    
    function _beforeTokenTransfer(address from, address, uint256 id) internal virtual override {
        initOwnerIfNeeded(from, id);
    }
    
    function initOwnerIfNeeded(address currentOwner, uint256 id) public {
        if (MigrationLib.isInMigration()) return;
        
        FacetERC721Storage storage fs = _FacetERC721Storage();
        
        if (!fs.ownerInitialized[id]) {
            if (currentOwner != address(0)) {
                emit Transfer(address(0), currentOwner, id);
            }
            
            fs.ownerInitialized[id] = true;
        }
    }
    
    function initManyOwnersIfNeeded(uint256[] memory ids) public {
        for (uint256 i = 0; i < ids.length; i++) {
            address owner = ownerOf(ids[i]);
            initOwnerIfNeeded(owner, ids[i]);
        }
    }
}