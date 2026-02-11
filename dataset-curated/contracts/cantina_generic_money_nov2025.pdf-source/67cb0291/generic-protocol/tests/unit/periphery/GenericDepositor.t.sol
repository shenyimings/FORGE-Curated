// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import {
    GenericDepositor,
    IERC20,
    IERC7575Vault,
    IGenericShare,
    IBridgeCoordinatorL1Outbound,
    IWhitelabeledUnit
} from "../../../src/periphery/GenericDepositor.sol";
import { IERC7575Share } from "../../../src/interfaces/IERC7575Share.sol";

abstract contract GenericDepositorTest is Test {
    GenericDepositor depositor;

    address unitToken = makeAddr("unitToken");
    address bridgeCoordinator = makeAddr("bridgeCoordinator");
    address asset = makeAddr("asset");
    address vault = makeAddr("vault");
    address user = makeAddr("user");
    uint256 assets = 1000e18;
    uint256 shares = 500e18;
    address sourceWhitelabel = makeAddr("sourceWhitelabel");
    bytes32 destinationWhitelabel = keccak256("destinationWhitelabel");

    uint16 bridgeType = 1;
    uint256 chainId = 100;
    bytes32 remoteRecipient = bytes32(uint256(uint160(makeAddr("remoteRecipient"))));
    bytes bridgeParams = "make it fast!";
    bytes32 messageId = keccak256("message id");
    bytes32 chainNickname = keccak256("chain of gods");

    function setUp() public virtual {
        depositor = new GenericDepositor(IGenericShare(unitToken), IBridgeCoordinatorL1Outbound(bridgeCoordinator));

        vm.mockCall(unitToken, abi.encodeWithSelector(IERC7575Share.vault.selector), abi.encode(vault));
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.asset.selector), abi.encode(asset));
        vm.mockCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(asset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    }
}

contract GenericDepositor_Deposit_Test is GenericDepositorTest {
    function test_shouldRevert_whenNoVaultForAsset() public {
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC7575Share.vault.selector), abi.encode(address(0)));

        vm.expectRevert(GenericDepositor.NoVaultForAsset.selector);
        vm.prank(user);
        depositor.deposit(IERC20(asset), sourceWhitelabel, assets);
    }

    function test_shouldRevert_whenVaultAssetNotMatch() public {
        address wrongAsset = makeAddr("wrongAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.asset.selector), abi.encode(wrongAsset));

        vm.expectRevert(GenericDepositor.AssetMismatch.selector);
        vm.prank(user);
        depositor.deposit(IERC20(asset), sourceWhitelabel, assets);
    }

    function test_shouldRevert_whenZeroAssets() public {
        vm.expectRevert(GenericDepositor.ZeroAssets.selector);
        vm.prank(user);
        depositor.deposit(IERC20(asset), sourceWhitelabel, 0);
    }

    function test_shouldDepositSuccessfully_whenWhitelabelZero() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector), abi.encode(shares));

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector, assets, user));

        vm.prank(user);
        uint256 receivedShares = depositor.deposit(IERC20(asset), address(0), assets);
        assertEq(receivedShares, shares);
    }

    function test_shouldDepositSuccessfully_whenWhitelabelNotZero() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector), abi.encode(shares));
        vm.mockCall(sourceWhitelabel, abi.encodeWithSelector(IWhitelabeledUnit.wrap.selector), "");

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector, assets, address(depositor)));
        vm.expectCall(sourceWhitelabel, abi.encodeWithSelector(IWhitelabeledUnit.wrap.selector, user, shares));

        vm.prank(user);
        uint256 receivedShares = depositor.deposit(IERC20(asset), sourceWhitelabel, assets);
        assertEq(receivedShares, shares);
    }
}

contract GenericDepositor_Mint_Test is GenericDepositorTest {
    function test_shouldRevert_whenNoVaultForAsset() public {
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC7575Share.vault.selector), abi.encode(address(0)));

        vm.expectRevert(GenericDepositor.NoVaultForAsset.selector);
        vm.prank(user);
        depositor.mint(IERC20(asset), sourceWhitelabel, shares);
    }

    function test_shouldRevert_whenVaultAssetNotMatch() public {
        address wrongAsset = makeAddr("wrongAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.asset.selector), abi.encode(wrongAsset));

        vm.expectRevert(GenericDepositor.AssetMismatch.selector);
        vm.prank(user);
        depositor.mint(IERC20(asset), sourceWhitelabel, shares);
    }

    function test_shouldRevert_whenZeroShares() public {
        vm.expectRevert(GenericDepositor.ZeroShares.selector);
        vm.prank(user);
        depositor.mint(IERC20(asset), sourceWhitelabel, 0);
    }

    function test_shouldMintSuccessfully_whenWhitelabelZero() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector), abi.encode(assets));
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.previewMint.selector), abi.encode(assets));

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector, shares, user));

        vm.prank(user);
        uint256 receivedAssets = depositor.mint(IERC20(asset), address(0), shares);
        assertEq(receivedAssets, assets);
    }

    function test_shouldMintSuccessfully_whenWhitelabelNotZero() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector), abi.encode(assets));
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.previewMint.selector), abi.encode(assets));
        vm.mockCall(sourceWhitelabel, abi.encodeWithSelector(IWhitelabeledUnit.wrap.selector), "");

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector, shares, address(depositor)));
        vm.expectCall(sourceWhitelabel, abi.encodeWithSelector(IWhitelabeledUnit.wrap.selector, user, shares));

        vm.prank(user);
        uint256 receivedAssets = depositor.mint(IERC20(asset), sourceWhitelabel, shares);
        assertEq(receivedAssets, assets);
    }
}

contract GenericDepositor_DepositAndBridge_Test is GenericDepositorTest {
    function test_shouldRevert_whenNoVaultForAsset() public {
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC7575Share.vault.selector), abi.encode(address(0)));

        vm.expectRevert(GenericDepositor.NoVaultForAsset.selector);
        vm.prank(user);
        depositor.depositAndBridge(
            IERC20(asset), assets, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
    }

    function test_shouldRevert_whenVaultAssetNotMatch() public {
        address wrongAsset = makeAddr("wrongAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.asset.selector), abi.encode(wrongAsset));

        vm.expectRevert(GenericDepositor.AssetMismatch.selector);
        vm.prank(user);
        depositor.depositAndBridge(
            IERC20(asset), assets, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
    }

    function test_shouldRevert_whenZeroAssets() public {
        vm.expectRevert(GenericDepositor.ZeroAssets.selector);
        vm.prank(user);
        depositor.depositAndBridge(
            IERC20(asset), 0, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
    }

    function test_shouldDepositAndBridgeSuccessfully() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector), abi.encode(shares));
        vm.mockCall(
            bridgeCoordinator,
            abi.encodeWithSelector(IBridgeCoordinatorL1Outbound.bridge.selector),
            abi.encode(messageId)
        );

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector, assets, address(depositor)));
        vm.expectCall(unitToken, abi.encodeWithSelector(IERC20.approve.selector, bridgeCoordinator, shares));
        vm.expectCall(
            bridgeCoordinator,
            abi.encodeWithSelector(
                IBridgeCoordinatorL1Outbound.bridge.selector,
                bridgeType,
                chainId,
                user,
                remoteRecipient,
                address(0),
                destinationWhitelabel,
                shares,
                bridgeParams
            )
        );

        vm.prank(user);
        (uint256 receivedShares, bytes32 receivedMessageId) = depositor.depositAndBridge(
            IERC20(asset), assets, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
        assertEq(receivedShares, shares);
        assertEq(receivedMessageId, messageId);
    }
}

contract GenericDepositor_MintAndBridge_Test is GenericDepositorTest {
    function test_shouldRevert_whenNoVaultForAsset() public {
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC7575Share.vault.selector), abi.encode(address(0)));

        vm.expectRevert(GenericDepositor.NoVaultForAsset.selector);
        vm.prank(user);
        depositor.mintAndBridge(
            IERC20(asset), shares, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
    }

    function test_shouldRevert_whenVaultAssetNotMatch() public {
        address wrongAsset = makeAddr("wrongAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.asset.selector), abi.encode(wrongAsset));

        vm.expectRevert(GenericDepositor.AssetMismatch.selector);
        vm.prank(user);
        depositor.mintAndBridge(
            IERC20(asset), shares, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
    }

    function test_shouldRevert_whenZeroShares() public {
        vm.expectRevert(GenericDepositor.ZeroShares.selector);
        vm.prank(user);
        depositor.mintAndBridge(
            IERC20(asset), 0, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
    }

    function test_shouldMintAndBridgeSuccessfully() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector), abi.encode(assets));
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.previewMint.selector), abi.encode(assets));
        vm.mockCall(
            bridgeCoordinator,
            abi.encodeWithSelector(IBridgeCoordinatorL1Outbound.bridge.selector),
            abi.encode(messageId)
        );

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector, shares, address(depositor)));
        vm.expectCall(unitToken, abi.encodeWithSelector(IERC20.approve.selector, bridgeCoordinator, shares));
        vm.expectCall(
            bridgeCoordinator,
            abi.encodeWithSelector(
                IBridgeCoordinatorL1Outbound.bridge.selector,
                bridgeType,
                chainId,
                user,
                remoteRecipient,
                address(0),
                destinationWhitelabel,
                shares,
                bridgeParams
            )
        );

        vm.prank(user);
        (uint256 receivedAssets, bytes32 receivedMessageId) = depositor.mintAndBridge(
            IERC20(asset), shares, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
        assertEq(receivedAssets, assets);
        assertEq(receivedMessageId, messageId);
    }
}

contract GenericDepositor_DepositAndPredeposit_Test is GenericDepositorTest {
    function test_shouldRevert_whenNoVaultForAsset() public {
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC7575Share.vault.selector), abi.encode(address(0)));

        vm.expectRevert(GenericDepositor.NoVaultForAsset.selector);
        vm.prank(user);
        depositor.depositAndPredeposit(IERC20(asset), assets, chainNickname, remoteRecipient);
    }

    function test_shouldRevert_whenVaultAssetNotMatch() public {
        address wrongAsset = makeAddr("wrongAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.asset.selector), abi.encode(wrongAsset));

        vm.expectRevert(GenericDepositor.AssetMismatch.selector);
        vm.prank(user);
        depositor.depositAndPredeposit(IERC20(asset), assets, chainNickname, remoteRecipient);
    }

    function test_shouldRevert_whenZeroAssets() public {
        vm.expectRevert(GenericDepositor.ZeroAssets.selector);
        vm.prank(user);
        depositor.depositAndPredeposit(IERC20(asset), 0, chainNickname, remoteRecipient);
    }

    function test_shouldDepositAndBridgeSuccessfully() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector), abi.encode(shares));
        vm.mockCall(bridgeCoordinator, abi.encodeWithSelector(IBridgeCoordinatorL1Outbound.predeposit.selector), "");

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.deposit.selector, assets, address(depositor)));
        vm.expectCall(unitToken, abi.encodeWithSelector(IERC20.approve.selector, bridgeCoordinator, shares));
        vm.expectCall(
            bridgeCoordinator,
            abi.encodeWithSelector(
                IBridgeCoordinatorL1Outbound.predeposit.selector, chainNickname, user, remoteRecipient, shares
            )
        );

        vm.prank(user);
        uint256 receivedShares = depositor.depositAndPredeposit(IERC20(asset), assets, chainNickname, remoteRecipient);
        assertEq(receivedShares, shares);
    }
}

contract GenericDepositor_MintAndPredeposit_Test is GenericDepositorTest {
    function test_shouldRevert_whenNoVaultForAsset() public {
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC7575Share.vault.selector), abi.encode(address(0)));

        vm.expectRevert(GenericDepositor.NoVaultForAsset.selector);
        vm.prank(user);
        depositor.mintAndPredeposit(IERC20(asset), shares, chainNickname, remoteRecipient);
    }

    function test_shouldRevert_whenVaultAssetNotMatch() public {
        address wrongAsset = makeAddr("wrongAsset");
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.asset.selector), abi.encode(wrongAsset));

        vm.expectRevert(GenericDepositor.AssetMismatch.selector);
        vm.prank(user);
        depositor.mintAndPredeposit(IERC20(asset), shares, chainNickname, remoteRecipient);
    }

    function test_shouldRevert_whenZeroShares() public {
        vm.expectRevert(GenericDepositor.ZeroShares.selector);
        vm.prank(user);
        depositor.mintAndPredeposit(IERC20(asset), 0, chainNickname, remoteRecipient);
    }

    function test_shouldMintAndBridgeSuccessfully() public {
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector), abi.encode(assets));
        vm.mockCall(vault, abi.encodeWithSelector(IERC7575Vault.previewMint.selector), abi.encode(assets));
        vm.mockCall(bridgeCoordinator, abi.encodeWithSelector(IBridgeCoordinatorL1Outbound.predeposit.selector), "");

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(depositor), assets));
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.approve.selector, vault, assets));
        vm.expectCall(vault, abi.encodeWithSelector(IERC7575Vault.mint.selector, shares, address(depositor)));
        vm.expectCall(unitToken, abi.encodeWithSelector(IERC20.approve.selector, bridgeCoordinator, shares));
        vm.expectCall(
            bridgeCoordinator,
            abi.encodeWithSelector(
                IBridgeCoordinatorL1Outbound.predeposit.selector, chainNickname, user, remoteRecipient, shares
            )
        );

        vm.prank(user);
        uint256 receivedAssets = depositor.mintAndPredeposit(IERC20(asset), shares, chainNickname, remoteRecipient);
        assertEq(receivedAssets, assets);
    }
}
