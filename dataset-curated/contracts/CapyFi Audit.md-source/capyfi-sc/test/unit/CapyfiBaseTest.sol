// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

import {Whitelist} from "src/contracts/Access/Whitelist.sol";
import {WhitelistAccess} from "src/contracts/Access/WhitelistAccess.sol";
import {CEther} from "src/contracts/CEther.sol";
import {ComptrollerInterface} from "src/contracts/ComptrollerInterface.sol";
import {InterestRateModel} from "src/contracts/InterestRateModel.sol";
import {CToken} from "src/contracts/CToken.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MockComptroller} from "../mocks/MockComptroller.sol";
import {MockInterestRateModel} from "../mocks/MockInterestRateModel.sol";


contract CapyfiBaseTest is Test {
    // Some test addresses
    address internal admin;
    address internal user1;
    address internal user2;
    address internal attacker;

    Whitelist internal whitelist;
    Whitelist internal whitelistImplementation;
    CEther internal cEther;
    MockComptroller internal comptroller;
    MockInterestRateModel internal irModel;

    function setUp() public virtual {
        // create addresses
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");

        // Give them some ETH
        vm.deal(admin, 100 ether);
        vm.deal(user1, 50 ether);
        vm.deal(user2, 50 ether);
        vm.deal(attacker, 50 ether);

        // Start deploying from admin
        vm.startPrank(admin);

        // Deploy whitelist implementation
        whitelistImplementation = new Whitelist();
        
        // Prepare initialization data for the proxy
        bytes memory initData = abi.encodeWithSelector(
            Whitelist.initialize.selector,
            admin
        );
        
        // Deploy the proxy contract
        ERC1967Proxy whitelistProxy = new ERC1967Proxy(
            address(whitelistImplementation),
            initData
        );
        
        // Use the proxy address as our whitelist
        whitelist = Whitelist(address(whitelistProxy));

        // Deploy protocol contracts
        comptroller = new MockComptroller();
        irModel = new MockInterestRateModel();

        // Deploy cEther
        cEther = new CEther(
            comptroller,
            InterestRateModel(address(irModel)),
            1e18,       // initial exchange rate
            "Capyfi Ether",
            "caETH",
            8,
            payable(admin)
        );

        vm.stopPrank();
    }
}
