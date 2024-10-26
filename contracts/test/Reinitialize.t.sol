// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {EthscriptionERC20BridgeV6e4} from "src/predeploys/EthscriptionERC20BridgeV6e4.sol";
import "src/libraries/ERC1967Proxy.sol";
import { console2 as console } from "forge-std/console2.sol";

contract ReinitializeTest is Test {
    EthscriptionERC20BridgeV6e4 public bridge;
    address constant deployer = address(1);
    
    function setUp() public {
        vm.startPrank(deployer);
        
        address bridgeImplementation = address(new EthscriptionERC20BridgeV6e4());
        bytes memory initData = abi.encodeCall(
            EthscriptionERC20BridgeV6e4.initialize,
            ("Test", "TEST", 1, address(1), 1000, false)
        );
        
        bridge = EthscriptionERC20BridgeV6e4(address(new ERC1967Proxy(bridgeImplementation, initData)));
    }

    function test_BridgeIn() public {
        bridge.bridgeIn(address(this), 1);
        assertEq(bridge.balanceOf(address(this)), 1 ether);
    }
    
    function test_Upgrade() public {
        bytes memory initData = abi.encodeCall(
            EthscriptionERC20BridgeV6e4.onUpgrade,
            (address(this), 1000)   
        );
        console.log("bridge.upgradeAdmin()", bridge.upgradeAdmin());
        bridge.upgradeToAndCall(address(new EthscriptionERC20BridgeV6e4()), initData);
    }
}
