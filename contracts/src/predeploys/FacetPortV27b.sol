// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/Upgradeable.sol";
import "src/libraries/FacetOwnable.sol";
import "src/libraries/Pausable.sol";
import "src/libraries/FacetERC721.sol";
import "src/libraries/FacetERC20.sol";
import "src/libraries/FacetERC2981.sol";
import "src/libraries/FacetEIP712.sol";
import "solady/src/utils/Initializable.sol";
import "solady/src/utils/ECDSA.sol";
import "solady/src/utils/SafeTransferLib.sol";

contract FacetPortV27b is Upgradeable, FacetOwnable, Pausable, Initializable, FacetEIP712 {
    using SafeTransferLib for address;
    using ECDSA for bytes32;
    
    struct FacetPortStorage {
        mapping(address => mapping(bytes16 => bool)) userOfferCancellations;
        mapping(string => mapping(address => mapping(address => mapping(uint256 => uint256)))) userOffersOnAssetValidAfterTime;
        mapping(string => mapping(address => uint256)) userOffersValidAfterTime;
        uint96 feeBps;
    }

    function s() internal pure returns (FacetPortStorage storage fs) {
        bytes32 position = keccak256("FacetPortV1.contract.storage.v1");
        assembly {
            fs.slot := position
        }
    }

    event OfferAccepted(bool success, string offerType, address indexed offerer, address indexed buyer, address indexed seller, address assetContract, uint256 assetId, uint256 considerationAmount, address considerationToken, bytes16 offerId);
    event OfferCancelled(address indexed offerer, bytes16 indexed offerId);
    event AllOffersOnAssetCancelledForUser(string offerType, address indexed offerer, address indexed assetContract, uint256 assetId);
    event AllOffersCancelledForUser(string offerType, address indexed offerer);

    function initialize(uint96 _feeBps, address _upgradeAdmin, address _owner) public initializer {
        s().feeBps = _feeBps;
        _initializeUpgradeAdmin(_upgradeAdmin);
        _initializeOwner(_owner);
        _pause();
    }

    function setFeeBps(uint96 _feeBps) external onlyOwner {
        s().feeBps = _feeBps;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function acceptOfferWithSignature(
        string memory offerType,
        bytes16 offerId,
        address offerer,
        address assetContract,
        uint256 assetId,
        string memory assetType,
        uint256 assetAmount,
        address considerationToken,
        uint256 considerationAmount,
        uint256 startTime,
        uint256 endTime,
        bytes memory signature
    ) external {
        bool success = _acceptOfferWithSignature(offerType, offerId, offerer, assetContract, assetId, assetType, assetAmount, considerationToken, considerationAmount, startTime, endTime, signature);
        require(success, "Offer was not successfully accepted");
    }

    function acceptMultipleOffersWithSignatures(
        string[] memory offerTypes,
        bytes16[] memory offerIds,
        address[] memory offerers,
        address[] memory assetContracts,
        uint256[] memory assetIds,
        string[] memory assetTypes,
        uint256[] memory assetAmounts,
        address[] memory considerationTokens,
        uint256[] memory considerationAmounts,
        uint256[] memory startTimes,
        uint256[] memory endTimes,
        bytes[] memory signatures
    ) external {
        require(offerIds.length == offerers.length, "Array lengths mismatch");
        require(offerIds.length == offerTypes.length, "Array lengths mismatch");
        require(offerIds.length == assetContracts.length, "Array lengths mismatch");
        require(offerIds.length == assetIds.length, "Array lengths mismatch");
        require(offerIds.length == assetTypes.length, "Array lengths mismatch");
        require(offerIds.length == assetAmounts.length, "Array lengths mismatch");
        require(offerIds.length == considerationTokens.length, "Array lengths mismatch");
        require(offerIds.length == considerationAmounts.length, "Array lengths mismatch");
        require(offerIds.length == startTimes.length, "Array lengths mismatch");
        require(offerIds.length == endTimes.length, "Array lengths mismatch");
        require(offerIds.length == signatures.length, "Array lengths mismatch");
        require(offerIds.length <= 20, "Cannot accept more than 20 offers at a time");

        bool atLeastOneSuccess = false;
        for (uint256 i = 0; i < offerIds.length; i++) {
            bool success = _acceptOfferWithSignature(offerTypes[i], offerIds[i], offerers[i], assetContracts[i], assetIds[i], assetTypes[i], assetAmounts[i], considerationTokens[i], considerationAmounts[i], startTimes[i], endTimes[i], signatures[i]);
            if (success) {
                atLeastOneSuccess = true;
            }
        }
        require(atLeastOneSuccess, "No offers were successfully accepted");
    }

    function _acceptOfferWithSignature(
        string memory offerType,
        bytes16 offerId,
        address offerer,
        address assetContract,
        uint256 assetId,
        string memory assetType,
        uint256 assetAmount,
        address considerationToken,
        uint256 considerationAmount,
        uint256 startTime,
        uint256 endTime,
        bytes memory signature
    ) internal whenNotPaused returns (bool) {
        bytes memory message = abi.encode(
            keccak256("Offer(string offerType,bytes16 offerId,address offerer,address assetContract,uint256 assetId,string assetType,uint256 assetAmount,address considerationToken,uint256 considerationAmount,uint256 startTime,uint256 endTime)"),
            keccak256(bytes(offerType)),
            offerId,
            offerer,
            assetContract,
            assetId,
            keccak256(bytes(assetType)),
            assetAmount,
            considerationToken,
            considerationAmount,
            startTime,
            endTime
        );
        
        verifySignatureAgainstNewAndOldChainId(message, signature, offerer);
        
        require(!s().userOfferCancellations[offerer][offerId], "Offer cancelled");
        require(keccak256(bytes(offerType)) == keccak256(bytes("Listing")) || keccak256(bytes(offerType)) == keccak256(bytes("Bid")), "Invalid offer type");
        require(keccak256(bytes(assetType)) == keccak256(bytes("ERC721")) && assetAmount == 1, "Only ERC721 assets are supported");
        require(block.timestamp >= startTime, "Current time is before the start time");
        require(block.timestamp < endTime, "Current time is after the end time");
        require(startTime > s().userOffersOnAssetValidAfterTime[offerType][offerer][assetContract][assetId], "Start time is before the offerer's valid after time");
        require(startTime > s().userOffersValidAfterTime[offerType][offerer], "Start time is before the valid after time for the offerer");

        address buyer;
        address seller;

        if (keccak256(bytes(offerType)) == keccak256(bytes("Bid"))) {
            buyer = offerer;
            seller = msg.sender;
        } else {
            buyer = msg.sender;
            seller = offerer;
        }

        bool transferSucceeded = _payRoyaltiesAndTransfer(assetContract, assetId, seller, buyer, considerationAmount, considerationToken);

        emit OfferAccepted(transferSucceeded, offerType, offerer, buyer, seller, assetContract, assetId, considerationAmount, considerationToken, offerId);
        return transferSucceeded;
    }

    function _payRoyaltiesAndTransfer(
        address assetContract,
        uint256 assetId,
        address seller,
        address buyer,
        uint256 considerationAmount,
        address considerationToken
    ) internal returns (bool) {
        address currentOwner = FacetERC721(assetContract).ownerOf(assetId);
        if (currentOwner != seller) {
            return false;
        }

        (bool success, bytes memory data) = assetContract.call(abi.encodeWithSignature("supportsERC2981()"));
        uint256 royaltyAmount = 0;

        if (success && abi.decode(data, (bool))) {
            (address receiver, uint256 _royaltyAmount) = FacetERC2981(assetContract).royaltyInfo(assetId, considerationAmount);
            royaltyAmount = _royaltyAmount;

            if (receiver == address(0)) {
                royaltyAmount = 0;
            }

            if (royaltyAmount > 0) {
                ERC20(considerationToken).transferFrom(buyer, receiver, royaltyAmount);
            }
        }

        uint256 marketplaceFee = computeFee(considerationAmount);
        uint256 sellerAmount = considerationAmount - royaltyAmount - marketplaceFee;
        
        if (sellerAmount > 0) {
            ERC20(considerationToken).transferFrom(buyer, seller, sellerAmount);
        }

        if (marketplaceFee > 0) {
            ERC20(considerationToken).transferFrom(buyer, owner(), marketplaceFee);
        }
        
        _transferNFT(assetContract, assetId, buyer, seller);

        return true;
    }

    function transferNFTs(address[] memory assetContracts, uint256[] memory assetIds, address[] memory recipients) external {
        require(assetContracts.length == assetIds.length, "Array lengths mismatch");
        require(assetContracts.length == recipients.length, "Array lengths mismatch");
        require(assetIds.length <= 20, "Cannot transfer more than 20 NFTs at a time");

        for (uint256 i = 0; i < recipients.length; i++) {
            _transferNFT(assetContracts[i], assetIds[i], recipients[i], msg.sender);
        }
    }

    function _transferNFT(address assetContract, uint256 assetId, address recipient, address from) internal whenNotPaused {
        FacetERC721(assetContract).transferFrom(from, recipient, assetId);
        s().userOffersOnAssetValidAfterTime["Listing"][from][assetContract][assetId] = block.timestamp;
        s().userOffersOnAssetValidAfterTime["Bid"][recipient][assetContract][assetId] = block.timestamp;
    }

    function cancelOffer(bytes16 offerId) external {
        s().userOfferCancellations[msg.sender][offerId] = true;
        emit OfferCancelled(msg.sender, offerId);
    }

    function cancelAllOffersForAsset(string memory offerType, address assetContract, uint256 assetId) external {
        require(keccak256(bytes(offerType)) == keccak256(bytes("Listing")) || keccak256(bytes(offerType)) == keccak256(bytes("Bid")), "Invalid offer type");
        s().userOffersOnAssetValidAfterTime[offerType][msg.sender][assetContract][assetId] = block.timestamp;
        emit AllOffersOnAssetCancelledForUser(offerType, msg.sender, assetContract, assetId);
    }

    function cancelAllOffersOfUser(string memory offerType) external {
        require(keccak256(bytes(offerType)) == keccak256(bytes("Listing")) || keccak256(bytes(offerType)) == keccak256(bytes("Bid")), "Invalid offer type");
        s().userOffersValidAfterTime[offerType][msg.sender] = block.timestamp;
        emit AllOffersCancelledForUser(offerType, msg.sender);
    }

    function computeFee(uint256 amount) public view returns (uint256) {
        return (amount * s().feeBps) / 10000;
    }
    
    function _domainNameAndVersion() 
        internal
        pure
        override
        returns (string memory name, string memory version)
    {
        name = "FacetPort";
        version = "1";
    }
}
