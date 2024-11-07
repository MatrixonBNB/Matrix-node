// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/utils/Initializable.sol";
import "solady/utils/MerkleProofLib.sol";
import "src/libraries/FacetERC721.sol";
import "src/libraries/FacetERC2981.sol";
import "src/libraries/Upgradeable.sol";
import "src/libraries/FacetOwnable.sol";
import "src/libraries/Pausable.sol";
import "src/libraries/FacetERC20.sol";
import "./EditionMetadataRendererV3f8.sol";
import "solady/utils/LibString.sol";

contract NFTCollectionV77f is FacetERC721, FacetERC2981, Upgradeable, FacetOwnable, Pausable, Initializable {
    using LibString for uint256;

    struct NFTCollectionStorage {
        uint256 maxSupply;
        uint256 totalSupply;
        uint256 maxPerMint;
        string baseURI;
        address WETH;
        address metadataRenderer;
        uint256 publicMaxPerAddress;
        uint256 publicMintStart;
        uint256 publicMintEnd;
        uint256 publicMintPrice;
        bytes32 allowListMerkleRoot;
        uint256 allowListMaxPerAddress;
        uint256 allowListMintStart;
        uint256 allowListMintEnd;
        uint256 allowListMintPrice;
        uint256 perMintFee;
        address feeTo;
        mapping(address => uint256) publicNumberMinted;
        mapping(address => uint256) allowListNumberMinted;
        uint256 nextTokenId;
    }

    function s() internal pure returns (NFTCollectionStorage storage ns) {
        bytes32 position = keccak256("NFTCollectionV101.contract.storage.v1");
        assembly {
            ns.slot := position
        }
    }

    event Minted(
        address indexed to,
        uint256 amount,
        uint256 mintPrice,
        uint256 totalCost,
        uint256 newTotalSupply,
        bool isPublic
    );
    event PublicMaxPerAddressUpdated(uint256 publicMaxPerAddress);
    event PublicMintStartUpdated(uint256 publicMintStart);
    event PublicMintEndUpdated(uint256 publicMintEnd);
    event PublicMintPriceUpdated(uint256 publicMintPrice);
    event AllowListMerkleRootUpdated(bytes32 allowListMerkleRoot);
    event AllowListMaxPerAddressUpdated(uint256 allowListMaxPerAddress);
    event AllowListMintStartUpdated(uint256 allowListMintStart);
    event AllowListMintEndUpdated(uint256 allowListMintEnd);
    event AllowListMintPriceUpdated(uint256 allowListMintPrice);
    event MaxSupplyUpdated(uint256 maxSupply);
    event BaseURIUpdated(string baseURI);
    event MetadataRendererUpdated(address metadataRenderer);

    function initialize(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        string memory baseURI,
        address weth,
        uint256 perMintFee,
        address feeTo
    ) public initializer {
        _initializeERC721(name, symbol);
        _initializeOwner(msg.sender);
        _initializeUpgradeAdmin(msg.sender);
        s().maxSupply = maxSupply;
        s().baseURI = baseURI;
        s().WETH = weth;
        s().maxPerMint = 25;
        s().perMintFee = perMintFee;
        s().feeTo = feeTo;
        s().nextTokenId = 1;
    }
    
    function setMaxPerMint(uint256 maxPerMint) public onlyOwner {
        s().maxPerMint = maxPerMint;
    }

    function _handleMint(
        address to,
        uint256 amount,
        bytes32[] memory merkleProof
    ) whenNotPaused internal {
        require(isMintActive(), "Mint is not active");
        require(amount > 0, "Amount must be positive");
        require(s().maxSupply == 0 || s().totalSupply + amount <= s().maxSupply, "Exceeded max supply");
        require(amount <= s().maxPerMint, "Exceeded max per mint");

        bool isAllowListMint = merkleProof.length > 0 && isAllowListMintActive();
        uint256 numberMinted;
        uint256 mintPrice;
        uint256 maxPerAddress;

        if (isAllowListMint) {
            require(isOnAllowList(to, merkleProof), "Not on allow list");
            s().allowListNumberMinted[to] += amount;
            numberMinted = s().allowListNumberMinted[to];
            mintPrice = s().allowListMintPrice;
            maxPerAddress = s().allowListMaxPerAddress;
        } else {
            s().publicNumberMinted[to] += amount;
            numberMinted = s().publicNumberMinted[to];
            mintPrice = s().publicMintPrice;
            maxPerAddress = s().publicMaxPerAddress;
        }

        require(maxPerAddress == 0 || numberMinted <= maxPerAddress, "Exceeded mint limit");

        uint256 totalFee = s().perMintFee * amount;
        if (totalFee > 0 && s().feeTo != address(0)) {
            ERC20(s().WETH).transferFrom(msg.sender, s().feeTo, totalFee);
        }

        uint256 totalCost = mintPrice * amount;
        if (totalCost > 0) {
            require(s().WETH != address(0), "WETH not set");
            ERC20(s().WETH).transferFrom(msg.sender, address(this), totalCost);
        }

        uint256 initialId = s().nextTokenId;
        s().nextTokenId += amount;
        s().totalSupply += amount;
        
        for (uint256 i = 0; i < amount; i++) {
            _mint(to, initialId + i);
        }

        emit Minted(to, amount, mintPrice, totalCost, s().totalSupply, !isAllowListMint);
    }

    function _isMintActive(uint256 mintStart, uint256 mintEnd) internal view returns (bool) {
        bool isNotMintedOut = s().maxSupply == 0 || s().totalSupply < s().maxSupply;
        bool isOwner = owner() == msg.sender;
        bool isOrAfterStart = block.timestamp >= mintStart && mintStart > 0;
        bool isBeforeEnd = block.timestamp < mintEnd || mintEnd == 0;
        return isNotMintedOut && isBeforeEnd && (isOwner || isOrAfterStart);
    }

    function isPublicMintActive() public view returns (bool) {
        return _isMintActive(s().publicMintStart, s().publicMintEnd);
    }

    function isAllowListMintActive() public view returns (bool) {
        return _isMintActive(s().allowListMintStart, s().allowListMintEnd);
    }

    function isMintActive() public view returns (bool) {
        return isPublicMintActive() || isAllowListMintActive();
    }

    function isOnAllowList(address wallet, bytes32[] memory merkleProof) public view returns (bool) {
        return MerkleProofLib.verify(merkleProof, s().allowListMerkleRoot, keccak256(abi.encodePacked(wallet)));
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");

        if (s().metadataRenderer != address(0)) {
            return EditionMetadataRendererV3f8(s().metadataRenderer).tokenURI(tokenId);
        }

        if (bytes(s().baseURI).length == 0) {
            return "";
        }

        if (bytes(s().baseURI)[bytes(s().baseURI).length - 1] != "/") {
            return s().baseURI;
        }

        return string(abi.encodePacked(s().baseURI, tokenId.toString()));
    }

    function contractURI() public view returns (string memory) {
        if (s().metadataRenderer == address(0)) {
            return "";
        }
        return EditionMetadataRendererV3f8(s().metadataRenderer).contractURI();
    }

    function airdrop(
        address to,
        uint256 amount,
        bytes32[] memory merkleProof
    ) public {
        _handleMint(to, amount, merkleProof);
    }

    function mint(
        uint256 amount,
        bytes32[] memory merkleProof
    ) public {
        _handleMint(msg.sender, amount, merkleProof);
    }

    function setPublicMaxPerAddress(uint256 publicMaxPerAddress) public onlyOwner {
        s().publicMaxPerAddress = publicMaxPerAddress;
        emit PublicMaxPerAddressUpdated(publicMaxPerAddress);
    }

    function setPublicMintStart(uint256 publicMintStart) public onlyOwner {
        s().publicMintStart = publicMintStart;
        emit PublicMintStartUpdated(publicMintStart);
    }

    function setPublicMintEnd(uint256 publicMintEnd) public onlyOwner {
        s().publicMintEnd = publicMintEnd;
        emit PublicMintEndUpdated(publicMintEnd);
    }

    function setPublicMintPrice(uint256 publicMintPrice) public onlyOwner {
        s().publicMintPrice = publicMintPrice;
        emit PublicMintPriceUpdated(publicMintPrice);
    }

    function setAllowListMerkleRoot(bytes32 allowListMerkleRoot) public onlyOwner {
        s().allowListMerkleRoot = allowListMerkleRoot;
        emit AllowListMerkleRootUpdated(allowListMerkleRoot);
    }

    function setAllowListMaxPerAddress(uint256 allowListMaxPerAddress) public onlyOwner {
        s().allowListMaxPerAddress = allowListMaxPerAddress;
        emit AllowListMaxPerAddressUpdated(allowListMaxPerAddress);
    }

    function setAllowListMintStart(uint256 allowListMintStart) public onlyOwner {
        s().allowListMintStart = allowListMintStart;
        emit AllowListMintStartUpdated(allowListMintStart);
    }

    function setAllowListMintEnd(uint256 allowListMintEnd) public onlyOwner {
        s().allowListMintEnd = allowListMintEnd;
        emit AllowListMintEndUpdated(allowListMintEnd);
    }

    function setAllowListMintPrice(uint256 allowListMintPrice) public onlyOwner {
        s().allowListMintPrice = allowListMintPrice;
        emit AllowListMintPriceUpdated(allowListMintPrice);
    }

    function setMaxSupply(uint256 maxSupply) public onlyOwner {
        require(s().maxSupply == 0, "Max supply already set");
        require(maxSupply >= s().totalSupply, "New max supply must be greater than total supply");
        s().maxSupply = maxSupply;
        emit MaxSupplyUpdated(maxSupply);
    }

    function setMetadataRenderer(address metadataRenderer, bytes memory data) public onlyOwner {
        s().metadataRenderer = metadataRenderer;
        if (bytes(data).length > 0) {
            (bool success, ) = metadataRenderer.call(data);
            require(success, "setMetadataRenderer failed");
        }
        emit MetadataRendererUpdated(metadataRenderer);
    }

    function setPublicMintSettings(
        uint256 publicMaxPerAddress,
        uint256 publicMintStart,
        uint256 publicMintEnd,
        uint256 publicMintPrice
    ) public onlyOwner {
        setPublicMaxPerAddress(publicMaxPerAddress);
        setPublicMintStart(publicMintStart);
        setPublicMintEnd(publicMintEnd);
        setPublicMintPrice(publicMintPrice);
    }

    function setAllowListMintSettings(
        bytes32 allowListMerkleRoot,
        uint256 allowListMaxPerAddress,
        uint256 allowListMintStart,
        uint256 allowListMintEnd,
        uint256 allowListMintPrice
    ) public onlyOwner {
        setAllowListMerkleRoot(allowListMerkleRoot);
        setAllowListMaxPerAddress(allowListMaxPerAddress);
        setAllowListMintStart(allowListMintStart);
        setAllowListMintEnd(allowListMintEnd);
        setAllowListMintPrice(allowListMintPrice);
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        s().baseURI = baseURI;
        emit BaseURIUpdated(baseURI);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function withdrawWETH() public onlyOwner {
        uint256 amount = ERC20(s().WETH).balanceOf(address(this));
        ERC20(s().WETH).transfer(owner(), amount);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() public onlyOwner {
        _deleteDefaultRoyalty();
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function deleteTokenRoyalty(uint256 tokenId) public onlyOwner {
        _deleteTokenRoyalty(tokenId);
    }

    function setFeeTo(address feeTo) public {
        require(msg.sender == s().feeTo, "Only feeTo can change feeTo");
        s().feeTo = feeTo;
    }
    
    function burn(uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: msg.sender not authorized to burn");
        s().totalSupply -= 1;
        _burn(tokenId);
    }

    function burnMultiple(uint256[] memory tokenIds) public {
        require(tokenIds.length > 0, "No token ids provided");
        require(tokenIds.length <= 20, "Too many token ids provided");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            burn(tokenIds[i]);
        }
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC2981, ERC721) returns (bool) {
        return 
            ERC2981.supportsInterface(interfaceId) || 
            ERC721.supportsInterface(interfaceId);
    }
}
