// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolBase, FeeInfo, IERC20, SafeERC20, CalculatorBase, MathLibs, packedFloat, Float} from "lib/liquidity-base/src/amm/base/PoolBase.sol";
import "lib/liquidity-base/src/common/IErrors.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {ALTBCPoolDeployed, LiquidityDeposited, LiquidityWithdrawn} from "src/common/IALTBCEvents.sol";

/**
 * @title Adjustable Linear TBC Pool
 * @dev This contract serves the purpose of facilitating swaps between a pair
 * of tokens, where one is an xToken and the other one is a yToken.
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

contract ALTBCPool is PoolBase {
    using SafeERC20 for IERC20;
    using ALTBCEquations for ALTBCDef;
    using ALTBCEquations for uint256;
    using MathLibs for int256;
    using ALTBCEquations for packedFloat;
    using MathLibs for packedFloat;

    ALTBCDef public tbc;

    /**
     * @dev constructor
     * @param _xToken address of the X token (x axis)
     * @param _yToken address of the Y token (y axis)
     * @param fees fee infomation
     * @param _tbcInput input parameters for the TBC
     */
    constructor(
        address _xToken,
        address _yToken,
        FeeInfo memory fees,
        ALTBCInput memory _tbcInput,
        string memory _name,
        string memory _symbol
    ) PoolBase(_xToken, _yToken, fees, _name, _symbol) {
        _validateTBC(_tbcInput);

        tbc.V = int(_tbcInput._V).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.xMin = int(_tbcInput._xMin).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.C = int(_tbcInput._C).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.calculateBn(x);
        tbc.c = int(_tbcInput._lowerPrice).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        _wInactive = int(_tbcInput._wInactive).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);

        emit ALTBCPoolDeployed(_xToken, _yToken, VERSION, fees._lpFee, fees._protocolFee, fees._protocolFeeCollector, _tbcInput);
    }

    function initializePool(address deployer) external onlyOwner {
        uint256 initialLiq = IERC20(xToken).balanceOf(address(this));
        if (initialLiq == 0) revert NoInitialLiquidity();

        _w = int(initialLiq).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.xMax = tbc.xMin.add(_w);

        x = tbc.xMin;
        _updateParameters(packedFloat.wrap(0));

        packedFloat D0 = tbc.calculateDn(x);
        packedFloat initialRJ = D0.div((_w.sub(_wInactive)));
        if (_wInactive.gt(ALTBCEquations.FLOAT_0))
            _mintTokenAndUpdate(
                deployer,
                _wInactive,
                type(int256).max.toPackedFloat(0),
                true,
                IERC20(xToken).balanceOf(address(this)),
                IERC20(yToken).balanceOf(address(this))
            );

        _mintTokenAndUpdate(
            deployer,
            int(initialLiq).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE),
            initialRJ,
            false,
            IERC20(xToken).balanceOf(address(this)),
            IERC20(yToken).balanceOf(address(this))
        );

        _transferOwnership(deployer);
    }

    /**
     * @dev This is the function to activate/deactivate trading.
     * @param _enable pass True to enable or False to disable
     * @notice Only the owner of the pool can call this function.
     */
    function enableSwaps(bool _enable) external override onlyOwner {
        _enable ? _unpause() : _pause();
    }

    /**
     * @dev This is the function to simulate a liquidity deposit into the pool.
     * @param _A The amount of xToken being deposited as liquidity in the simulation.
     * @param _B The amount of yToken being deposited as liquidity in the simulation.
     * @return A calculated A value 
     * @return B calculated B value
     * @return Q calculated Q value
     * @return wj calculated wj value
     */
    function simulateLiquidityDeposit(uint256 _A, uint256 _B) public returns (uint256 A, uint256 B, uint256 Q, packedFloat wj) {
        (packedFloat AFloat, packedFloat BFloat, packedFloat qFloat) = tbc.calculateQ(
            x,
            int(_A).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE),
            int(_B).toPackedFloat(int(yDecimalDiff) - int(POOL_NATIVE_DECIMALS)),
            tbc.calculateL(x),
            tbc.calculateDn(x)
        );

        wj = qFloat.mul(_w);

        packedFloat multiplier = ALTBCEquations.FLOAT_1.add(qFloat);

        x = tbc._liquidityUpdateHelper(x, multiplier);
        _w = _w.add(wj); // add the additional liquidity to the total liquidity

        packedFloat L = tbc.calculateL(x);
        tbc.calculateZ(L, _w, _wInactive, qFloat, false);
        h = tbc.calculateH(L, _w, _wInactive, _collectedLPFees);
        A = uint(AFloat.convertpackedFloatToWAD());
        B = uint(BFloat.convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)));
        Q = uint(qFloat.convertpackedFloatToWAD());
    }

    /**
     * @dev This is the function to deposit liquidity into the pool.
     * @notice If the tokenId provided is owned by the lp, this tokenId will be updated based on liquidity deposit
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param _A The amount of xToken being deposited as liquidity.
     * @param _B The amount of yToken being deposited as liquidity.
     * @return A calculated A value 
     * @return B calculated B value
     * @return Q calculated Q value
     */
    function depositLiquidity(uint256 tokenId, uint256 _A, uint256 _B) external returns (uint256 A, uint256 B, uint256 Q) {
        // Inactive NFT check
        if (tokenId == INACTIVE_ID) {
            revert CannotDepositInactiveLiquidity();
        }

        packedFloat wj;
        (A, B, Q, wj) = simulateLiquidityDeposit(_A > 0 ? _A - 1 : _A, _B > 0 ? _B - 1 : _B);

        // Add one too each for rounding purposes
        if(A > 0) {
            IERC20(xToken).safeTransferFrom(_msgSender(), address(this), A + 1);
        }
        if(B > 0) {
            IERC20(yToken).safeTransferFrom(_msgSender(), address(this), B + 1);
        }

        uint256 _tokenId = _depositLiquidityNFTUpdates(tokenId, wj, _A, _B);
        emit LiquidityDeposited(_msgSender(), _tokenId, _A, _B);
    }

    function _depositLiquidityNFTUpdates(uint256 tokenId, packedFloat wj, uint256 _A, uint256 _B) private returns (uint256 _tokenId) {
        // Update lp's position or mint a new LP Token
        if (tokenId == 0) {
            _mintTokenAndUpdate(
                _msgSender(),
                wj,
                h,
                false,
                _A,
                _B
            );
            _tokenId = currentTokenId; // tokenId in the ERC721 that was just minted
        } else if (ownerOf(tokenId) == _msgSender()) {
            _tokenId = tokenId;
            (packedFloat w_hat, packedFloat r_hat) = getLPToken(_msgSender(), tokenId);
            _updateLPTokenVarsDeposit(_msgSender(), tokenId, wj, h.calculateLastRevenueClaim(wj, r_hat, w_hat));
        } else {
            revert("ALTBCPool: lp does not own tokenId");
        }
    }

    function withdrawLiquidity(uint256 tokenId, uint256 uj) external {
        if (uj == 0) revert ZeroValueNotAllowed();
        if (ownerOf(tokenId) != _msgSender()) revert InvalidToken();

        // Get packedFloat variables
        packedFloat _uj = int(uj).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        {
            packedFloat L = tbc.calculateL(x);
            h = tbc.calculateH(L, _w, _wInactive, _collectedLPFees);
        }

        // STEP 1 - Get q and multiplier
        packedFloat q = _uj.div(_w);
        packedFloat multiplier = ALTBCEquations.FLOAT_1.sub(q);

        // STEP 2 - Calc amount out
        uint256 Ax = uint(q.mul(tbc.xMax.sub(x)).convertpackedFloatToWAD());

        uint256 Ay = uint(q.mul(tbc.calculateDn(x).sub(tbc.calculateL(x))).convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)));

        x = tbc._liquidityUpdateHelper(x, multiplier);

        // STEP 7 - Update LPToken and W
        _w = _w.sub(_uj);
        if (tokenId == INACTIVE_ID) {
            _wInactive = _wInactive.sub(_uj);
        }

        if (_w.sub(_wInactive).le(ALTBCEquations.FLOAT_0) && _wInactive.gt(ALTBCEquations.FLOAT_0)) {
            revert AllLiquidityCannotBeInactive();
        }

        packedFloat rj = _updateLPTokenVarsWithdrawal(_msgSender(), tokenId, _uj);

        // Update Ay to include any revenue accrued
        uint256 revenueAccrued = uint(_uj.mul(h.sub(rj)).convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)));
        Ay += revenueAccrued;

        if (tokenId == INACTIVE_ID) {
            tbc.Zn = tbc.Zn.add((q.mul(tbc.calculateL(x))));
        } else {
            tbc.calculateZ(tbc.calculateL(x), _w, _wInactive, q, true);
        }

        // Transfer the liquidity amounts to the lp
        IERC20(xToken).safeTransfer(_msgSender(), Ax);
        IERC20(yToken).safeTransfer(_msgSender(), _normalizeTokenDecimals(false, Ay));

        emit LiquidityWithdrawn(_msgSender(), tokenId, Ax, Ay, revenueAccrued);
    }

    function withdrawRevenue(uint256 tokenId, uint256 Q) external returns (uint256 revenue) {
        if (ownerOf(tokenId) != _msgSender()) revert InvalidToken();
        packedFloat _Q = int(Q).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);

        ( , , packedFloat _wj, packedFloat _rj, packedFloat revenueAvailable, ) = _getRevenueAvailable(
            _msgSender(),
            tokenId
        );

        if (_Q.gt(revenueAvailable)) revert("ALTBCPool: Q too high");
        packedFloat updatedRj = _rj.add(_Q.div(_wj));
        lpToken[_msgSender()][tokenId].rj = updatedRj;
        r += Q;
        revenue = _normalizeTokenDecimals(false, Q);
        IERC20(yToken).safeTransfer(_msgSender(), revenue);
    }

    function revenueAvailable(address lp, uint256 tokenId) public view returns (uint256 _revenueAvailable) {
        (, , , , , _revenueAvailable) = _getRevenueAvailable(lp, tokenId);
    }

    function _getRevenueAvailable(
        address lp,
        uint256 tokenId
    )
        internal
        view
        returns (
            packedFloat L,
            packedFloat hn,
            packedFloat _wj,
            packedFloat _rj,
            packedFloat _revenueAvailable,
            uint256 revenueAvailableUint
        )
    {
        L = tbc.calculateL(x);
        hn = tbc.calculateH(L, _w, _wInactive, _collectedLPFees);
        (_wj, _rj) = getLPToken(_msgSender(), tokenId);
        _revenueAvailable = _wj.calculateRevenueAvailable(hn, _rj);
        revenueAvailableUint = uint(_revenueAvailable.convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)));

    }

    /**
     * @dev This is the function to retrieve the current spot price of the x token.
     * @return sPrice the price in YToken Decimals
     * @notice x + 1 is used for returning the price of the next token sold, not the price of the last token sold
     */
    function _spotPrice() internal view override returns (packedFloat sPrice) {
        // Price P(N+1) = f(x(n+1));
        sPrice = tbc.calculatefx(x.add(int(1).toPackedFloat(0)));
    }

    /**
     * @dev This function updates the state of the math values of the pool.
     * @param x_old This parameter is not used in this function and is only present for backwards compatibility with the interface.
     */
    function _updateParameters(packedFloat x_old) public override {
        x_old;
        // Calculate Dn using Bn and cn before they get updated
        packedFloat oldBn = tbc.b;
        oldBn;
        // Calculate Bn (Sn)
        tbc.calculateBn(x);
        // we update c only if x is not zero
        if (packedFloat.unwrap(x) > 0) tbc.calculateCNew(x, oldBn);
    }

    /**
     * @dev This function calculates the amount of token X required for the user to purchase a specific amount of Token Y (buy y with x : out perspective).
     * @param _amountOfY desired amount of token Y
     * @return amountOfX required amount of token X
     */
    function _calculateAmountOfXRequiredBuyingY(packedFloat _amountOfY) internal view override returns (packedFloat amountOfX) {
        // xn - F^-1(y - y_in)
        packedFloat Fx = tbc.calculateDn(x);

        if (Fx.sub(_amountOfY).lt((tbc.b.div(ALTBCEquations.FLOAT_2).mul((tbc.xMin.mul(tbc.xMin)))).add(tbc.c.mul(tbc.xMin)))) {
            revert NotEnoughCollateral();
        }

        packedFloat _updatedX = tbc.calculateXofNPlus1(Fx.sub(_amountOfY)); // XOutOfBounds is impossible to be triggered in this scenario. arithmetic overflow instead
        amountOfX = x.sub(_updatedX);
    }

    /**
     * @dev This function calculates the amount of token Y required for the user to purchase a specific amount of Token X (buy x with y : out perspective).
     * @param _amountOfX desired amount of token X
     * @return amountOfY required amount of token Y
     */
    function _calculateAmountOfYRequiredBuyingX(packedFloat _amountOfX) internal view override returns (packedFloat amountOfY) {
        // D(x + q) - D(x)
        packedFloat _updatedX = x.add(_amountOfX);
        if (_updatedX.gt(tbc.xMax)) revert XOutOfBounds(uint(_updatedX.sub(tbc.xMax).sub(tbc.xMin).convertpackedFloatToWAD()));
        packedFloat Fx = tbc.calculateDn(x);
        packedFloat updatedFx = tbc.calculateDn(_updatedX);
        amountOfY = updatedFx.sub(Fx);
    }

    /**
     * @dev This function calculates the amount of token Y the user will receive when selling token X (sell x for y : in perspective).
     * @param _amountOfX amount of token X to be sold
     * @return amountOfY amount of token Y to be received
     */
    function _calculateAmountOfYReceivedSellingX(packedFloat _amountOfX) internal view override returns (packedFloat amountOfY) {
        // F(xn)-F(xn-q)
        if (x.lt(_amountOfX)) revert BeyondLiquidity();
        if (tbc.xMin.gt(x.sub(_amountOfX))) revert XOutOfBounds(uint(tbc.xMin.add(_amountOfX.sub(x)).convertpackedFloatToWAD()));
        packedFloat _updatedX = x.sub(_amountOfX);
        packedFloat Fx = tbc.calculateDn(x);
        packedFloat updatedFx = tbc.calculateDn(_updatedX);
        amountOfY = Fx.sub(updatedFx);
    }

    /**
     * This function calculates the amount of token X the user will receive when selling token Y (sell y for x : in perspective).
     * @param _amountOfY amount of token Y to be sold
     * @return amountOfX amount of token X to be received
     */
    function _calculateAmountOfXReceivedSellingY(packedFloat _amountOfY) internal view override returns (packedFloat amountOfX) {
        // F^-1(F(x) + q) - x
        packedFloat Fx = tbc.calculateDn(x);

        if (Fx.add(_amountOfY).gt((tbc.b.div(ALTBCEquations.FLOAT_2).mul((tbc.xMax.mul(tbc.xMax)))).add(tbc.c.mul(tbc.xMax)))) {
            revert DnTooLarge();
        }

        packedFloat _updatedX = tbc.calculateXofNPlus1(Fx.add(_amountOfY));

        amountOfX = _updatedX.sub(x);
    }
    /**
     * @dev This function cleans the state of the calculator in the case of the pool closing.
     */
    function _clearState() internal override {
        delete tbc;
    }

    /**
     * @dev A helper function to validate most of constructor's inputs.
     * @param _tbcInput input parameters for the TBC
     */
    function _validateTBC(ALTBCInput memory _tbcInput) internal pure {
        if (_tbcInput._C == 0) revert CCannotBeZero();
        if (_tbcInput._V == 0) revert VCannotBeZero();
        if (_tbcInput._xMin == 0) revert xMinCannotBeZero();
    }

    /**
     * @dev This function validates the liquidity addition to ensure it does not exceed the max supply of xToken.
     * @param afterBalance the balance of xToken after the addition
     */
    function _validateLiquidityAdd(packedFloat afterBalance) internal view virtual override {
        if (afterBalance.add(x).gt(tbc.xMax.add(tbc.xMin)))
            revert XOutOfBounds((uint(afterBalance.add(x).sub(tbc.xMax.sub(tbc.xMin)).convertpackedFloatToWAD())));
    }

    /**
     * @dev This function gets revenue data for an lp and tokenId
     * @param lp the address of the liquidity provider
     * @param tokenId the id of the LP token to withdraw revenue for
     * @return rj the claimed revenue per liquidity unit for the specified token
     * @return wj the liquidity units of the specified token
     * @return hn the total revenue per liquidity unit for the pool
     */
    function _getRevenueInfoForToken(address lp, uint256 tokenId) internal view returns (uint256 rj, uint256 wj, uint256 hn) {
        packedFloat _wj;
        packedFloat _rj;
        (_wj, _rj) = getLPToken(lp, tokenId);
        wj = uint(_wj.convertpackedFloatToWAD());
        rj = uint(_rj.convertpackedFloatToWAD());
        packedFloat L;
        hn = uint(tbc.calculateH(L, _w, _wInactive, _collectedLPFees).convertpackedFloatToWAD());
    }
}
