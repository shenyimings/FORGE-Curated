// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { VaultConfig } from "../../../contracts/deploy/interfaces/DeployConfigs.sol";

import { CapToken } from "../../../contracts/token/CapToken.sol";
import { StakedCap } from "../../../contracts/token/StakedCap.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { Vm } from "forge-std/Vm.sol";

contract InitTestVaultLiquidity is StdCheats {
    /// @dev Initialize the vault with some liquidity
    function _initTestVaultLiquidity(VaultConfig memory vault) internal {
        _initTestUserStakedCapToken(vault, makeAddr("random_user_1"), 12000e18);
    }

    /// @dev Give the user some cap tokens
    function _initTestUserMintCapToken(VaultConfig memory vault, address sendTo, uint256 capTokenAmount) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // init the vault with some assets
        address randomUser = makeAddr("random_user_2");
        vm.deal(randomUser, 100 ether);
        vm.startPrank(randomUser);

        CapToken capToken = CapToken(vault.capToken);

        for (uint256 i = 0; i < vault.assets.length; i++) {
            MockERC20 asset = MockERC20(vault.assets[i]);
            uint256 amount = capTokenAmount * 10 ** asset.decimals() / 10 ** capToken.decimals();

            MockERC20(asset).mint(randomUser, amount);
            asset.approve(address(capToken), amount);
            capToken.mint(address(asset), amount, 0, randomUser, block.timestamp + 1 hours);
        }

        capToken.transfer(sendTo, capTokenAmount);
        vm.stopPrank();

        // assert(capToken.balanceOf(sendTo) == capTokenAmount);
    }

    /// @dev Give the user some staked cap tokens
    function _initTestUserStakedCapToken(VaultConfig memory vault, address sendTo, uint256 stakedCapTokenAmount)
        internal
    {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        // init the vault with some assets
        address randomUser = makeAddr("random_user_3");
        vm.deal(randomUser, 100 ether);

        CapToken capToken = CapToken(vault.capToken);
        StakedCap stakedCapToken = StakedCap(vault.stakedCapToken);

        uint256 capTokenAmount = stakedCapTokenAmount * 10 ** capToken.decimals() / 10 ** stakedCapToken.decimals();
        _initTestUserMintCapToken(vault, randomUser, capTokenAmount);

        vm.startPrank(randomUser);
        capToken.approve(vault.stakedCapToken, capTokenAmount);
        stakedCapToken.deposit(capTokenAmount, randomUser);

        stakedCapToken.transfer(sendTo, stakedCapTokenAmount);
        vm.stopPrank();

        // assert(stakedCapToken.balanceOf(sendTo) == stakedCapTokenAmount);
    }
}
