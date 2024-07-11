// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "solady/src/tokens/ERC721.sol";

abstract contract FacetERC721 is ERC721 {
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
    
    function setApprovalForAll(address operator, bool approved) public virtual override {
        super.setApprovalForAll(operator, approved);
    }
    
    function approve(address spender, uint256 id) public payable virtual override {
        super.approve(spender, id);
    }
}
