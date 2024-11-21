// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/tokens/ERC721.sol";
import "src/libraries/FacetBuddyLib.sol";
import "src/libraries/MigrationLib.sol";

interface IBaseRegistrar {
    function controllers(address user) external view returns (bool);
}

abstract contract FacetERC721 is ERC721 {
    using FacetBuddyLib for address;
    
    struct FacetERC721Storage {
        string name;
        string symbol;
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
        if (MigrationLib.isInMigration() && msg.sender.isBuddyOfUser(from)) {
            setApprovalForAll(msg.sender, true);
        }
        
        if (MigrationLib.isInMigration() && isController(msg.sender)) {
            _approve(from, msg.sender, id);
        }
        
        return super.transferFrom(from, to, id);
    }
    
    function controllerSetApprovalForAll(address by, address operator, bool isApproved) public virtual {
        if (MigrationLib.isInMigration() && isController(msg.sender)) {
            _setApprovalForAll(by, operator, isApproved);
        }
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
        
        return MigrationLib.isInMigration() &&
        (spender.isBuddyOfUser(owner) || isController(spender));
    }
    
    function _afterTokenTransfer(address, address, uint256 id) internal virtual override {
        if (MigrationLib.isInMigration()) {
            MigrationLib.manager().recordERC721TokenId(id);
        }
    }
    
    function safeOwnerOf(uint256 id) external view returns (address) {
        return _ownerOf(id);
    }
    
    function isController(address user) public view returns (bool) {
        try IBaseRegistrar(address(this)).controllers(user) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }
    
    error NotMigrationManager();
    function emitTransferEvent(uint256 id) external {
        address manager = MigrationLib.MIGRATION_MANAGER;
        assembly {
            if xor(caller(), manager) {
                mstore(0x00, 0x2fb9930a) // 0x3cc50b45 is the 4-byte selector of "NotMigrationManager()"
                revert(0x1C, 0x04) // returns the stored 4-byte selector from above
            }
        }
        
        address owner = _ownerOf(id);
        
        if (owner == address(0)) return;
        
        emit Transfer({
            from: address(0),
            to: owner,
            id: id
        });
    }
}
