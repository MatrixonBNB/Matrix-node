// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "solady/utils/Initializable.sol";

contract PublicMintERC20Vc88 is FacetERC20, Initializable {
    struct PublicMintERC20Storage {
        uint256 maxSupply;
        uint256 perMintLimit;
    }
    
    function s() internal pure returns (PublicMintERC20Storage storage cs) {
        bytes32 position = keccak256("PublicMintERC20Storage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    function getMaxSupply() public view returns (uint256) {
        return s().maxSupply;
    }

    function getPerMintLimit() public view returns (uint256) {
        return s().perMintLimit;
    }
  
    constructor() {
      _disableInitializers();
    }
  
    function initialize(
      string memory name,
      string memory symbol,
      uint256 maxSupply,
      uint256 perMintLimit,
      uint8 decimals
    ) public initializer {
        _initializeERC20(name, symbol, decimals);
        s().maxSupply = maxSupply;
        s().perMintLimit = perMintLimit;
    }

    function mint(uint256 amount) public {
        require(amount > 0, "Amount must be positive");
        require(amount <= s().perMintLimit, "Exceeded mint limit");
        require(totalSupply() + amount <= s().maxSupply, "Exceeded max supply");
        _mint(msg.sender, amount);
    }

    function airdrop(address to, uint256 amount) public {
        require(amount > 0, "Amount must be positive");
        require(amount <= s().perMintLimit, "Exceeded mint limit");
        require(totalSupply() + amount <= s().maxSupply, "Exceeded max supply");
        _mint(to, amount);
    }
}
