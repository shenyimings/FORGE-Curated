// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { FluidkeyEarnModule } from "../src/FluidkeyEarnModule.sol";
import { SafeModuleSetup } from "../src/SafeModuleSetup.sol";
import { MultiSend } from "../lib/safe-tools/lib/safe-contracts/contracts/libraries/MultiSend.sol";
import { SafeProxyFactory } from
    "../lib/safe-tools/lib/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import { Safe } from "../lib/safe-tools/lib/safe-contracts/contracts/Safe.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { SENTINEL } from "sentinellist/SentinelList.sol";
import { console } from "forge-std/console.sol";

contract FluidkeyEarnModuleTest is Test {
    // Contracts
    FluidkeyEarnModule internal module;
    SafeModuleSetup internal safeModuleSetup;
    MultiSend internal multiSend;
    SafeProxyFactory internal safeProxyFactory;

    // ERC20 contracts on Base
    IERC20 public USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20 public WETH = IERC20(0x4200000000000000000000000000000000000006);
    address public ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IERC4626 public RE7_USDC_ERC4626 = IERC4626(0x12AFDeFb2237a5963e7BAb3e2D46ad0eee70406e);
    IERC4626 public GAUNTLET_WETH_ERC4626 = IERC4626(0x6b13c060F13Af1fdB319F52315BbbF3fb1D88844);
    IERC4626 public STEAKHOUSE_USDC_ERC4626 = IERC4626(0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183);
    uint256 constant RELAYER_PRIVATE_KEY = 0x35383d0f6ff2fa6b3f8de5425f4d6227b20d1a7a02bff9b00e9458db39e07e28;


    address internal owner;
    address[] internal ownerAddresses;
    address internal authorizedRelayer;
    address internal safe;
    address internal moduleOwner;
    bytes internal moduleInitData;
    bytes internal moduleSettingData;
    bytes internal moduleData;
    uint256 internal baseFork;

    function setUp() public {
        // Create a fork on Base
        string memory DEPLOYMENT_RPC = vm.envString("RPC_URL_BASE");
        baseFork = vm.createSelectFork(DEPLOYMENT_RPC);
        vm.selectFork(baseFork);

        // Create test addresses
        owner = makeAddr("bob");
        moduleOwner = makeAddr("moduleDeployer");
        authorizedRelayer = vm.addr(RELAYER_PRIVATE_KEY);

        // Initialize contracts - deploy module from moduleOwner
        vm.startPrank(moduleOwner);
        module = new FluidkeyEarnModule(authorizedRelayer, address(WETH));
        vm.stopPrank();
        safeModuleSetup = SafeModuleSetup(0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47);
        multiSend = MultiSend(0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526);
        safeProxyFactory = SafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);

        // Prepare the FluidkeyEarnModule init and setting data as part of a multisend tx
        address[] memory modules = new address[](1);
        modules[0] = address(module);
        moduleInitData = abi.encodeWithSelector(safeModuleSetup.enableModules.selector, modules);
        uint256 moduleInitDataLength = moduleInitData.length;

        // Create a dynamic array of ConfigWithToken
        FluidkeyEarnModule.ConfigWithToken[] memory configs =
            new FluidkeyEarnModule.ConfigWithToken[](2);

        // Populate the array
        configs[0] = FluidkeyEarnModule.ConfigWithToken({
            token: address(USDC),
            vault: address(RE7_USDC_ERC4626)
        });
        configs[1] = FluidkeyEarnModule.ConfigWithToken({
            token: address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            vault: address(GAUNTLET_WETH_ERC4626)
        });

        moduleSettingData = abi.encodeWithSelector(module.onInstall.selector, abi.encode(configs));

        uint256 moduleSettingDataLength = moduleSettingData.length;
        bytes memory multisendData = abi.encodePacked(
            uint8(1),
            address(safeModuleSetup),
            uint256(0),
            moduleInitDataLength,
            moduleInitData,
            uint8(0),
            address(module),
            uint256(0),
            moduleSettingDataLength,
            moduleSettingData
        );
        multisendData = abi.encodeWithSelector(multiSend.multiSend.selector, multisendData);
        ownerAddresses = new address[](1);
        ownerAddresses[0] = owner;
        bytes memory initData = abi.encodeWithSelector(
            Safe.setup.selector,
            ownerAddresses,
            1,
            address(multiSend),
            multisendData,
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        // Deploy the Safe
        safe = payable(
            safeProxyFactory.createProxyWithNonce(
                address(0x29fcB43b46531BcA003ddC8FCB67FFE91900C762), initData, 100
            )
        );
    }

    function test_Deployment() public view {
        bool isInitialized = module.isInitialized(safe);
        assertEq(isInitialized, true, "1: Module is not initialized");
    }

    function test_AutoEarnWithRelayerErc20() public {
        deal(address(USDC), safe, 100_000_000);
        vm.startPrank(authorizedRelayer);
        module.autoEarn(address(USDC), 100_000_000, safe);
        uint256 balance = USDC.balanceOf(safe);
        assertEq(balance, 0, "1: USDC balance is not correct");
        uint256 balanceOfVault = RE7_USDC_ERC4626.balanceOf(safe);
        assertGt(balanceOfVault, 0, "2: USDC balance of vault is 0");
    }

    function test_AutoEarnWithRelayerEth() public {
        deal(safe, 1 ether);
        vm.startPrank(authorizedRelayer);
        module.autoEarn(ETH, 1 ether, safe);
        uint256 balance = address(safe).balance;
        assertEq(balance, 0, "1: ETH balance is not correct");
        uint256 balanceOfVault = GAUNTLET_WETH_ERC4626.balanceOf(safe);
        assertGt(balanceOfVault, 0, "2: ETH balance of vault is 0");
    }

    function test_AutoEarnWithoutRelayer() public {
        deal(address(USDC), safe, 100_000_000);
        address unauthorizedRelayer = makeAddr("unauthorizedRelayer");
        vm.startPrank(unauthorizedRelayer);
        vm.expectRevert(
            abi.encodeWithSelector(FluidkeyEarnModule.NotAuthorized.selector, unauthorizedRelayer)
        );
        module.autoEarn(address(USDC), 100_000_000, safe);
    }

    function test_UpdateConfig() public {
        vm.startPrank(safe);
        module.setConfig(address(USDC), address(STEAKHOUSE_USDC_ERC4626));
        vm.startPrank(authorizedRelayer);
        deal(address(USDC), safe, 100_000_000);
        module.autoEarn(address(USDC), 100_000_000, safe);
        uint256 balance = USDC.balanceOf(safe);
        assertEq(balance, 0, "1: USDC balance is not correct");
        uint256 balanceOfVault = STEAKHOUSE_USDC_ERC4626.balanceOf(safe);
        assertGt(balanceOfVault, 0, "2: USDC balance of vault is 0");
    }

    function test_DeleteConfig() public {
        address[] memory tokens = module.getTokens(safe);
        vm.startPrank(safe);
        module.deleteConfig(SENTINEL, tokens[0]);
        tokens = module.getTokens(safe);
        module.deleteConfig(SENTINEL, tokens[0]);
        tokens = module.getTokens(safe);
        assertEq(tokens.length, 0, "1: Tokens are not deleted");
        deal(safe, 1 ether);
        vm.startPrank(authorizedRelayer);
        vm.expectRevert(
            abi.encodeWithSelector(FluidkeyEarnModule.ConfigNotFound.selector, address(ETH))
        );
        module.autoEarn(ETH, 1 ether, safe);
    }

    function test_AddRemoveRelayer() public {
        address newRelayer = makeAddr("newRelayer");
        vm.startPrank(authorizedRelayer);
        module.addAuthorizedRelayer(newRelayer);
        vm.stopPrank();
        vm.startPrank(newRelayer);
        module.removeAuthorizedRelayer(authorizedRelayer);
        vm.stopPrank();
        vm.startPrank(authorizedRelayer);
        vm.expectRevert(
            abi.encodeWithSelector(FluidkeyEarnModule.NotAuthorized.selector, authorizedRelayer)
        );
        module.addAuthorizedRelayer(authorizedRelayer);
        vm.stopPrank();
        vm.startPrank(newRelayer);
        vm.expectRevert(FluidkeyEarnModule.CannotRemoveSelf.selector);
        module.removeAuthorizedRelayer(newRelayer);
    }

    function test_AutoEarnWithModuleOwnerAsRelayer() public {
        deal(address(USDC), safe, 100_000_000);
        vm.startPrank(moduleOwner);
        // ModuleOwner should work as authorized since owner has permission
        module.autoEarn(address(USDC), 100_000_000, safe);
        uint256 balance = USDC.balanceOf(safe);
        assertEq(balance, 0);
        uint256 balanceOfVault = RE7_USDC_ERC4626.balanceOf(safe);
        assertGt(balanceOfVault, 0);
    }

    function test_AutoEarnWithValidSignature() public {
        // Give the Safe some USDC
        deal(address(USDC), safe, 100_000_000);

        // Sign the message with the authorized relayer's key
        uint256 nonce = 1234;
        bytes32 hash = keccak256(abi.encodePacked(address(USDC), uint256(100_000_000), safe, nonce));
        bytes32 ethHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(RELAYER_PRIVATE_KEY, ethHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Execute autoEarn with a valid signature
        vm.prank(makeAddr("anyone"));
        module.autoEarn(address(USDC), 100_000_000, safe, nonce, signature);

        // Verify the funds got deposited
        assertEq(USDC.balanceOf(safe), 0);
        assertGt(RE7_USDC_ERC4626.balanceOf(safe), 0);
    }

    function test_AutoEarnWithInvalidSignature() public {
        // Give the Safe some USDC
        deal(address(USDC), safe, 50_000_000);

        // Sign with a different private key (unauthorized)
        uint256 nonce = 1234;
        bytes32 hash = keccak256(abi.encodePacked(address(USDC), uint256(50_000_000), safe, nonce));
        bytes32 ethHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
        uint256 UNAUTHORIZED_PRIVATE_KEY = 0x491fa4c92337d0a76cb0323e71e88ec4073e0fd9770ec97e9a6196a39e4a7d01;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(UNAUTHORIZED_PRIVATE_KEY, ethHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Expect revert because it doesn't recover to an authorized relayer
        vm.prank(makeAddr("anyone"));
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidkeyEarnModule.NotAuthorized.selector,
                /* this will be the recovered address from the bad signature */
                vm.addr(UNAUTHORIZED_PRIVATE_KEY)
            )
        );
        module.autoEarn(address(USDC), 50_000_000, safe, nonce, signature);
    }

    function test_AutoEarnReplaySignature() public {
        // Give the Safe some USDC
        deal(address(USDC), safe, 100_000_000);

        // Create a valid signature from authorized relayer
        uint256 nonce = 1234;
        bytes32 hash = keccak256(abi.encodePacked(address(USDC), uint256(10_000_000), safe, nonce));
        bytes32 ethHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(RELAYER_PRIVATE_KEY, ethHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First call succeeds
        vm.prank(makeAddr("anyone"));
        module.autoEarn(address(USDC), 10_000_000, safe, nonce, signature);

        // Second call with the same signature should revert
        vm.prank(makeAddr("anyone"));
        vm.expectRevert(FluidkeyEarnModule.SignatureAlreadyUsed.selector);
        module.autoEarn(address(USDC), 10_000_000, safe, nonce, signature);
    }

    function test_CannotRemoveModuleOwnerFromRelayers() public {
        vm.startPrank(moduleOwner);
        // Attempt to remove self should revert
        vm.expectRevert(FluidkeyEarnModule.CannotRemoveSelf.selector);
        module.removeAuthorizedRelayer(moduleOwner);
    }

    function test_ModuleOwnerCanAddRelayer() public {
        address newRelayer = makeAddr("newRelayer");
        vm.startPrank(moduleOwner);
        module.addAuthorizedRelayer(newRelayer);
        bool isRelayer = module.authorizedRelayers(newRelayer);
        assertTrue(isRelayer, "Module owner could not add a new relayer");
    }

    function test_AddModuleOwnerAsRelayerWorks() public {
        vm.startPrank(moduleOwner);
        // Adding owner again should work without affecting permissions
        module.addAuthorizedRelayer(moduleOwner);
        bool isRelayer = module.authorizedRelayers(moduleOwner);
        assertTrue(isRelayer);
        // Owner continues to execute actions
        deal(address(USDC), safe, 100_000_000);
        module.autoEarn(address(USDC), 100_000_000, safe);
        uint256 balanceOfVault = RE7_USDC_ERC4626.balanceOf(safe);
        assertGt(balanceOfVault, 0);
    }

    function test_OnUninstall() public {
        vm.startPrank(safe);
        module.onUninstall();
        address[] memory tokens = module.getTokens(safe);
        assertEq(tokens.length, 0, "1: Tokens are not deleted");
    }
}
