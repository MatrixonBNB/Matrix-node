// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "src/libraries/MigrationLib.sol";
import "src/libraries/FacetERC20.sol";

contract YourToken is FacetERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _initializeERC20(name_, symbol_, decimals_);
    }
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TestInitAllBalances is Script {
    YourToken public token;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    function setUp() public {
        token = new YourToken("Test Token", "TEST", 18);
    }

    function run() public {
        vm.etch(MigrationLib.DUMMY_ADDRESS, new bytes(1));

        // Mint some tokens and perform transfers
        token.mint(alice, 1000000 ether);
        
        vm.startPrank(alice);
        token.transfer(bob, 300 ether);
        token.transfer(charlie, 200 ether);

        vm.etch(MigrationLib.DUMMY_ADDRESS, new bytes(0));
        
        vm.expectRevert("Balances not initialized");
        token.transfer(bob, 100 ether);

        token.initAllBalances();

        // Check the balanceHoldersToInit set again
        console.log("Holders to init after:", token.balanceHoldersToInitCount());
        
        for (uint256 i = 0; i < token.balanceHoldersToInitCount(); i++) {
            address holder = token.getBalanceHoldersToInit()[i];
            console.log("Holder:", holder);
        }

        // Try to transfer again (should succeed)
        bool success = token.transfer(bob, 100 ether);
        require(success, "Transfer failed");

        // Log final balances
        console.log("Alice balance:", token.balanceOf(alice) / 1 ether);
        console.log("Bob balance:", token.balanceOf(bob) / 1 ether);
        console.log("Charlie balance:", token.balanceOf(charlie) / 1 ether);
    }
}
