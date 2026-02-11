// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IPolygonStaking {
    function buyVoucherPOL(uint256 _amount, uint256 _minSharesToMint) external returns (uint256);

    function sellVoucherPOL(uint256 _claimAmount, uint256 _maximumSharesToBurn) external;

    function unstakeClaimTokensPOL() external;

    function restakePOL() external returns (uint256, uint256);

    function withdrawRewardsPOL() external;

    function getLiquidRewards(address _user) external view returns (uint256);

    function balanceOf(address _user) external view returns (uint256);

    function exchangeRate() external view returns (uint256);

    function withdrawExchangeRate() external view returns (uint256);

    function unbonds(address _user) external view returns (uint256, uint256);

    function validatorId() external view returns (uint256);

    function minAmount() external view returns (uint256);
}
