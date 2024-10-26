// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/libraries/FacetERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ILegacyMintableERC20, IOptimismMintableERC20 } from "src/interfaces/IOptimismMintableERC20.sol";

import { Upgradeable } from "src/libraries/Upgradeable.sol";

import "solady/src/utils/Initializable.sol";
import "src/libraries/FacetOwnable.sol";

/// @title OptimismMintableERC20
/// @notice OptimismMintableERC20 is a standard extension of the base ERC20 token contract designed
///         to allow the StandardBridge contracts to mint and burn tokens. This makes it possible to
///         use an OptimismMintablERC20 as the L2 representation of an L1 token, or vice-versa.
///         Designed to be backwards compatible with the older StandardL2ERC20 token which was only
///         meant for use on L2.
contract FacetOptimismMintableERC20 is IOptimismMintableERC20, ILegacyMintableERC20, FacetERC20, Initializable, Upgradeable, FacetOwnable {
    struct BridgeStorage {
        address _trustedSmartContract;
        mapping(bytes32 => uint256) _withdrawalIdAmount;
        mapping(address => bytes32) _userWithdrawalId;
        uint256 _withdrawalIdNonce;
        address _bridgeAndCallHelper;
        address _facetBuddyFactory;
        
        address remoteToken;
        address bridge;
    }
    
    function s() internal pure returns (BridgeStorage storage cs) {
        bytes32 position = keccak256("BridgeStorage.contract.storage.v1");
        assembly {
           cs.slot := position
        }
    }
    
    /// @notice Emitted whenever tokens are minted for an account.
    /// @param account Address of the account tokens are being minted for.
    /// @param amount  Amount of tokens minted.
    event Mint(address indexed account, uint256 amount);

    /// @notice Emitted whenever tokens are burned from an account.
    /// @param account Address of the account tokens are being burned from.
    /// @param amount  Amount of tokens burned.
    event Burn(address indexed account, uint256 amount);

    /// @notice A modifier that only allows the bridge to call
    modifier onlyBridge() {
        require(msg.sender == s().bridge, "OptimismMintableERC20: only bridge can mint and burn");
        _;
    }

    constructor() {
      _disableInitializers();
    }
    
    function initialize(
        address _bridge,
        address _remoteToken,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) public initializer {
        _initializeERC20(_name, _symbol, _decimals);
        _initializeUpgradeAdmin(msg.sender);
        _initializeOwner(msg.sender);
        
        setBridgeAndRemoteToken(_bridge, _remoteToken);
    }
    
    function setBridgeAndRemoteToken(address _bridge, address _remoteToken) public onlyOwner {
        s().bridge = _bridge;
        s().remoteToken = _remoteToken;
    }

    /// @notice Allows the StandardBridge on this network to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function mint(
        address _to,
        uint256 _amount
    )
        external
        virtual
        override(IOptimismMintableERC20, ILegacyMintableERC20)
        onlyBridge
    {
        _mint(_to, _amount);
        emit Mint(_to, _amount);
    }

    /// @notice Allows the StandardBridge on this network to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function burn(
        address _from,
        uint256 _amount
    )
        external
        virtual
        override(IOptimismMintableERC20, ILegacyMintableERC20)
        onlyBridge
    {
        _burn(_from, _amount);
        emit Burn(_from, _amount);
    }
    
    function selfBurn(uint256 _amount) external virtual {
        _burn(msg.sender, _amount);
        emit Burn(msg.sender, _amount);
    }

    /// @notice ERC165 interface check function.
    /// @param _interfaceId Interface ID to check.
    /// @return Whether or not the interface is supported by this contract.
    function supportsInterface(bytes4 _interfaceId) external pure virtual returns (bool) {
        bytes4 iface1 = type(IERC165).interfaceId;
        // Interface corresponding to the legacy L2StandardERC20.
        bytes4 iface2 = type(ILegacyMintableERC20).interfaceId;
        // Interface corresponding to the updated OptimismMintableERC20 (this contract).
        bytes4 iface3 = type(IOptimismMintableERC20).interfaceId;
        return _interfaceId == iface1 || _interfaceId == iface2 || _interfaceId == iface3;
    }

    /// @custom:legacy
    /// @notice Legacy getter for the remote token. Use REMOTE_TOKEN going forward.
    function l1Token() public view returns (address) {
        return s().remoteToken;
    }

    /// @custom:legacy
    /// @notice Legacy getter for the bridge. Use BRIDGE going forward.
    function l2Bridge() public view returns (address) {
        return s().bridge;
    }

    /// @custom:legacy
    /// @notice Legacy getter for REMOTE_TOKEN.
    function remoteToken() public view returns (address) {
        return s().remoteToken;
    }

    /// @custom:legacy
    /// @notice Legacy getter for BRIDGE.
    function bridge() public view returns (address) {
        return s().bridge;
    }
}
