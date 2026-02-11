// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mainnet Ethena contract addresses
IsUSDe constant sUSDe = IsUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
ERC20 constant USDe = ERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
// Dai and sDAI are required for trading out of sUSDe
ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
IERC4626 constant sDAI = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

interface IsUSDe is IERC4626 {
    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function cooldownDuration() external view returns (uint24);
    function cooldowns(address account) external view returns (UserCooldown memory);
    function cooldownShares(uint256 shares) external returns (uint256 assets);
    function unstake(address receiver) external;
}

