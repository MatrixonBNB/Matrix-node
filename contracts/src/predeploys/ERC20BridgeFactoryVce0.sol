// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetOwnable.sol";
import "src/libraries/Pausable.sol";
import "src/libraries/Upgradeable.sol";
import "src/libraries/FacetERC20.sol";
import "./ERC20BridgeV1aa.sol";
import "solady/utils/LibString.sol";
import "solady/utils/Initializable.sol";
import "src/libraries/ERC1967Proxy.sol";
import "src/libraries/MigrationLib.sol";

contract ERC20BridgeFactoryVce0 is Ownable, Pausable, Upgradeable, Initializable {
    using LibString for *;
  
    event FactoryBridgedIn(address indexed to, uint256 amount, address smartContract, address dumbContract);
    event FactoryInitiateWithdrawal(address indexed from, uint256 amount, bytes32 withdrawalId, address smartContract, address dumbContract);
    event FactoryWithdrawalComplete(address indexed to, uint256 amount, bytes32 withdrawalId, address smartContract, address dumbContract);
    event BridgeCreated(address newBridge, address tokenSmartContract);

    struct ERC20BridgeFactoryStorage {
        address trustedSmartContract;
        mapping(address => address) bridgeDumbContractToTokenSmartContract;
        mapping(address => address) tokenSmartContractToBridgeDumbContract;
    }

    function s() internal pure returns (ERC20BridgeFactoryStorage storage fs) {
        bytes32 position = keccak256("ERC20BridgeFactoryStorage.contract.storage.v1");
        assembly {
            fs.slot := position
        }
    }

    function initialize(address trustedSmartContract) public initializer {
        require(trustedSmartContract != address(0), "Invalid smart contract");
        _initializeUpgradeAdmin(msg.sender);
        _initializeOwner(msg.sender);
        s().trustedSmartContract = trustedSmartContract;
    }

    modifier onlyTrustedSmartContract() {
        require(msg.sender == s().trustedSmartContract, "Only the trusted smart contract can call this function");
        _;
    }
    
    function bridgeDumbContractToTokenSmartContract(address bridgeDumbContract) public view returns (address) {
        return s().bridgeDumbContractToTokenSmartContract[bridgeDumbContract];
    }
    
    function tokenSmartContractToBridgeDumbContract(address tokenSmartContract) public view returns (address) {
        return s().tokenSmartContractToBridgeDumbContract[tokenSmartContract];
    }

    function bridgeIn(address tokenSmartContract, uint8 decimals, string memory symbol, string memory name, address to, uint256 amount) public onlyTrustedSmartContract {
        address bridge = findOrCreateBridge(tokenSmartContract, decimals, symbol, name);
        ERC20BridgeV1aa(bridge).bridgeIn(to, amount);
        emit FactoryBridgedIn(to, amount, tokenSmartContract, bridge);
    }

    function bridgeIntoExistingBridge(address tokenSmartContract, address to, uint256 amount) public onlyTrustedSmartContract {
        address bridge = s().tokenSmartContractToBridgeDumbContract[tokenSmartContract];
        require(bridge != address(0), "Bridge not found");
        ERC20BridgeV1aa(bridge).bridgeIn(to, amount);
        emit FactoryBridgedIn(to, amount, tokenSmartContract, bridge);
    }
    function findOrCreateBridge(
        address tokenSmartContract,
        uint8 decimals,
        string memory symbol,
        string memory name
    ) internal returns (address) {
        address existingBridge = s().tokenSmartContractToBridgeDumbContract[tokenSmartContract];
        if (existingBridge != address(0)) {
            return existingBridge;
        }

        bytes32 salt = keccak256(abi.encodePacked(tokenSmartContract));
        address implementationAddress = MigrationLib.predeployAddrFromName("ERC20BridgeV1aa");
        bytes memory initBytes = abi.encodeCall(
            ERC20BridgeV1aa.initialize,
            (tokenSmartContract, s().trustedSmartContract, string(abi.encodePacked("Facet ", name)), string(abi.encodePacked("f", symbol.upper())), decimals)
        );

        address bridge = address(new ERC1967Proxy{salt: salt}(implementationAddress, initBytes));
        require(s().bridgeDumbContractToTokenSmartContract[bridge] == address(0), "Bridge already exists");

        s().tokenSmartContractToBridgeDumbContract[tokenSmartContract] = bridge;
        s().bridgeDumbContractToTokenSmartContract[bridge] = tokenSmartContract;

        emit BridgeCreated(bridge, tokenSmartContract);
        return bridge;
    }

    function bridgeOut(address bridgeDumbContract, uint256 amount) public whenNotPaused {
        address smartContract = s().bridgeDumbContractToTokenSmartContract[bridgeDumbContract];
        require(smartContract != address(0), "Bridge not found");
        ERC20BridgeV1aa(bridgeDumbContract).bridgeOut(msg.sender, amount);
        emit FactoryInitiateWithdrawal(msg.sender, amount, keccak256(abi.encodePacked(block.number)), smartContract, bridgeDumbContract);
    }

    function markWithdrawalComplete(address to, bytes32 withdrawalId, address tokenSmartContract) public onlyTrustedSmartContract {
        address dumbContract = s().tokenSmartContractToBridgeDumbContract[tokenSmartContract];
        uint256 amount = ERC20BridgeV1aa(dumbContract).withdrawalIdAmount(withdrawalId);
        ERC20BridgeV1aa(dumbContract).markWithdrawalComplete(to, withdrawalId);
        emit FactoryWithdrawalComplete(to, amount, withdrawalId, tokenSmartContract, dumbContract);
    }

    function predictBridgeAddress(address tokenSmartContract, uint8 decimals, string memory symbol, string memory name) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(tokenSmartContract));
        address implementationAddress = MigrationLib.predeployAddrFromName("ERC20BridgeV1aa");
        bytes memory initBytes = abi.encodeCall(
            ERC20BridgeV1aa.initialize,
            (tokenSmartContract, s().trustedSmartContract, string(abi.encodePacked("Facet ", name)), string(abi.encodePacked("f", symbol.upper())), decimals)
        );

        bytes32 bytecodeHash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(implementationAddress, initBytes)
            ))
        ));

        return address(uint160(uint256(bytecodeHash)));
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
