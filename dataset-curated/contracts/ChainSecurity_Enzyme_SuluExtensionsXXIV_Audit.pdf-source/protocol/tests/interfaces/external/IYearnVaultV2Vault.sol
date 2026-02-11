// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

import {IERC20} from "./IERC20.sol";

interface IYearnVaultV2Vault {
    function token() external view returns (IERC20 underlying_);

    function pricePerShare() external view returns (uint256 pricePerShare_);
}
