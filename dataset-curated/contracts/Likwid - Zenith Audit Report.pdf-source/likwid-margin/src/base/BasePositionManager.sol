// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.26;

// Openzeppelin
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
// Solmate
import {Owned} from "solmate/src/auth/Owned.sol";
// Local
import {IBasePositionManager} from "../interfaces/IBasePositionManager.sol";
import {ImmutableState} from "./ImmutableState.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolId} from "../types/PoolId.sol";
import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IUnlockCallback} from "../interfaces/callback/IUnlockCallback.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";
import {CurrencyPoolLibrary} from "../libraries/CurrencyPoolLibrary.sol";

abstract contract BasePositionManager is
    IBasePositionManager,
    ImmutableState,
    IUnlockCallback,
    ERC721Enumerable,
    Owned
{
    using CurrencyPoolLibrary for Currency;
    using CustomRevert for bytes4;

    uint256 public nextId = 1;

    mapping(uint256 tokenId => PoolId poolId) public poolIds;
    mapping(PoolId poolId => PoolKey poolKey) public poolKeys;

    constructor(string memory name_, string memory symbol_, address initialOwner, IVault _vault)
        ImmutableState(_vault)
        Owned(initialOwner)
        ERC721(name_, symbol_)
    {}

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    function _requireAuth(address spender, uint256 tokenId) internal view {
        if (spender != ownerOf(tokenId)) {
            NotOwner.selector.revertWith();
        }
    }

    function _clearNative(address spender) internal {
        // clear any native currency left in the contract
        uint256 balance = address(this).balance;
        if (balance > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(spender, balance);
        }
    }

    function _processDelta(
        address sender,
        PoolKey memory key,
        BalanceDelta delta,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 amount0Max,
        uint256 amount1Max
    ) internal returns (uint256 amount0, uint256 amount1) {
        if (delta.amount0() < 0) {
            amount0 = uint256(-int256(delta.amount0()));
            if ((amount0Min > 0 && amount0 < amount0Min) || (amount0Max > 0 && amount0 > amount0Max)) {
                PriceSlippageTooHigh.selector.revertWith();
            }
            key.currency0.settle(vault, sender, amount0, false);
        } else if (delta.amount0() > 0) {
            amount0 = uint256(int256(delta.amount0()));
            if ((amount0Min > 0 && amount0 < amount0Min) || (amount0Max > 0 && amount0 > amount0Max)) {
                PriceSlippageTooHigh.selector.revertWith();
            }
            key.currency0.take(vault, sender, amount0, false);
        }

        if (delta.amount1() < 0) {
            amount1 = uint256(-int256(delta.amount1()));
            if ((amount1Min > 0 && amount1 < amount1Min) || (amount1Max > 0 && amount1 > amount1Max)) {
                PriceSlippageTooHigh.selector.revertWith();
            }
            key.currency1.settle(vault, sender, amount1, false);
        } else if (delta.amount1() > 0) {
            amount1 = uint256(int256(delta.amount1()));
            if ((amount1Min > 0 && amount1 < amount1Min) || (amount1Max > 0 && amount1 > amount1Max)) {
                PriceSlippageTooHigh.selector.revertWith();
            }
            key.currency1.take(vault, sender, amount1, false);
        }

        _clearNative(sender);
    }

    function _mintPosition(PoolKey memory key, address to) internal returns (uint256 tokenId) {
        tokenId = nextId++;
        _mint(to, tokenId);

        PoolId poolId = key.toId();
        poolIds[tokenId] = poolId;
        if (poolKeys[poolId].currency1 == Currency.wrap(address(0))) {
            poolKeys[poolId] = key;
        } else {
            PoolKey memory existingKey = poolKeys[poolId];
            if (
                !(
                    existingKey.currency0 == key.currency0 && existingKey.currency1 == key.currency1
                        && existingKey.fee == key.fee
                )
            ) {
                MismatchedPoolKey.selector.revertWith();
            }
        }
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external virtual returns (bytes memory);
}
