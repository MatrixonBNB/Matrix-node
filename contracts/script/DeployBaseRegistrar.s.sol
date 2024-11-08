// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {BaseRegistrar} from "src/facetnames/BaseRegistrar.sol";
import {RegistrarController} from "src/facetnames/RegistrarController.sol";
import {NameEncoder} from "ens-contracts/utils/NameEncoder.sol";
import "src/facetnames/Constants.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract MockWETH is ERC20 {
    constructor() {
        // Maybe mint some initial supply to deployer
        _mint(msg.sender, 1000000 ether);
    }
    
    function name() public pure override returns (string memory) {
        return "Wrapped Ether";
    }
    
    function symbol() public pure override returns (string memory) {
        return "WETH";
    }

    // Optional: Add deposit/withdraw functions to mimic real WETH
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}

contract S is Script {
    using LibString for *;

    function _encodeName(string memory name) internal pure returns (string memory) {
        (, bytes32 node) = NameEncoder.dnsEncodeName(name);
        return uint256(node).toHexString(32);
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("FACET_ETH_NODE", _encodeName("facet.eth"));
        
        string memory l2ReverseLabelString = (0x80000000 | 8453).toHexStringNoPrefix();
        console.log(l2ReverseLabelString);
        console.log("FACET_REVERSE_NODE", _encodeName(l2ReverseLabelString.concat(".reverse"))); // _encodeName("80001325.reverse")
        
        (bytes memory dnsName,) = NameEncoder.dnsEncodeName("facet.eth");
        console.log("FACET_ETH_NAME", dnsName.toHexStringNoPrefix());

        uint256[] memory prices = new uint256[](6);
        prices[0] = 316_808_781_402;
        prices[1] = 31_680_878_140;
        prices[2] = 3_168_087_814;
        prices[3] = 316_808_781;
        prices[4] = 31_680_878;
        prices[5] = 3_168_087;
        
        ERC20 wethToken = new MockWETH();
        
        RegistrarController controller = new RegistrarController({
            owner_: deployerAddress,
            paymentReceiver_: deployerAddress,
            baseDomainName_: "facet.eth",
            prices_: prices,
            premiumStart_: 500 ether,
            totalDays_: 28 days,
            wethToken_: wethToken
        });

        vm.warp(1735689600);
        
        wethToken.approve(address(controller), 8 ether);
        
        RegistrarController.RegisterRequest memory request = RegistrarController.RegisterRequest({
            name: "tester12345",
            owner: msg.sender, // The user calling this function becomes the owner
            duration: 366 days,
            resolver: address(controller.resolver()),
            data: new bytes[](0),
            reverseRecord: true
        });
        
        controller.register(request);
        
        vm.stopBroadcast();
    }
}
