// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "solady/utils/SafeTransferLib.sol";
import "solady/utils/Initializable.sol";
import "solady/utils/Base64.sol";
import "solady/utils/LibString.sol";
import "solady/utils/ECDSA.sol";
import "src/libraries/Upgradeable.sol";
import "src/libraries/Pausable.sol";
import "src/libraries/FacetERC20.sol";
import "src/libraries/FacetERC721.sol";
import "src/libraries/FacetOwnable.sol";
import "src/libraries/FacetERC2981.sol";
import "src/libraries/FacetEIP712.sol";

contract NameRegistryV2f5 is FacetERC721, FacetERC2981, Upgradeable, Initializable, FacetOwnable, Pausable, FacetEIP712 {
    using LibString for *;
    using SafeTransferLib for address;
    using ECDSA for bytes32;
        
    struct Card {
        string displayName;
        string bio;
        string imageURI;
        string[] links;
    }

    struct Sticker {
        address signer;
        string name;
        string description;
        string imageURI;
        uint256 expiry;
    }

    struct StickerPosition {
        uint256 stickerId;
        uint256 xPosition;
        uint256 yPosition;
    }

    struct User {
        uint256 primaryNameTokenId;
        uint256[] stickerAry;
        mapping(uint256 => bool) stickerIdsAwardedMap;
    }

    struct Token {
        string name;
        uint256 expiry;
        uint256 registrationTimestamp;
        StickerPosition[] stickerPositions;
        Card cardDetails;
        mapping(uint256 => bool) stickerIdsPlacedMap;
    }

    struct NameRegistryStorage {
        address WETH;
        uint256 usdWeiCentsInOneEth;
        uint256 minRegistrationDuration;
        uint256 gracePeriod;
        uint256 maxNameLength;
        uint256[] charCountToUsdWeiCentsPrice;
        bool preregistrationComplete;
        uint256 nextTokenId;

        uint256 maxImportBatchSize;
        
        string cardTemplate;
        uint256 nextStickerId;
        uint256 maxStickersPerUser;
        uint256 maxStickersPerCard;
        uint256 maxLinksPerCard;
        uint256 bioMaxLength;
        uint256 displayNameMaxLength;
        uint256 uriMaxLength;
        
        mapping(string => uint256) nameToTokenId;
        
        mapping(uint256 => Token) tokens;
        mapping(address => User) users;
        mapping(uint256 => Sticker) stickers;
    }
    
    event NameRegistered(uint256 indexed tokenId, address indexed owner, string name, uint256 expires);
    event NameRenewed(uint256 indexed tokenId, uint256 newExpiry);
    event PrimaryNameSet(address indexed user, uint256 indexed tokenId);
    event ConversionRateUpdate(uint256 newRate);
    
    event StickerCreated(uint256 indexed stickerId, string name, string description, string imageURI, uint256 stickerExpiry, address grantingAddress);
    event StickerClaimed(uint256 indexed stickerId, address indexed claimer);
    event StickerPlaced(uint256 indexed stickerId, uint256 indexed tokenId, uint256[2] position);
    event StickerRepositioned(uint256 indexed stickerId, uint256 indexed tokenId, uint256[2] position);
    event CardDetailsSet(uint256 indexed tokenId, string displayName, string bio, string imageURI, string[] links);


    function s() internal pure returns (NameRegistryStorage storage cs) {
        bytes32 position = keccak256("NameRegistryStorage.contract.storage.v1");
        assembly {
            cs.slot := position
        }
    }
    
    constructor() EIP712() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address owner,
        uint256 usdWeiCentsInOneEth,
        uint256[] memory charCountToUsdWeiCentsPrice,
        string memory cardTemplate,
        address _WETH
    ) public initializer {
        require(charCountToUsdWeiCentsPrice.length >= 4);
        require(charCountToUsdWeiCentsPrice.length <= 10);
        _initializeERC721(name, symbol);
        _initializeOwner(owner);
        _initializePausable(true);
        _initializeUpgradeAdmin(msg.sender);
        s().WETH = _WETH;
        s().usdWeiCentsInOneEth = usdWeiCentsInOneEth;
        s().charCountToUsdWeiCentsPrice = charCountToUsdWeiCentsPrice;
        s().maxNameLength = 32;
        s().gracePeriod = 90 days;
        s().minRegistrationDuration = 28 days;
        s().nextTokenId = 1;
        s().nextStickerId = 1;
        s().maxImportBatchSize = 10;
        
        s().maxStickersPerUser = 25;
        s().maxStickersPerCard = s().maxStickersPerUser;
        s().maxLinksPerCard = 5;
        s().bioMaxLength = 1000;
        s().displayNameMaxLength = 100;
        s().uriMaxLength = 96000;
        require(bytes(cardTemplate).length <= s().uriMaxLength, "c");
        s().cardTemplate = cardTemplate;
    }

    function registerNameWithPayment(address to, string memory name, uint256 durationInSeconds) public whenNotPaused {
        require(s().preregistrationComplete, "P");
        require(durationInSeconds >= s().minRegistrationDuration, "D");
        _registerName(to, name, durationInSeconds);
        
        // Update user's primary name token ID if necessary
        if (to == msg.sender && s().users[msg.sender].primaryNameTokenId == 0) {
            uint256 tokenId = s().nameToTokenId[name];
            s().users[msg.sender].primaryNameTokenId = tokenId;
        }
        
        // Transfer payment
        s().WETH.safeTransferFrom(msg.sender, address(this), getPrice(name, durationInSeconds));
    }

    function renewNameWithPayment(string memory name, uint256 durationInSeconds) public whenNotPaused {
        _renewName(name, durationInSeconds);
        s().WETH.safeTransferFrom(msg.sender, address(this), getPrice(name, durationInSeconds));
    }
    
    function _registerName(address to, string memory name, uint256 durationInSeconds) internal {
        require(nameAvailable(name), "Name not available");
        require(nameIsValid(name), "Invalid name");
        uint256 tokenId = s().nameToTokenId[name];
        if (_exists(tokenId)) {
            _burn(tokenId);
        } else {
            tokenId = s().nextTokenId;
            s().nextTokenId += 1;
        }
        _mint(to, tokenId);
        s().nameToTokenId[name] = tokenId;
        
        Token storage token = s().tokens[tokenId];
        token.name = name;
        token.expiry = block.timestamp + durationInSeconds;
        token.registrationTimestamp = block.timestamp;
        token.stickerPositions = new StickerPosition[](0);
        token.cardDetails = Card("", "", "", new string[](0));

        emit NameRegistered(tokenId, to, name, s().tokens[tokenId].expiry);
    }

    function _renewName(string memory name, uint256 durationInSeconds) internal {
        uint256 tokenId = s().nameToTokenId[name];
        uint256 currentExpiry = s().tokens[tokenId].expiry;
        require(currentExpiry + s().gracePeriod >= block.timestamp, "Must be registered or in grace period");
        s().tokens[tokenId].expiry = currentExpiry + durationInSeconds;
        emit NameRenewed(tokenId, s().tokens[tokenId].expiry);
    }

    function markPreregistrationComplete() public onlyOwner {
        s().preregistrationComplete = true;
    }

    function importFromPreregistration(string[] memory names, address[] memory owners, uint256[] memory durations) public onlyOwner {
        require(!s().preregistrationComplete, "Preregistration must not be complete");
        require(names.length == owners.length, "Names and owners must be the same length");
        require(names.length == durations.length, "Names and owners must be the same length");
        require(names.length <= s().maxImportBatchSize, "Cannot import more than 10 names at a time");
        for (uint256 i = 0; i < names.length; i++) {
            _registerName(owners[i], names[i], durations[i]);
            if (s().users[owners[i]].primaryNameTokenId == 0) {
                uint256 tokenId = s().nameToTokenId[names[i]];
                s().users[owners[i]].primaryNameTokenId = tokenId;
            }
        }
    }
    
    function getCardStickers(uint256 tokenId) public view returns (StickerPosition[] memory positions, Sticker[] memory stickers) {
        enforceNotExpired(tokenId);
        Token storage token = s().tokens[tokenId];
        uint256 length = token.stickerPositions.length;

        StickerPosition[] memory positionsTemp = new StickerPosition[](length);
        Sticker[] memory stickersTemp = new Sticker[](length);

        uint256 count = 0;
        for (uint256 i = 0; i < length; i++) {
            StickerPosition storage position = token.stickerPositions[i];
            Sticker storage sticker = s().stickers[position.stickerId];
            if (sticker.expiry > block.timestamp) {
                positionsTemp[count] = position;
                stickersTemp[count] = sticker;
                count++;
            }
        }

        positions = new StickerPosition[](count);
        stickers = new Sticker[](count);
        for (uint256 i = 0; i < count; i++) {
            positions[i] = positionsTemp[i];
            stickers[i] = stickersTemp[i];
        }
    }
    
    function renderCard(uint256 tokenId) public view returns (string memory) {
        enforceNotExpired(tokenId);
        address owner = ownerOf(tokenId);
        Token storage token = s().tokens[tokenId];
        Card storage card = token.cardDetails;

        (StickerPosition[] memory positions, Sticker[] memory stickers) = getCardStickers(tokenId);

        string memory stickerIdsStr = "[";
        string memory stickerXPositionsStr = "[";
        string memory stickerYPositionsStr = "[";
        string memory stickerImageURIsStr = "[";
        for (uint256 i = 0; i < positions.length; i++) {
            stickerIdsStr = stickerIdsStr.concat(positions[i].stickerId.toString());
            stickerXPositionsStr = stickerXPositionsStr.concat(positions[i].xPosition.toString());
            stickerYPositionsStr = stickerYPositionsStr.concat(positions[i].yPosition.toString());
            stickerImageURIsStr = stickerImageURIsStr.concat(stickers[i].imageURI.escapeJSON(true));
            
            if (i < positions.length - 1) {
                stickerIdsStr = stickerIdsStr.concat(",");
                stickerXPositionsStr = stickerXPositionsStr.concat(",");
                stickerYPositionsStr = stickerYPositionsStr.concat(",");
                stickerImageURIsStr = stickerImageURIsStr.concat(",");
            }
        }
        stickerIdsStr = stickerIdsStr.concat("]");
        stickerXPositionsStr = stickerXPositionsStr.concat("]");
        stickerYPositionsStr = stickerYPositionsStr.concat("]");
        stickerImageURIsStr = stickerImageURIsStr.concat("]");

        string memory storageData = string(abi.encodePacked(
            '{"tokenId":"', tokenId.toString(), '","owner":"', owner.toHexString(), '","name":"', token.name.escapeJSON(), '","stickerIds":', stickerIdsStr, ',"stickerXPositions":', stickerXPositionsStr, ',"stickerYPositions":', stickerYPositionsStr, ',"stickerImages":', stickerImageURIsStr, ',"displayName":"', card.displayName.escapeJSON(), '","bio":"', card.bio.escapeJSON(), '","imageURI":"', card.imageURI.escapeJSON(), '","links":', arrayToString(card.links), '}'
        ));
        string memory template = s().cardTemplate;
        return string(abi.encodePacked(
            "<script>window.s=", storageData, ";document.open();document.write('", template, "');document.close();</script>"
        ));
    }
    
    function arrayToString(string[] memory array) internal pure returns (string memory) {
        string memory result = "[";
        for (uint256 i = 0; i < array.length; i++) {
            result = result.concat(array[i].escapeJSON(true));
            if (i < array.length - 1) {
                result = result.concat(",");
            }
        }
        return result.concat("]");
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_exists(id), "ERC721Metadata: URI query for nonexistent token");
        enforceNotExpired(id);

        Token storage token = s().tokens[id];
        string memory name = token.name;
        string memory card = renderCard(id);
        string memory b64Card = string(abi.encodePacked("data:text/html;charset=utf-8;base64,", Base64.encode(bytes(card))));

        // Create attributes array
        string memory attributes = string(abi.encodePacked(
            '[{"display_type":"number","trait_type":"Length","value":', bytes(name).length.toString(), '},',
            '{"display_type":"date","trait_type":"Expiration Date","value":', token.expiry.toString(), '},',
            '{"display_type":"date","trait_type":"Registration Date","value":', token.registrationTimestamp.toString(), '}]'
        ));

        // Create JSON data
        string memory json_data = string(abi.encodePacked(
            '{"name":"', name.escapeJSON(), '",',
            '"description":"', name.escapeJSON(), ', a Facet Name name.",',
            '"animation_url":"', b64Card, '",',
            '"attributes":', attributes, '}'
        ));

        return string(abi.encodePacked("data:application/json,", json_data));
    }

    function _burn(uint256 id) internal override {
        address owner = ownerOf(id);
        if (s().users[owner].primaryNameTokenId == id) {
            s().users[owner].primaryNameTokenId = 0;
        }
        
        _clearCardPersonalInfo(id);
        super._burn(id);
    }

    function transferFrom(address from, address to, uint256 id) public payable override {
        if (s().users[from].primaryNameTokenId == id) {
            s().users[from].primaryNameTokenId = 0;
        }
        
        _clearCardPersonalInfo(id);
        super.transferFrom(from, to, id);
    }
    
    function _clearCardPersonalInfo(uint256 tokenId) internal {
        _clearCardDetails(tokenId);
        _clearStickers(tokenId);
    }

    function _clearCardDetails(uint256 tokenId) internal {
        delete s().tokens[tokenId].cardDetails;
    }
    
    function _clearStickers(uint256 tokenId) internal {
        Token storage token = s().tokens[tokenId];
        for (uint256 i = 0; i < token.stickerPositions.length; i++) {
            uint256 stickerId = token.stickerPositions[i].stickerId;
            token.stickerIdsPlacedMap[stickerId] = false;
        }
        delete token.stickerPositions;
    }

    function enforceNotExpired(uint256 id) internal view {
        bool expiresInFuture = s().tokens[id].expiry > block.timestamp;
        require(expiresInFuture, "Name expired");
    }

    function ownerOf(uint256 id) public view override returns (address) {
        address owner = super.ownerOf(id);
        enforceNotExpired(id);
        return owner;
    }

    function lookupAddress(address user) public view returns (string memory) {
        uint256 candidateId = s().users[user].primaryNameTokenId;
        require(ownerOf(candidateId) == user, "Not the owner");
        return s().tokens[candidateId].name;
    }

    function setPrimaryName(string memory name) public {
        uint256 tokenId = s().nameToTokenId[name];
        require(msg.sender == ownerOf(tokenId), "Not the owner");
        s().users[msg.sender].primaryNameTokenId = tokenId;
        emit PrimaryNameSet(msg.sender, tokenId);
    }

    function resolveName(string memory name) public view returns (address) {
        uint256 tokenId = s().nameToTokenId[name];
        return ownerOf(tokenId);
    }

    function nameIsValid(string memory name) public view returns (bool) {
        return bytes(name).length <= s().maxNameLength &&
            name.is7BitASCII(LibString.ALPHANUMERIC_7_BIT_ASCII) &&
            name.eq(name.lower());
    }

    function nameAvailable(string memory name) public view returns (bool) {
        uint256 tokenId = s().nameToTokenId[name];
        if (!_exists(tokenId)) {
            return true;
        }
        return s().tokens[tokenId].expiry + s().gracePeriod < block.timestamp;
    }

    function getPrice(string memory name, uint256 durationInSeconds) public view returns (uint256) {
        uint256 len = bytes(name).length;
        uint256 priceWeiCentsPerSecond = len >= s().charCountToUsdWeiCentsPrice.length ? s().charCountToUsdWeiCentsPrice[s().charCountToUsdWeiCentsPrice.length - 1] : s().charCountToUsdWeiCentsPrice[len - 1];
        uint256 totalPriceWeiCents = priceWeiCentsPerSecond * durationInSeconds;
        return (totalPriceWeiCents * 1 ether) / s().usdWeiCentsInOneEth;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setUsdWeiCentsInOneEth(uint256 rate) public onlyOwner {
        s().usdWeiCentsInOneEth = rate;
        emit ConversionRateUpdate(rate);
    }

    function withdrawWETH() public onlyOwner {
        uint256 amount = ERC20(s().WETH).balanceOf(address(this));
        s().WETH.safeTransfer(owner(), amount);
    }

    function totalSupply() public view returns (uint256) {
        return s().nextTokenId - 1;
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
    
    function createSticker(string memory name, string memory description, string memory imageURI, uint256 stickerExpiry, address grantingAddress) public whenNotPaused {
        require(bytes(name).length > 0, "NNE");
        require(bytes(name).length <= s().displayNameMaxLength, "NTL");
        require(bytes(description).length <= s().bioMaxLength, "DTL");
        require(bytes(imageURI).length <= s().uriMaxLength, "ITL");
        require(grantingAddress != address(0), "Granting address must be non-zero");
            
        stickerManager.controllerCreateSticker(
            msg.sender,
            name,
            description,
            imageURI,
            stickerExpiry,
            grantingAddress
        );
            
        uint256 currentId = s().nextStickerId;
        s().nextStickerId += 1;

        Sticker storage newSticker = s().stickers[currentId];
        newSticker.name = name;
        newSticker.description = description;
        newSticker.imageURI = imageURI;
        newSticker.expiry = stickerExpiry;
        newSticker.signer = grantingAddress;

        emit StickerCreated(currentId, name, description, imageURI, stickerExpiry, grantingAddress);
    }
    
    function claimSticker(uint256 stickerId, uint256 deadline, uint256 tokenId, uint256[2] memory position, bytes memory signature) public whenNotPaused {
        User storage user = s().users[msg.sender];
        require(!user.stickerIdsAwardedMap[stickerId], "Sticker already awarded");
        require(user.stickerAry.length < s().maxStickersPerUser, "Too many stickers");
        require(deadline > block.timestamp, "Deadline passed");
        require(
            s().stickers[stickerId].expiry > block.timestamp,
            "Sticker expired"
        );
        
        stickerManager.controllerClaimSticker(
            msg.sender,
            stickerId,
            deadline,
            signature
        );
        
        bytes memory message = abi.encode(
            keccak256("StickerClaim(uint256 stickerId,address claimer,uint256 deadline)"),
            stickerId,
            msg.sender,
            deadline
        );
        
        verifySignatureAgainstNewAndOldChainId(message, signature, s().stickers[stickerId].signer);
        
        user.stickerIdsAwardedMap[stickerId] = true;
        user.stickerAry.push(stickerId);

        if (tokenId != 0) {
            placeSticker(stickerId, tokenId, position);
        }

        emit StickerClaimed(stickerId, msg.sender);
    }

    function placeSticker(uint256 stickerId, uint256 tokenId, uint256[2] memory position) public whenNotPaused {
        enforceNotExpired(tokenId);
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        
        User storage user = s().users[msg.sender];
        Token storage token = s().tokens[tokenId];
        
        require(user.stickerIdsAwardedMap[stickerId], "Sticker not claimed");
        require(!token.stickerIdsPlacedMap[stickerId], "Sticker already placed");
        require(token.stickerPositions.length < s().maxStickersPerCard, "Too many stickers");
        
        token.stickerPositions.push(StickerPosition(stickerId, position[0], position[1]));
        token.stickerIdsPlacedMap[stickerId] = true;
        
        emit StickerPlaced(stickerId, tokenId, position);
    }

    function repositionSticker(uint256 stickerIndex, uint256 tokenId, uint256[2] memory position) public whenNotPaused {
        enforceNotExpired(tokenId);
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        
        Token storage token = s().tokens[tokenId];
        StickerPosition storage stickerPosition = token.stickerPositions[stickerIndex];
        
        require(token.stickerIdsPlacedMap[stickerPosition.stickerId], "Sticker not placed");
        
        stickerPosition.xPosition = position[0];
        stickerPosition.yPosition = position[1];
        
        emit StickerRepositioned(stickerPosition.stickerId, tokenId, position);
    }
    
    function setCardDetails(uint256 tokenId, string memory displayName, string memory bio, string memory imageURI, string[] memory links) public whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        require(links.length <= s().maxLinksPerCard, "Too many links");
        require(bytes(bio).length <= s().bioMaxLength, "Bio too long");
        require(bytes(displayName).length <= s().displayNameMaxLength, "Display name too long");
        require(bytes(imageURI).length <= s().uriMaxLength, "ImageURI too long");

        Token storage token = s().tokens[tokenId];
        token.cardDetails.displayName = displayName;
        token.cardDetails.bio = bio;
        token.cardDetails.imageURI = imageURI;
        token.cardDetails.links = links;

        emit CardDetailsSet(tokenId, displayName, bio, imageURI, links);
    }
    
    function getCardDetails(uint256 tokenId) public view returns (string memory displayName, string memory bio, string memory imageURI, string[] memory links) {
        enforceNotExpired(tokenId);
        return (s().tokens[tokenId].cardDetails.displayName, s().tokens[tokenId].cardDetails.bio, s().tokens[tokenId].cardDetails.imageURI, s().tokens[tokenId].cardDetails.links);
    }

    function updateCardTemplate(string memory cardTemplate) public onlyOwner {
        s().cardTemplate = cardTemplate;
    }
    
    function _domainNameAndVersion() 
        internal
        view
        override
        returns (string memory name, string memory version)
    {
        string memory collectionName = _FacetERC721Storage().name;
        
        if (collectionName.eq("Facet Names")) {
            name = "Facet Cards";
        } else {
            name = collectionName;
        }
        
        version = "1";
    }
    
    function preregistrationComplete() external view returns (bool) {
        return s().preregistrationComplete;
    }

    function nextTokenId() external view returns (uint256) {
        return s().nextTokenId;
    }

    function maxImportBatchSize() external view returns (uint256) {
        return s().maxImportBatchSize;
    }

    function cardTemplate() external view returns (string memory) {
        return s().cardTemplate;
    }

    function nextStickerId() external view returns (uint256) {
        return s().nextStickerId;
    }

    function maxStickersPerUser() external view returns (uint256) {
        return s().maxStickersPerUser;
    }

    function maxStickersPerCard() external view returns (uint256) {
        return s().maxStickersPerCard;
    }

    function maxLinksPerCard() external view returns (uint256) {
        return s().maxLinksPerCard;
    }

    function bioMaxLength() external view returns (uint256) {
        return s().bioMaxLength;
    }

    function displayNameMaxLength() external view returns (uint256) {
        return s().displayNameMaxLength;
    }

    function uriMaxLength() external view returns (uint256) {
        return s().uriMaxLength;
    }

    function WETH() external view returns (address) {
        return s().WETH;
    }

    function usdWeiCentsInOneEth() external view returns (uint256) {
        return s().usdWeiCentsInOneEth;
    }

    function minRegistrationDuration() external view returns (uint256) {
        return s().minRegistrationDuration;
    }

    function gracePeriod() external view returns (uint256) {
        return s().gracePeriod;
    }

    function maxNameLength() external view returns (uint256) {
        return s().maxNameLength;
    }

    function charCountToUsdWeiCentsPrice() external view returns (uint256[] memory) {
        return s().charCountToUsdWeiCentsPrice;
    }
    
    function nameToTokenId(string memory name) external view returns (uint256) {
        return s().nameToTokenId[name];
    }

    function getToken(uint256 id) external view returns (
        string memory name,
        uint256 expiry,
        uint256 registrationTimestamp,
        StickerPosition[] memory stickerPositions
    ) {
        Token storage token = s().tokens[id];
        return (token.name, token.expiry, token.registrationTimestamp, token.stickerPositions);
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC2981, ERC721) returns (bool) {
        return 
            ERC2981.supportsInterface(interfaceId) || 
            ERC721.supportsInterface(interfaceId);
    }
}
