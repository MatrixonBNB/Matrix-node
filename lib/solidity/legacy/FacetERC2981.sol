// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract FacetERC2981 {
    event DefaultRoyaltyUpdated(address indexed receiver, uint96 feeNumerator);
    event TokenRoyaltyUpdated(uint256 indexed tokenId, address indexed receiver, uint96 feeNumerator);

    struct ERC2981Storage {
        mapping(uint256 => address) tokenIdToReceiver;
        mapping(uint256 => uint96) tokenIdToFeeNumerator;
        address defaultRoyaltyReceiver;
        uint96 defaultFeeNumerator;
    }

    function _ERC2981Storage() internal pure returns (ERC2981Storage storage ds) {
        bytes32 position = keccak256("ERC2981Storage.contract.storage.v1");
        assembly {
            ds.slot := position
        }
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) public view virtual returns (address receiver, uint256 royaltyAmount) {
        receiver = _ERC2981Storage().tokenIdToReceiver[tokenId];
        uint96 feeNumerator = _ERC2981Storage().tokenIdToFeeNumerator[tokenId];
        if (receiver == address(0)) {
            receiver = _ERC2981Storage().defaultRoyaltyReceiver;
            feeNumerator = _ERC2981Storage().defaultFeeNumerator;
        }
        royaltyAmount = (salePrice * feeNumerator) / _feeDenominator();
        return (receiver, royaltyAmount);
    }

    function _setDefaultRoyalty(address receiver, uint96 feeNumerator) internal virtual {
        require(feeNumerator <= _feeDenominator(), "ERC2981: Invalid default royalty");
        require(receiver != address(0), "ERC2981: Invalid default royalty receiver");
        _ERC2981Storage().defaultRoyaltyReceiver = receiver;
        _ERC2981Storage().defaultFeeNumerator = feeNumerator;
        emit DefaultRoyaltyUpdated(receiver, feeNumerator);
    }

    function _deleteDefaultRoyalty() internal virtual {
        _ERC2981Storage().defaultRoyaltyReceiver = address(0);
        _ERC2981Storage().defaultFeeNumerator = 0;
        emit DefaultRoyaltyUpdated(address(0), 0);
    }

    function _setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) internal virtual {
        require(feeNumerator <= _feeDenominator(), "ERC2981: Invalid token royalty");
        require(receiver != address(0), "ERC2981: Invalid token royalty receiver");
        _ERC2981Storage().tokenIdToReceiver[tokenId] = receiver;
        _ERC2981Storage().tokenIdToFeeNumerator[tokenId] = feeNumerator;
        emit TokenRoyaltyUpdated(tokenId, receiver, feeNumerator);
    }

    function _deleteTokenRoyalty(uint256 tokenId) internal virtual {
        _ERC2981Storage().tokenIdToReceiver[tokenId] = address(0);
        _ERC2981Storage().tokenIdToFeeNumerator[tokenId] = 0;
        emit TokenRoyaltyUpdated(tokenId, address(0), 0);
    }

    function _feeDenominator() internal view virtual returns (uint96) {
        return 10000;
    }

    function supportsERC2981() public pure virtual returns (bool) {
        return true;
    }
}
