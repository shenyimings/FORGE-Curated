// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import "./IlvlUSD.sol";
import "./ILevelMinting.sol";
import "./IStakedlvlUSD.sol";
import "./ILevelBaseYieldManager.sol";

interface ILevelBaseReserveManager {
    /* Events */
    event DepositedToYieldManager(
        address token,
        address yieldManager,
        uint256 amount
    );
    event WithdrawnFromYieldManager(
        address token,
        address yieldManager,
        uint256 amount
    );
    event DepositedToLevelMinting(uint256 amount);
    event YieldManagerSetForToken(address token, address yieldManager);

    /* Errors */
    error InvalidlvlUSDAddress();
    error InvalidZeroAddress();
    error TreasuryNotSet();
    error InvalidAmount();
    error InvalidRecipient();

    /* Functions */
    function treasury() external view returns (address);

    function rakeBasisPoints() external view returns (uint16);

    function maxSlippageThresholdBasisPoints() external view returns (uint16);

    function lvlUSD() external view returns (IlvlUSD);

    function lvlUsdDecimals() external view returns (uint256);

    function levelMinting() external view returns (ILevelMinting);

    function allowlist(address) external view returns (bool);

    function depositForYield(address token, uint256 amount) external;

    function withdrawFromYieldManager(address token, uint256 amount) external;

    function depositToLevelMinting(address token, uint256 amount) external;

    // function rewardStakedlvlUSD(uint256 amount) external;
    // function mintlvlUSD(address collateral, uint256 amount) external;
    function approveSpender(
        address token,
        address spender,
        uint256 amount
    ) external;

    function transferERC20(
        address tokenAddress,
        address tokenReceiver,
        uint256 tokenAmount
    ) external;

    function transferEth(address payable _to, uint256 _amount) external;

    function setPaused(bool paused) external;

    function setAllowlist(address recipient, bool isAllowlisted) external;

    function setStakedlvlUSDAddress(address newAddress) external;

    function setYieldManager(address token, address baseYieldManager) external;

    function setTreasury(address _treasury) external;

    function setRakeBasisPoints(uint16 _rakeBasisPoints) external;

    function setMaxSlippageThresholdBasisPoints(
        uint16 _maxSlippageThresholdBasisPoints
    ) external;
}
