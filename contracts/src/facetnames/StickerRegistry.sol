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

contract StickerRegistry is Upgradeable, Initializable, FacetOwnable, FacetEIP712 {
    using LibString for *;
    using SafeTransferLib for address;
    using ECDSA for bytes32;
        
    struct Sticker {
        address signer;
        string name;
        string description;
        string imageURI;
        uint256 expiry;
    }

    struct User {
        uint256[] stickerAry;
        mapping(uint256 => bool) stickerIdsAwardedMap;
    }

    struct StickerRegistryStorage {
        uint256 nextStickerId;
        mapping(address => User) users;
        mapping(uint256 => Sticker) stickers;
        mapping(address controller => bool isApproved) controllers;
    }
    
    event StickerCreated(uint256 indexed stickerId, string name, string description, string imageURI, uint256 stickerExpiry, address grantingAddress);
    event StickerClaimed(uint256 indexed stickerId, address indexed claimer);
    event StickerPlaced(uint256 indexed stickerId, uint256 indexed tokenId, uint256[2] position);
    event StickerRepositioned(uint256 indexed stickerId, uint256 indexed tokenId, uint256[2] position);
  
    function s() internal pure returns (StickerRegistryStorage storage cs) {
        bytes32 position = keccak256("NameRegistryStorage.contract.storage.v1");
        assembly {
            cs.slot := position
        }
    }
    
    function controllers(address controller) public view returns (bool) {
        return s().controllers[controller];
    }
    
    /// @notice Emitted when a Controller is added to the approved `controllers` mapping.
    ///
    /// @param controller The address of the approved controller.
    event ControllerAdded(address indexed controller);

    /// @notice Emitted when a Controller is removed from the approved `controllers` mapping.
    ///
    /// @param controller The address of the removed controller.
    event ControllerRemoved(address indexed controller);
    
    function addController(address controller) external onlyOwner {
        s().controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    /// @notice Revoke controller permission for an address.
    ///
    /// @dev Emits `ControllerRemoved(controller)` after removing the `controller` from the `controllers` mapping.
    ///
    /// @param controller The address of the controller to remove.
    function removeController(address controller) external onlyOwner {
        s().controllers[controller] = false;
        emit ControllerRemoved(controller);
    }
    
    /// @notice Decorator for restricting methods to only approved Controller callers.
    modifier onlyController() {
        require(s().controllers[msg.sender], "Only controllers can call this function");
        _;
    }
    
    constructor() EIP712() {
        _disableInitializers();
    }

    function initialize() public initializer {
        _initializeOwner(msg.sender);
        _initializeUpgradeAdmin(msg.sender);
    }

    function createSticker(
        string memory name, 
        string memory description, 
        string memory imageURI, 
        uint256 stickerExpiry, 
        address grantingAddress
    ) public onlyController {
        require(bytes(name).length > 0, "NNE");
        require(grantingAddress != address(0), "Granting address must be non-zero");
        
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
    
    function claimSticker(
        address originalSender,
        uint256 stickerId, 
        uint256 deadline, 
        uint256 tokenId, 
        uint256[2] memory position, 
        bytes memory signature
    ) public onlyController {
        User storage user = s().users[originalSender];
        require(!user.stickerIdsAwardedMap[stickerId], "Sticker already awarded");
        require(deadline > block.timestamp, "Deadline passed");
        require(
            s().stickers[stickerId].expiry > block.timestamp,
            "Sticker expired"
        );
        
        bytes memory message = abi.encode(
            keccak256("StickerClaim(uint256 stickerId,address claimer,uint256 deadline)"),
            stickerId,
            originalSender,
            deadline
        );
        
        verifySignatureAgainstNewAndOldChainId(message, signature, s().stickers[stickerId].signer);
        
        user.stickerIdsAwardedMap[stickerId] = true;
        user.stickerAry.push(stickerId);

        if (tokenId != 0) {
            placeSticker(stickerId, tokenId, position);
        }

        emit StickerClaimed(stickerId, originalSender);
    }

    function placeSticker(
        uint256 stickerId, 
        uint256 tokenId, 
        uint256[2] memory position
    ) public onlyController {
        emit StickerPlaced(stickerId, tokenId, position);
    }

    function repositionSticker(
        uint256 stickerIndex, 
        uint256 tokenId, 
        uint256[2] memory position
    ) public onlyController {
        emit StickerRepositioned(stickerIndex, tokenId, position);
    }
    
    function _domainNameAndVersion() 
        internal
        view
        override
        returns (string memory name, string memory version)
    {
        name = "Facet Cards";
        version = "1";
    }
}    
