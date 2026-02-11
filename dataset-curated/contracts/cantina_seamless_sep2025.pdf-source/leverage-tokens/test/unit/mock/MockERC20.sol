// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {RebalanceAction, ActionType, LeverageTokenConfig} from "src/types/DataTypes.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";

enum ReentrancyCallType {
    None,
    Mint,
    Redeem,
    Rebalance,
    CreateNewLeverageToken
}

contract MockERC20 is ERC20Mock {
    uint8 private _decimals;

    ILeverageManager internal leverageManager;
    ReentrancyCallType internal reentrancyCallType;

    constructor() {
        _decimals = 18;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mockSetDecimals(uint8 decimalAmount) external {
        _decimals = decimalAmount;
    }

    function mockSetReentrancyCallType(ReentrancyCallType _reentrancyCallType) external {
        reentrancyCallType = _reentrancyCallType;
    }

    function mockSetLeverageManager(ILeverageManager _leverageManager) external {
        leverageManager = _leverageManager;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        _executeDummyReentrancyCall();
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _executeDummyReentrancyCall();
        return super.transferFrom(from, to, value);
    }

    function _executeDummyReentrancyCall() internal {
        if (leverageManager != ILeverageManager(address(0))) {
            require(
                LeverageManagerHarness(address(leverageManager)).exposed_getReentrancyGuardTransientStorage() == true,
                "ReentrancyGuardTransient transient storage should be set to true"
            );
        }

        if (leverageManager == ILeverageManager(address(0)) || reentrancyCallType == ReentrancyCallType.None) {
            return;
        }

        if (reentrancyCallType == ReentrancyCallType.Mint) {
            leverageManager.mint(ILeverageToken(address(0)), 10 ether, 10 ether);
        } else if (reentrancyCallType == ReentrancyCallType.Redeem) {
            leverageManager.redeem(ILeverageToken(address(0)), 10 ether, 10 ether);
        } else if (reentrancyCallType == ReentrancyCallType.Rebalance) {
            RebalanceAction[] memory actions = new RebalanceAction[](1);
            actions[0] = RebalanceAction({actionType: ActionType.AddCollateral, amount: 10 ether});
            leverageManager.rebalance(
                ILeverageToken(address(0)), actions, IERC20(address(this)), IERC20(address(0)), 10 ether, 0
            );
        } else if (reentrancyCallType == ReentrancyCallType.CreateNewLeverageToken) {
            leverageManager.createNewLeverageToken(
                LeverageTokenConfig({
                    lendingAdapter: ILendingAdapter(address(0)),
                    rebalanceAdapter: IRebalanceAdapter(address(0)),
                    mintTokenFee: 0,
                    redeemTokenFee: 0
                }),
                "dummy name",
                "dummy symbol"
            );
        }
    }
}
