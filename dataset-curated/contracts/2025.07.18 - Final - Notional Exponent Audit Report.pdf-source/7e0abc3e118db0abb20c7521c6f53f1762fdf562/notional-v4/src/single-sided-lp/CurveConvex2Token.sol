// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IWithdrawRequestManager} from "../interfaces/IWithdrawRequestManager.sol";
import {AbstractSingleSidedLP, BaseLPLib} from "./AbstractSingleSidedLP.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {ETH_ADDRESS, ALT_ETH_ADDRESS, WETH, CHAIN_ID_MAINNET} from "../utils/Constants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/Curve/ICurve.sol";
import "../interfaces/Curve/IConvex.sol";

struct DeploymentParams {
    address pool;
    address poolToken;
    address gauge;
    address convexRewardPool;
    CurveInterface curveInterface;
}

contract CurveConvex2Token is AbstractSingleSidedLP {

    uint256 internal constant _NUM_TOKENS = 2;

    ERC20 internal immutable CURVE_POOL_TOKEN;
    uint8 internal immutable _PRIMARY_INDEX;
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;

    function NUM_TOKENS() internal pure override returns (uint256) { return _NUM_TOKENS; }
    function PRIMARY_INDEX() internal view override returns (uint256) { return _PRIMARY_INDEX; }
    function TOKENS() internal view override returns (ERC20[] memory) {
        ERC20[] memory tokens = new ERC20[](_NUM_TOKENS);
        tokens[0] = ERC20(TOKEN_1);
        tokens[1] = ERC20(TOKEN_2);
        return tokens;
    }

    constructor(
        uint256 _maxPoolShare,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _rewardManager,
        DeploymentParams memory params,
        IWithdrawRequestManager _withdrawRequestManager
    ) AbstractSingleSidedLP(_maxPoolShare, _asset, _yieldToken, _feeRate, _rewardManager, 18, _withdrawRequestManager) {
        CURVE_POOL_TOKEN = ERC20(params.poolToken);

        // We interact with curve pools directly so we never pass the token addresses back
        // to the curve pools. The amounts are passed back based on indexes instead. Therefore
        // we can rewrite the token addresses from ALT Eth (0xeeee...) back to (0x0000...) which
        // is used by the vault internally to represent ETH.
        TOKEN_1 = _rewriteAltETH(ICurvePool(params.pool).coins(0));
        TOKEN_2 = _rewriteAltETH(ICurvePool(params.pool).coins(1));

        // Assets may be WETH, so we need to unwrap it in this case.
        _PRIMARY_INDEX =
            (TOKEN_1 == _asset || (TOKEN_1 == ETH_ADDRESS && _asset == address(WETH))) ? 0 :
            (TOKEN_2 == _asset || (TOKEN_2 == ETH_ADDRESS && _asset == address(WETH))) ? 1 :
            // Otherwise the primary index is not set and we will not be able to enter or exit
            // single sided.
            type(uint8).max;

        LP_LIB = address(new CurveConvexLib(TOKEN_1, TOKEN_2, _asset, _PRIMARY_INDEX, params));
    }

    function _rewriteAltETH(address token) private pure returns (address) {
        return token == address(ALT_ETH_ADDRESS) ? ETH_ADDRESS : address(token);
    }

    function _transferYieldTokenToOwner(address owner, uint256 yieldTokens) internal override {
        _delegateCall(LP_LIB, abi.encodeWithSelector(
            CurveConvexLib.transferYieldTokenToOwner.selector, owner, yieldTokens)
        );
    }

    function _totalPoolSupply() internal view override returns (uint256) {
        return CURVE_POOL_TOKEN.totalSupply();
    }

    function _checkReentrancyContext() internal override {
        CurveConvexLib(payable(LP_LIB)).checkReentrancyContext();
    }
}

contract CurveConvexLib is BaseLPLib {
    using SafeERC20 for ERC20;
    using TokenUtils for ERC20;

    uint256 internal constant _NUM_TOKENS = 2;

    address internal immutable CURVE_POOL;
    ERC20 internal immutable CURVE_POOL_TOKEN;

    /// @dev Curve gauge contract used when there is no convex reward pool
    address internal immutable CURVE_GAUGE;
    /// @dev Convex booster contract used for staking BPT
    address internal immutable CONVEX_BOOSTER;
    /// @dev Convex reward pool contract used for unstaking and claiming reward tokens
    address internal immutable CONVEX_REWARD_POOL;
    uint256 internal immutable CONVEX_POOL_ID;

    uint8 internal immutable _PRIMARY_INDEX;
    address internal immutable ASSET;
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    CurveInterface internal immutable CURVE_INTERFACE;

    // Payable is required for the CurveV1 interface which will execute a transfer
    // when the remove_liquidity function is called, it only will be done to this contract
    // during the checkReentrancyContext function.
    receive() external payable {}

    constructor(
        address _token1,
        address _token2,
        address _asset,
        uint8 _primaryIndex,
        DeploymentParams memory params
    ) {
        TOKEN_1 = _token1;
        TOKEN_2 = _token2;
        ASSET = _asset;
        _PRIMARY_INDEX = _primaryIndex;

        CURVE_POOL = params.pool;
        CURVE_GAUGE = params.gauge;
        CURVE_POOL_TOKEN = ERC20(params.poolToken);
        CURVE_INTERFACE = params.curveInterface;

        // If the convex reward pool is set then get the booster and pool id, if not then
        // we will stake on the curve gauge directly.
        CONVEX_REWARD_POOL = params.convexRewardPool;
        address convexBooster;
        uint256 poolId;
        if (block.chainid == CHAIN_ID_MAINNET && CONVEX_REWARD_POOL != address(0)) {
            convexBooster = IConvexRewardPool(CONVEX_REWARD_POOL).operator();
            poolId = IConvexRewardPool(CONVEX_REWARD_POOL).pid();
        }

        CONVEX_POOL_ID = poolId;
        CONVEX_BOOSTER = convexBooster;
    }

    function checkReentrancyContext() external {
        uint256[2] memory minAmounts;
        if (CURVE_INTERFACE == CurveInterface.V1) {
            ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(0, minAmounts);
        } else if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
            // Total supply on stable swap has a non-reentrant lock
            ICurveStableSwapNG(CURVE_POOL).totalSupply();
        } else if (CURVE_INTERFACE == CurveInterface.V2) {
            // Curve V2 does a `-1` on the liquidity amount so set the amount removed to 1 to
            // avoid an underflow.
            ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(1, minAmounts, true, address(this));
        } else {
            revert();
        }
    }

    function TOKENS() internal view override returns (ERC20[] memory) {
        ERC20[] memory tokens = new ERC20[](_NUM_TOKENS);
        tokens[0] = ERC20(TOKEN_1);
        tokens[1] = ERC20(TOKEN_2);
        return tokens;
    }

    function initialApproveTokens() external {
        // If either token is ETH_ADDRESS the check approve will short circuit
        ERC20(TOKEN_1).checkApprove(address(CURVE_POOL), type(uint256).max);
        ERC20(TOKEN_2).checkApprove(address(CURVE_POOL), type(uint256).max);
        if (CONVEX_BOOSTER != address(0)) {
            CURVE_POOL_TOKEN.checkApprove(address(CONVEX_BOOSTER), type(uint256).max);
        } else {
            CURVE_POOL_TOKEN.checkApprove(address(CURVE_GAUGE), type(uint256).max);
        }
    }

    function joinPoolAndStake(
        uint256[] memory _amounts, uint256 minPoolClaim
    ) external {
        // Although Curve uses ALT_ETH to represent native ETH, it is rewritten in the Curve2TokenPoolMixin
        // to the Deployments.ETH_ADDRESS which we use internally.
        uint256 msgValue;
        if (TOKEN_1 == ETH_ADDRESS) {
            msgValue = _amounts[0];
        } else if (TOKEN_2 == ETH_ADDRESS) {
            msgValue = _amounts[1];
        }
        if (msgValue > 0) WETH.withdraw(msgValue);

        uint256 lpTokens = _enterPool(_amounts, minPoolClaim, msgValue);

        _stakeLpTokens(lpTokens);
    }

    function unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) external returns (uint256[] memory exitBalances) {
        _unstakeLpTokens(poolClaim);

        exitBalances = _exitPool(poolClaim, _minAmounts, isSingleSided);

        if (ASSET == address(WETH)) {
            if (TOKEN_1 == ETH_ADDRESS) {
                WETH.deposit{value: exitBalances[0]}();
            } else if (TOKEN_2 == ETH_ADDRESS) {
                WETH.deposit{value: exitBalances[1]}();
            }
        }
    }

    function transferYieldTokenToOwner(address owner, uint256 yieldTokens) external {
        _unstakeLpTokens(yieldTokens);
        CURVE_POOL_TOKEN.safeTransfer(owner, yieldTokens);
    }

    function _enterPool(
        uint256[] memory _amounts, uint256 minPoolClaim, uint256 msgValue
    ) internal returns (uint256) {
        if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
            return ICurveStableSwapNG(CURVE_POOL).add_liquidity{value: msgValue}(
                _amounts, minPoolClaim
            );
        } 

        uint256[2] memory amounts;
        amounts[0] = _amounts[0];
        amounts[1] = _amounts[1];
        if (CURVE_INTERFACE == CurveInterface.V1) {
            return ICurve2TokenPoolV1(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim
            );
        } else if (CURVE_INTERFACE == CurveInterface.V2) {
            return ICurve2TokenPoolV2(CURVE_POOL).add_liquidity{value: msgValue}(
                amounts, minPoolClaim, 0 < msgValue // use_eth = true if msgValue > 0
            );
        }

        revert();
    }

    function _exitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) internal returns (uint256[] memory exitBalances) {
        if (isSingleSided) {
            exitBalances = new uint256[](_NUM_TOKENS);
            if (CURVE_INTERFACE == CurveInterface.V1 || CURVE_INTERFACE == CurveInterface.StableSwapNG) {
                // Method signature is the same for v1 and stable swap ng
                exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity_one_coin(
                    poolClaim, int8(_PRIMARY_INDEX), _minAmounts[_PRIMARY_INDEX]
                );
            } else {
                exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity_one_coin(
                    // Last two parameters are useEth = true and receiver = this contract
                    poolClaim, _PRIMARY_INDEX, _minAmounts[_PRIMARY_INDEX], true, address(this)
                );
            }
        } else {
            // Two sided exit
            if (CURVE_INTERFACE == CurveInterface.StableSwapNG) {
                return ICurveStableSwapNG(CURVE_POOL).remove_liquidity(poolClaim, _minAmounts);
            }
            
            // Redeem proportionally, min amounts are rewritten to a fixed length array
            uint256[2] memory minAmounts;
            minAmounts[0] = _minAmounts[0];
            minAmounts[1] = _minAmounts[1];

            exitBalances = new uint256[](_NUM_TOKENS);
            if (CURVE_INTERFACE == CurveInterface.V1) {
                uint256[2] memory _exitBalances = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(poolClaim, minAmounts);
                exitBalances[0] = _exitBalances[0];
                exitBalances[1] = _exitBalances[1];
            } else {
                exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1);
                exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2);
                // Remove liquidity on CurveV2 does not return the exit amounts so we have to measure
                // them before and after.
                ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(
                    // Last two parameters are useEth = true and receiver = this contract
                    poolClaim, minAmounts, true, address(this)
                );
                exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1) - exitBalances[0];
                exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2) - exitBalances[1];
            }
        }
    }

    function _stakeLpTokens(uint256 lpTokens) internal {
        if (CONVEX_BOOSTER != address(0)) {
            bool success = IConvexBooster(CONVEX_BOOSTER).deposit(CONVEX_POOL_ID, lpTokens, true);
            require(success);
        } else {
            ICurveGauge(CURVE_GAUGE).deposit(lpTokens);
        }
    }


    function _unstakeLpTokens(uint256 poolClaim) internal {
        if (CONVEX_REWARD_POOL != address(0)) {
            bool success = IConvexRewardPool(CONVEX_REWARD_POOL).withdrawAndUnwrap(poolClaim, false);
            require(success);
        } else {
            ICurveGauge(CURVE_GAUGE).withdraw(poolClaim);
        }
    }

}