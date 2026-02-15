// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {ICowSettlement} from "src/interface/ICowSettlement.sol";
import {IERC20} from "src/vendored/IERC20.sol";

import {ICowAllowListAuthentication} from "./ICowAllowListAuthentication.sol";

library Constants {
    // Multi-chain

    ICowSettlement internal constant SETTLEMENT_CONTRACT = ICowSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
    ICowAllowListAuthentication internal constant SOLVER_AUTHENTICATOR =
        ICowAllowListAuthentication(0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE);
    // The following address can add solvers on CoW Protocol in all networks and
    // forked blocks we consider in the e2e tests as of writing.
    address internal constant AUTHENTICATOR_MANAGER = 0xA03be496e67Ec29bC62F01a428683D7F9c204930;

    // Mainnet

    IERC20 internal constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
}
