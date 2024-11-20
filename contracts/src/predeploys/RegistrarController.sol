// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {StringUtils} from "ens-contracts/utils/StringUtils.sol";

import {BaseRegistrar} from "./BaseRegistrar.sol";
import {L2Resolver} from "./L2Resolver.sol";
import {IReverseRegistrar} from "src/facetnames/interface/IReverseRegistrar.sol";
import {Registry} from "./Registry.sol";
import {StablePriceOracle, IPriceOracle} from "src/facetnames/StablePriceOracle.sol";
import {ExponentialPremiumPriceOracle} from "./ExponentialPremiumPriceOracle.sol";
import {ReverseRegistrar} from "./ReverseRegistrar.sol";
import {NameEncoder} from "ens-contracts/utils/NameEncoder.sol";
import "./Constants.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ENS} from "ens-contracts/registry/ENS.sol";

import {Pausable} from "src/libraries/Pausable.sol";
import {ERC1967Proxy} from "src/libraries/ERC1967Proxy.sol";
import "solady/utils/Initializable.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {StickerRegistry} from "src/predeploys/StickerRegistry.sol";
import "src/libraries/MigrationLib.sol";

import {EventReplayable} from "src/libraries/EventReplayable.sol";

contract RegistrarController is Ownable, Pausable, Initializable, EventReplayable {
    using LibString for *;
    using StringUtils for *;
    using SafeERC20 for IERC20;
    
    ENS public registry;
    L2Resolver public resolver;
    ERC20 public wethToken;
    
    function setWethToken(address wethToken_) public onlyOwner {
        wethToken = ERC20(wethToken_);
    }

    struct RegisterRequest {
        string name;
        address owner;
        uint256 duration;
        address resolver;
        bytes[] data;
        bool reverseRecord;
    }

    BaseRegistrar public base;
    IPriceOracle public prices;
    IReverseRegistrar public reverseRegistrar;

    bytes32 public rootNode;
    string public rootName;
    
    mapping(uint256 => uint256) public v1TokenIdToV2TokenId;
    mapping(uint256 => uint256) public v2TokenIdToV1TokenId;
    uint256 public nextV1TokenId;
    
    bool public preregistrationComplete;
    StickerRegistry public stickerRegistry;
    
    uint256 public constant MIN_REGISTRATION_DURATION = 365 days;
    uint256 public constant MIN_NAME_LENGTH = 1;

    error NameNotAvailable(string name);
    error DurationTooShort(uint256 duration);
    error ResolverRequiredWhenDataSupplied();
    error InsufficientValue();
    error TransferFailed();

    event ETHPaymentProcessed(address indexed payee, uint256 price);

    event NameRegistered(
        string name,
        bytes32 indexed label,
        address indexed owner,
        uint256 baseCost,
        uint256 premium,
        uint256 expires
    );

    event NameRenewed(
        string name,
        bytes32 indexed label,
        uint256 cost,
        uint256 expires
    );

    event PriceOracleUpdated(address newPrices);

    event ReverseRegistrarUpdated(address newReverseRegistrar);
    
    modifier validRegistration(RegisterRequest memory request) {
        if (request.data.length > 0 && request.resolver == address(0)) {
            revert ResolverRequiredWhenDataSupplied();
        }
        if (!available(request.name)) {
            revert NameNotAvailable(request.name);
        }
        if (request.duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(request.duration);
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        IMPLEMENTATION                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        address owner_,
        uint256[] memory prices_,
        ERC20 wethToken_
    ) public initializer {
        wethToken = wethToken_;
        
        // Set up nodes and labels
        bytes32 facetNameLabel = keccak256("facet");
        bytes32 facetReverseLabel = keccak256("800face7");
        
        rootNode = FACET_ETH_NODE;
        rootName = ".facet.eth";
        
        _initializeOwner(owner_);

        address registryImplementation = MigrationLib.predeployAddrFromName("Registry");
        
        registry = Registry(address(new ERC1967Proxy(
            registryImplementation,
            abi.encodeWithSelector(
                Registry.initialize.selector,
                address(this)
            )
        )));
        
        address baseImplementation = MigrationLib.predeployAddrFromName("BaseRegistrar");
        
        base = BaseRegistrar(address(new ERC1967Proxy(
            baseImplementation,
            abi.encodeWithSelector(
                BaseRegistrar.initialize.selector,
                tokenName,
                tokenSymbol,
                registry,
                address(this),
                rootNode,
                "",
                ""
            )
        )));
        
        address priceOracleImplementation = MigrationLib.predeployAddrFromName("ExponentialPremiumPriceOracle");
        
        prices = ExponentialPremiumPriceOracle(address(new ERC1967Proxy(
            priceOracleImplementation,
            abi.encodeWithSelector(
                ExponentialPremiumPriceOracle.initialize.selector,
                prices_,
                500 ether,
                20 days
            )
        )));
        
        address reverseRegistrarImplementation = MigrationLib.predeployAddrFromName("ReverseRegistrar");
        
        reverseRegistrar = IReverseRegistrar(address(new ERC1967Proxy(
            reverseRegistrarImplementation,
            abi.encodeWithSelector(
                ReverseRegistrar.initialize.selector,
                registry,
                address(this),
                FACET_REVERSE_NODE
            )
        )));
        
        registry.setSubnodeOwner(0x0, keccak256("reverse"), address(this));
        registry.setSubnodeOwner(REVERSE_NODE, facetReverseLabel, address(reverseRegistrar));
        registry.setSubnodeOwner(REVERSE_NODE, keccak256("addr"), address(reverseRegistrar));
        
        reverseRegistrar.claim(owner());
        
        address resolverImplementation = MigrationLib.predeployAddrFromName("L2Resolver");
        
        bytes memory initData = abi.encodeWithSelector(
            L2Resolver.initialize.selector,
            address(registry),
            address(this),
            address(reverseRegistrar),
            owner()
        );
        
        resolver = L2Resolver(address(new ERC1967Proxy(resolverImplementation, initData)));
        
        registry.setSubnodeOwner(0x0, keccak256("eth"), address(this));
        registry.setSubnodeOwner(ETH_NODE, facetNameLabel, address(this));
        base.addController(address(this));
        ReverseRegistrar(address(reverseRegistrar)).setControllerApproval(address(this), true);
        
        registry.setResolver(rootNode, address(resolver));
        registry.setResolver(REVERSE_NODE, address(resolver));
        
        registry.setSubnodeOwner(ETH_NODE, facetNameLabel, address(base));
        
        registry.setSubnodeOwner(0x0, keccak256("eth"), owner());
        registry.setSubnodeOwner(0x0, keccak256("reverse"), owner());
        registry.setOwner(0x0, owner());
        
        ReverseRegistrar(address(reverseRegistrar)).transferOwnership(owner());
        base.transferOwnership(owner());
        
        address stickerRegistryImpl = MigrationLib.predeployAddrFromName("StickerRegistry");
        ERC1967Proxy proxy = new ERC1967Proxy(stickerRegistryImpl, "");
        
        stickerRegistry = StickerRegistry(address(proxy));
        stickerRegistry.initialize();
        stickerRegistry.addController(address(this));
        stickerRegistry.transferOwnership(owner());
        stickerRegistry.setUpgradeAdmin(owner());
    }
    
    function transferFrom(address from, address to, uint256 id) public {
        require(MigrationLib.isInMigration(), "Migration only");
        uint256 v2TokenId = v1TokenIdToV2TokenId[id];
        
        require(base.isApprovedOrOwner(msg.sender, v2TokenId), "Not approved");
        base.transferFrom(from, to, v2TokenId);
    }
    
    function setApprovalForAll(address operator, bool approved) public {
        require(MigrationLib.isInMigration(), "Migration only");
        base.controllerSetApprovalForAll(msg.sender, operator, approved);
    }
    
    function ownerOf(uint256 tokenId) public view returns (address) {
        return base.ownerOf(tokenId);
    }
    
    function balanceOf(address owner) public view returns (uint256) {
        return base.balanceOf(owner);
    }
    
    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return base.isApprovedForAll(owner, operator);
    }
    
    function isApprovedOrOwner(address spender, uint256 id) public view returns (bool) {
        return base.isApprovedOrOwner(spender, id);
    }
    
    function encodeName(string memory name) public pure returns (bytes32) {
        (, bytes32 node) = NameEncoder.dnsEncodeName(name);
        return node;
    }
    function setPriceOracle(IPriceOracle prices_) external onlyOwner {
        prices = prices_;
        emit PriceOracleUpdated(address(prices_));
    }

    function setReverseRegistrar(IReverseRegistrar reverse_) external onlyOwner {
        reverseRegistrar = reverse_;
        emit ReverseRegistrarUpdated(address(reverse_));
    }

    function valid(string memory name) public pure returns (bool) {
        return name.strlen() >= MIN_NAME_LENGTH;
    }

    function available(string memory name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.isAvailable(uint256(label));
    }

    function rentPrice(string memory name, uint256 duration) public view returns (IPriceOracle.Price memory price) {
        bytes32 label = keccak256(bytes(name));
        price = prices.price(name, _getExpiry(uint256(label)), duration);
    }

    function registerPrice(string memory name, uint256 duration) public view returns (uint256) {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        return price.base + price.premium;
    }

    function register(RegisterRequest memory request) public validRegistration(request) {
        uint256 price = registerPrice(request.name, request.duration);

        _transferPayment(price);
        
        if (MigrationLib.isInMigration()) {
            request.duration += 30 days;
        }

        _register(request, price);
    }

    function renew(string calldata name, uint256 duration) external {
        bytes32 labelhash = keccak256(bytes(name));
        uint256 tokenId = uint256(labelhash);
        IPriceOracle.Price memory price = rentPrice(name, duration);

        _transferPayment(price.base);

        uint256 expires = base.renew(tokenId, duration);

        emit NameRenewed(name, labelhash, price.base, expires);
    }

    function _transferPayment(uint256 price) internal {
        wethToken.transferFrom(msg.sender, address(this), price);
        emit ETHPaymentProcessed(msg.sender, price);
    }

    function _getExpiry(uint256 tokenId) internal view returns (uint256 expires) {
        expires = base.nameExpires(tokenId);
        return expires + GRACE_PERIOD;
    }

    function _register(RegisterRequest memory request, uint256 baseCost) internal {
        uint256 v2TokenId = uint256(keccak256(bytes(request.name)));
        nextV1TokenId++;
        v1TokenIdToV2TokenId[nextV1TokenId] = v2TokenId;
        v2TokenIdToV1TokenId[v2TokenId] = nextV1TokenId;
        
        uint256 expires = base.registerWithRecord(
            v2TokenId, request.owner, request.duration, request.resolver, 0
        );

        if (request.data.length > 0) {
            _setRecords(request.resolver, keccak256(bytes(request.name)), request.data);
        }

        if (request.reverseRecord) {
            _setReverseRecord(request.name, request.resolver, msg.sender);
        }
        
        recordAndEmitEvent(
            "NameRegistered(string,bytes32,address,uint256,uint256,uint256)",
            abi.encode(keccak256(bytes(request.name)), request.owner),
            abi.encode(request.name, baseCost, 0, expires)
        );
    }

    function _setRecords(address resolverAddress, bytes32 label, bytes[] memory data) internal {
        bytes32 nodehash = keccak256(abi.encodePacked(rootNode, label));
        L2Resolver resolver = L2Resolver(resolverAddress);
        resolver.multicallWithNodeCheck(nodehash, data);
    }

    function _setReverseRecord(string memory name, address resolver, address owner) internal {
        reverseRegistrar.setNameForAddr(msg.sender, owner, resolver, string.concat(name, rootName));
    }

    function recoverFunds(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }
    
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
    
    function importFromPreregistration(
        string[] memory names,
        address[] memory owners,
        uint256[] memory durations
    ) public onlyOwner {
        require(!preregistrationComplete, "Preregistration must not be complete");
        require(names.length == owners.length, "Names and owners must be the same length");
        require(names.length == durations.length, "Names and durations must be the same length");
        
        for (uint256 i = 0; i < names.length; i++) {
            RegisterRequest memory request = RegisterRequest({
                name: names[i],
                owner: owners[i],
                duration: durations[i],
                resolver: address(resolver),
                data: new bytes[](0),
                reverseRecord: false
            });
            
            _register(request, 0);
            
            if (!hasReverseRecord(owners[i])) {
                reverseRegistrar.setNameForAddr(
                    owners[i],
                    owners[i],
                    address(resolver),
                    string.concat(names[i], rootName)
                );
            }
            
            bytes32 node = encodeName(names[i].concat(rootName));
            resolver.setAddr(node, owners[i]);
        }
    }
    
    function ownerOfName(string memory name) public view returns (address) {
        uint256 tokenId = uint256(keccak256(bytes(name)));
        
        if (MigrationLib.isInMigration()) {
            tokenId = v2TokenIdToV1TokenId[tokenId];
        }
        
        return base.ownerOf(tokenId);
    }
    
    function hasReverseRecord(address addr) public view returns (bool) {
        address resolverAddress = registry.resolver(REVERSE_NODE);
        bytes32 node = reverseRegistrar.node(addr);
        
        if (resolverAddress == address(0)) return false;
        
        // Check if there's a name set in the resolver
        string memory name = L2Resolver(resolverAddress).name(node);
        if (bytes(name).length == 0) return false;
        
        bytes32 forwardNode = encodeName(name);
        address resolvedAddress = L2Resolver(resolver).addr(forwardNode);
        
        return resolvedAddress == addr;
    }
    
    function setPrimaryName(string memory name) public {
        string memory fullName = string.concat(name, rootName);

        bytes32 nameNode = encodeName(fullName);
        address owner = registry.owner(nameNode);
        
        address tokenOwner = ownerOfName(name);
        
        require(owner == msg.sender || tokenOwner == msg.sender, "Not the owner");
        
        _setReverseRecord(name, address(resolver), msg.sender);
    }
    
    event UpgradeAdminChanged(address indexed newUpgradeAdmin);
    function setUpgradeAdmin(address newUpgradeAdmin) public {
        if (MigrationLib.isInMigration()) {
            emit UpgradeAdminChanged(newUpgradeAdmin);
        } else {
            revert("Contract not upgradeable");
        }
    }
    
    function markPreregistrationComplete() public onlyOwner {
        preregistrationComplete = true;
    }
    
    function setCardDetails(
        uint256 tokenId,
        string memory displayName,
        string memory bio,
        string memory imageURI,
        string[] memory links
    ) public {
        if (MigrationLib.isInMigration()) {
            tokenId = v1TokenIdToV2TokenId[tokenId];
        }
        
        bytes32 label = bytes32(tokenId);
        bytes32 subnode = keccak256(abi.encodePacked(rootNode, label));
        address owner = registry.owner(subnode);
        
        address tokenOwner = base.ownerOf(tokenId);
        
        require(owner == msg.sender || tokenOwner == msg.sender, "Not the owner");
        
        // Call resolver methods to set each text record
        resolver.setText(subnode, "alias", displayName);
        resolver.setText(subnode, "description", bio);
        resolver.setText(subnode, "avatar", imageURI);
        
        // Set links using url, url2, url3, etc.
        for (uint i = 0; i < links.length; i++) {
            string memory key = i == 0 ? "url" : string.concat("url", (i + 1).toString());
            resolver.setText(subnode, key, links[i]);
        }
    }
    
    function registerNameWithPayment(address to, string memory name, uint256 durationInSeconds) public {
        // Set reverse record only if:
        // 1. User is registering for themselves (to == msg.sender)
        // 2. They don't already have a reverse record
        bool setReverseRecord = (to == msg.sender && !hasReverseRecord(msg.sender));
        
        RegisterRequest memory request = RegisterRequest({
            name: name,
            owner: to,
            duration: durationInSeconds,
            resolver: address(resolver),  // Need resolver for reverse record
            data: new bytes[](0),
            reverseRecord: setReverseRecord
        });
        
        register(request);
        bytes32 node = encodeName(name.concat(rootName));
        resolver.setAddr(node, to);
    }
       
    function withdrawWETH() public onlyOwner {
        uint256 amount = ERC20(wethToken).balanceOf(address(this));
        wethToken.transfer(owner(), amount);
    }

    function placeSticker(uint256 stickerId, uint256 tokenId, uint256[2] memory position) public {
        stickerRegistry.placeSticker(stickerId, tokenId, position);
    }
    
    function repositionSticker(uint256 stickerIndex, uint256 tokenId, uint256[2] memory position) public {
        stickerRegistry.repositionSticker(stickerIndex, tokenId, position);
    }
    
    function claimSticker(uint256 stickerId, uint256 deadline, uint256 tokenId, uint256[2] memory position, bytes memory signature) public {
        stickerRegistry.claimSticker(
            msg.sender,
            stickerId,
            deadline,
            tokenId,
            position,
            signature
        );
    }
    
    function createSticker(string memory name, string memory description, string memory imageURI, uint256 stickerExpiry, address grantingAddress) public {
        stickerRegistry.createSticker(
            name,
            description,
            imageURI,
            stickerExpiry,
            grantingAddress
        );
    }

    event ContractUpgraded(address indexed newImplementation);
    function upgrade(bytes32 newHash, string calldata newSource) external {
        emit ContractUpgraded(address(0));
    }
}
