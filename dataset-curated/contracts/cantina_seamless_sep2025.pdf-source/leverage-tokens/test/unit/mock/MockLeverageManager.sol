// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";
// Dependency imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState, ActionData, RebalanceAction} from "src/types/DataTypes.sol";

contract MockLeverageManager is Test {
    uint256 public BASE_RATIO = 1e18;

    struct LeverageTokenData {
        ILeverageToken leverageToken;
        ILendingAdapter lendingAdapter;
        IERC20 collateralAsset;
        IERC20 debtAsset;
    }

    struct DepositParams {
        ILeverageToken leverageToken;
        uint256 collateral;
        uint256 minShares;
    }

    struct RedeemParams {
        ILeverageToken leverageToken;
        uint256 shares;
        uint256 minCollateral;
    }

    struct PreviewDepositParams {
        ILeverageToken leverageToken;
        uint256 collateral;
    }

    struct MockDepositData {
        uint256 collateral;
        uint256 debt;
        uint256 shares;
        bool isExecuted;
    }

    struct MockRedeemData {
        uint256 collateral;
        uint256 debt;
        uint256 shares;
        bool isExecuted;
    }

    struct MockPreviewDepositData {
        uint256 collateral;
        uint256 debt;
        uint256 shares;
        uint256 tokenFee;
        uint256 treasuryFee;
    }

    struct MockPreviewRedeemData {
        uint256 collateralToRemove;
        uint256 debtToRepay;
        uint256 shares;
        uint256 tokenFee;
        uint256 treasuryFee;
    }

    mapping(ILeverageToken => LeverageTokenData) public leverageTokens;

    mapping(ILeverageToken => LeverageTokenState) public leverageTokenStates;

    mapping(bytes32 => MockDepositData[]) public mockDepositData;

    mapping(bytes32 => MockRedeemData[]) public mockRedeemData;

    mapping(bytes32 => MockPreviewDepositData) public mockPreviewDepositData;

    mapping(bytes32 => MockPreviewRedeemData) public mockPreviewRedeemData;

    mapping(ILeverageToken => address) public leverageTokenRebalanceAdapter;

    mapping(ILeverageToken => uint256) public leverageTokenInitialCollateralRatio;

    function getLeverageTokenCollateralAsset(ILeverageToken leverageToken) external view returns (IERC20) {
        return leverageTokens[leverageToken].collateralAsset;
    }

    function getLeverageTokenInitialCollateralRatio(ILeverageToken leverageToken) external view returns (uint256) {
        return leverageTokenInitialCollateralRatio[leverageToken];
    }

    function getLeverageTokenLendingAdapter(ILeverageToken leverageToken) external view returns (ILendingAdapter) {
        return leverageTokens[leverageToken].lendingAdapter;
    }

    function getLeverageTokenRebalanceAdapter(ILeverageToken leverageToken) public view returns (address) {
        return leverageTokenRebalanceAdapter[leverageToken];
    }

    function getLeverageTokenState(ILeverageToken leverageToken) external view returns (LeverageTokenState memory) {
        return leverageTokenStates[leverageToken];
    }

    function getLeverageTokenDebtAsset(ILeverageToken leverageToken) external view returns (IERC20) {
        return leverageTokens[leverageToken].debtAsset;
    }

    function setLeverageTokenInitialCollateralRatio(ILeverageToken leverageToken, uint256 _initialCollateralRatio)
        external
    {
        leverageTokenInitialCollateralRatio[leverageToken] = _initialCollateralRatio;
    }

    function setLeverageTokenData(ILeverageToken leverageToken, LeverageTokenData memory _leverageTokenData) external {
        leverageTokens[leverageToken] = _leverageTokenData;
    }

    function setLeverageTokenState(ILeverageToken leverageToken, LeverageTokenState memory _leverageTokenState)
        external
    {
        leverageTokenStates[leverageToken] = _leverageTokenState;
    }

    function setLeverageTokenRebalanceAdapter(ILeverageToken leverageToken, address _rebalanceAdapter) external {
        leverageTokenRebalanceAdapter[leverageToken] = _rebalanceAdapter;
    }

    function setMockPreviewDepositData(
        PreviewDepositParams memory _depositParams,
        MockPreviewDepositData memory _mockPreviewDepositData
    ) external {
        bytes32 mockPreviewDepositDataKey =
            keccak256(abi.encode(_depositParams.leverageToken, _depositParams.collateral));
        mockPreviewDepositData[mockPreviewDepositDataKey] = _mockPreviewDepositData;
    }

    function setMockDepositData(DepositParams memory _depositParams, MockDepositData memory _mockDepositData)
        external
    {
        bytes32 mockDepositDataKey =
            keccak256(abi.encode(_depositParams.leverageToken, _depositParams.collateral, _depositParams.minShares));
        mockDepositData[mockDepositDataKey].push(_mockDepositData);
    }

    function setMockRedeemData(RedeemParams memory _redeemParams, MockRedeemData memory _mockRedeemData) external {
        bytes32 mockRedeemDataKey =
            keccak256(abi.encode(_redeemParams.leverageToken, _redeemParams.shares, _redeemParams.minCollateral));
        mockRedeemData[mockRedeemDataKey].push(_mockRedeemData);
    }

    function previewDeposit(ILeverageToken leverageToken, uint256 collateral)
        external
        view
        returns (ActionData memory)
    {
        bytes32 mockPreviewDepositDataKey = keccak256(abi.encode(leverageToken, collateral));
        return ActionData({
            collateral: mockPreviewDepositData[mockPreviewDepositDataKey].collateral,
            debt: mockPreviewDepositData[mockPreviewDepositDataKey].debt,
            shares: mockPreviewDepositData[mockPreviewDepositDataKey].shares,
            tokenFee: mockPreviewDepositData[mockPreviewDepositDataKey].tokenFee,
            treasuryFee: mockPreviewDepositData[mockPreviewDepositDataKey].treasuryFee
        });
    }

    function deposit(ILeverageToken leverageToken, uint256 collateral, uint256 minShares)
        external
        returns (ActionData memory)
    {
        LeverageTokenData storage leverageTokenData = leverageTokens[leverageToken];

        bytes32 mockDepositDataKey = keccak256(abi.encode(leverageToken, collateral, minShares));
        MockDepositData[] memory mockDepositDataArray = mockDepositData[mockDepositDataKey];

        // Find the first unexecuted mock deposit data
        for (uint256 i = 0; i < mockDepositDataArray.length; i++) {
            MockDepositData memory _mockDepositData = mockDepositDataArray[i];
            if (!_mockDepositData.isExecuted) {
                // Transfer the required collateral to the LeverageManager
                SafeERC20.safeTransferFrom(
                    leverageTokenData.collateralAsset, msg.sender, address(this), _mockDepositData.collateral
                );

                // Give the sender the required debt
                deal(address(leverageTokenData.debtAsset), address(this), _mockDepositData.debt);
                leverageTokenData.debtAsset.transfer(msg.sender, _mockDepositData.debt);

                // Give the sender the shares
                deal(address(leverageTokenData.leverageToken), address(this), _mockDepositData.shares);
                leverageTokenData.leverageToken.transfer(msg.sender, _mockDepositData.shares);

                // Set the mock deposit data to executed and return the shares minted
                mockDepositData[mockDepositDataKey][i].isExecuted = true;
                return ActionData({
                    collateral: _mockDepositData.collateral,
                    debt: _mockDepositData.debt,
                    shares: _mockDepositData.shares,
                    tokenFee: 0,
                    treasuryFee: 0
                });
            }
        }

        // If no mock deposit data is found, revert
        revert("No mock deposit data found for MockLeverageManager.deposit");
    }

    function redeem(ILeverageToken leverageToken, uint256 shares, uint256 minCollateral)
        external
        returns (ActionData memory)
    {
        LeverageTokenData storage leverageTokenData = leverageTokens[leverageToken];

        bytes32 mockRedeemDataKey = keccak256(abi.encode(leverageToken, shares, minCollateral));
        MockRedeemData[] memory mockRedeemDataArray = mockRedeemData[mockRedeemDataKey];

        // Find the first unexecuted mock mint data
        for (uint256 i = 0; i < mockRedeemDataArray.length; i++) {
            MockRedeemData memory _mockRedeemData = mockRedeemDataArray[i];
            if (!_mockRedeemData.isExecuted) {
                // Transfer the required debt to the LeverageManager
                SafeERC20.safeTransferFrom(leverageTokenData.debtAsset, msg.sender, address(this), _mockRedeemData.debt);

                // Give the sender the required collateral
                deal(address(leverageTokenData.collateralAsset), address(this), _mockRedeemData.collateral);
                leverageTokenData.collateralAsset.transfer(msg.sender, _mockRedeemData.collateral);

                // Burn the sender's shares
                leverageTokenData.leverageToken.burn(msg.sender, _mockRedeemData.shares);

                // Set the mock redeem data to executed
                mockRedeemData[mockRedeemDataKey][i].isExecuted = true;
                return ActionData({
                    collateral: _mockRedeemData.collateral,
                    debt: _mockRedeemData.debt,
                    shares: _mockRedeemData.shares,
                    tokenFee: 0,
                    treasuryFee: 0
                });
            }
        }

        // If no mock redeem data is found, revert
        revert("No mock redeem data found for MockLeverageManager.redeem");
    }

    function rebalance(
        ILeverageToken leverageToken,
        RebalanceAction[] calldata actions,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        // Transfer tokens in from caller to this contract
        tokenIn.transferFrom(msg.sender, address(this), amountIn);

        for (uint256 i = 0; i < actions.length; i++) {
            address rebalanceAdapter = getLeverageTokenRebalanceAdapter(leverageToken);

            bool isEligible = IRebalanceAdapter(rebalanceAdapter).isEligibleForRebalance(
                leverageToken, leverageTokenStates[leverageToken], msg.sender
            );
            if (!isEligible) {
                revert("RebalanceAdapter is not eligible for rebalance");
            }
        }

        // Transfer tokens out from this contract to caller
        tokenOut.transfer(msg.sender, amountOut);
    }
}
