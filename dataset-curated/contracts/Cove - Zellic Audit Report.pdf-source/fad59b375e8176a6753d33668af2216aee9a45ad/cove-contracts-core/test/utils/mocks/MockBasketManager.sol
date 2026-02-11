// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BasketToken } from "src/BasketToken.sol";

contract MockBasketManager is AccessControlEnumerable {
    BasketToken public basketTokenImplementation;
    bytes32 private constant _BASKET_TOKEN_ROLE = keccak256("BASKET_TOKEN_ROLE");

    constructor(address basketTokenImplementation_) {
        basketTokenImplementation = BasketToken(basketTokenImplementation_);
    }

    function createNewBasket(
        IERC20 asset,
        string memory basketName,
        string memory symbol,
        uint256 bitFlag,
        address strategy,
        address assetRegistry
    )
        public
        returns (BasketToken basket)
    {
        basket = BasketToken(Clones.clone(address(basketTokenImplementation)));
        basket.initialize(asset, basketName, symbol, bitFlag, strategy, assetRegistry);
        BasketToken(basket).approve(address(basket), type(uint256).max);
        IERC20(asset).approve(address(basket), type(uint256).max);
        _grantRole(_BASKET_TOKEN_ROLE, address(basket));
    }

    function fulfillDeposit(address basket, uint256 sharesToIssue) external {
        BasketToken(basket).fulfillDeposit(sharesToIssue);
    }

    function fulfillRedeem(address basket, uint256 assetsToIssue) external {
        BasketToken(basket).fulfillRedeem(assetsToIssue);
    }
}
