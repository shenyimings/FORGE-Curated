// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {PoolBase, FeeInfo, IERC20, SafeERC20, CalculatorBase, MathLibs, packedFloat} from "lib/liquidity-base/src/amm/base/PoolBase.sol";
import "lib/liquidity-base/src/common/IErrors.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {ALTBCPoolDeployed, ALTBCCurveState} from "src/common/IALTBCEvents.sol";
import {Initializable} from "lib/liquidity-base/lib/solady/src/utils/Initializable.sol";
import {SafeCast} from "lib/liquidity-base/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {ILPToken} from "lib/liquidity-base/src/common/ILPToken.sol";

/**
 * @title Adjustable Linear TBC Pool
 * @dev This contract serves the purpose of facilitating swaps between a pair
 * of tokens, where one is an xToken and the other one is a yToken.
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

contract ALTBCPool is PoolBase, Initializable {
    using SafeERC20 for IERC20;
    using ALTBCEquations for ALTBCDef;
    using ALTBCEquations for uint256;
    using MathLibs for int256;
    using ALTBCEquations for packedFloat;
    using MathLibs for packedFloat;
    using SafeCast for uint;
    using SafeCast for int;

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
        address _lpToken,
        uint256 _inactiveLpId,
        FeeInfo memory fees,
        ALTBCInput memory _tbcInput,
        string memory _VERSION
    ) PoolBase(_xToken, _yToken, _lpToken, _inactiveLpId, fees) {
        _validateTBC(_tbcInput);

        tbc.V = int(_tbcInput._V).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.xMin = int(_tbcInput._xMin).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.C = int(_tbcInput._C).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.calculateBn(x);
        tbc.c = int(_tbcInput._lowerPrice).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);

        emit ALTBCPoolDeployed(_xToken, _yToken, _VERSION, fees._lpFee, fees._protocolFee, fees._protocolFeeCollector, _tbcInput);
    }

    /**
     * @dev This is the function to initialize the pool.
     * @param deployer The address of the deployer
     * @param ___wInactive initial inactive liquidity for the pool
     */
    function initializePool(address deployer, uint256 initialLiq, uint256 ___wInactive) external onlyOwner initializer {
        _w = int(initialLiq).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        packedFloat __wInactive = int(___wInactive).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        tbc.xMax = tbc.xMin.add(_w);
        packedFloat wActive = _w.sub(__wInactive);
        checkInactiveLiquidity(wActive, __wInactive);

        x = tbc.xMin;
        _updateParameters();

        packedFloat D0 = tbc.calculateDn(x);
        packedFloat initialRJ = D0.div((_w.sub(__wInactive)));
        ILPToken(lpToken).mintTokenAndUpdate(deployer, __wInactive, type(int256).max.toPackedFloat(0));
        emit PositionMinted(inactiveLpId, _msgSender(), true);
        emit LiquidityDeposited(deployer, inactiveLpId, ___wInactive, 0);

        ILPToken(lpToken).mintTokenAndUpdate(deployer, wActive, initialRJ);
        emit PositionMinted(activeLpId, _msgSender(), false);
        emit LiquidityDeposited(deployer, activeLpId, initialLiq - ___wInactive, 0);
        _emitCurveState();
        _transferOwnership(deployer);
    }

    /**
     * @dev This is the function to simulate a liquidity deposit into the pool.
     * @param _A The amount of xToken being deposited as liquidity in the simulation.
     * @param _B The amount of yToken being deposited as liquidity in the simulation.
     * @return A calculated A value which is the amount of xToken that will be deposited
     * @return B calculated B value which is the amount of yToken that will be deposited
     * @return Q calculated Q value which is the ratio of this provided liquidity unit to the total liquidity of the pool
     * @return ratio calculated ratio of xToken to yToken required for the deposit
     * @return qFloat calculated qFloat value which is the ratio of this provided liquidity unit to the total liquidity of the pool in packedFloat format
     */
    function simulateLiquidityDeposit(
        uint256 _A,
        uint256 _B
    ) public view returns (uint256 A, uint256 B, uint256 Q, int256 ratio, packedFloat qFloat, packedFloat L) {
        packedFloat AFloat;
        packedFloat BFloat;
        L = tbc.calculateL(x);
        (AFloat, BFloat, qFloat) = tbc.calculateQ(
            x,
            (_A.toInt256()).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE),
            (_B.toInt256()).toPackedFloat(int(yDecimalDiff) - int(POOL_NATIVE_DECIMALS)),
            L,
            tbc.calculateDn(x)
        );
        A = AFloat.convertpackedFloatToWAD().toUint256();
        B = BFloat.convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)).toUint256();
        Q = qFloat.convertpackedFloatToWAD().toUint256();
        if (BFloat.lt(ALTBCEquations.FLOAT_WAD)) {
            ratio = type(int256).max; // The closest we can get to infinity
        } else {
            ratio = AFloat.div(BFloat).convertpackedFloatToDoubleWAD();
        }
    }

    function tokenDepositUpdate(uint256 tokenId, packedFloat wj) internal returns (uint256) {
        packedFloat h = retrieveH();
        if (tokenId == 0) {
            tokenId = ILPToken(lpToken).mintTokenAndUpdate(_msgSender(), wj, h);
            emit PositionMinted(tokenId, _msgSender(), false);
        } else {
            (packedFloat w_hat, packedFloat r_hat) = ILPToken(lpToken).getLPToken(tokenId);
            packedFloat newWj = wj.add(w_hat);
            packedFloat newRj = h.calculateLastRevenueClaim(wj, r_hat, w_hat);
            ILPToken(lpToken).updateLPToken(tokenId, newWj, newRj);
        }

        return tokenId;
    }

    /**
     * @dev This is the function to deposit liquidity into the pool.
     * @notice If the tokenId provided is owned by the lp, this tokenId will be updated based on liquidity deposit
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param _A The amount of xToken being deposited as liquidity.
     * @param _B The amount of yToken being deposited as liquidity.
     * @param _minA The minimum acceptable amount of xToken actually deposited as liquidity.
     * @param _minB The minimum acceptable amount of yToken actually deposited as liquidity.
     * @param expires Timestamp at which the deposit transaction will expire.
     * @return A calculated A value
     * @return B calculated B value
     */
    function depositLiquidity(
        uint256 tokenId,
        uint256 _A,
        uint256 _B,
        uint256 _minA,
        uint256 _minB,
        uint256 expires
    ) external whenNotPaused checkExpiration(expires) returns (uint256 A, uint256 B) {
        // Inactive NFT check
        if (tokenId == inactiveLpId) {
            revert CannotDepositInactiveLiquidity();
        }

        packedFloat L;
        packedFloat qFloat;

        (A, B, , , qFloat, L) = simulateLiquidityDeposit(_A, _B);
        if (A == 0 && B == 0) revert ZeroValueNotAllowed();

        _checkSlippage(A, _minA);
        _checkSlippage(B, _minB);

        IERC20(xToken).safeTransferFrom(_msgSender(), address(this), A);
        IERC20(yToken).safeTransferFrom(_msgSender(), address(this), B);

        tbc.calculateZ(L, _w, _wInactive(), qFloat, false);

        packedFloat wj = qFloat.mul(_w);

        packedFloat multiplier = ALTBCEquations.FLOAT_1.add(qFloat);

        x = tbc._liquidityUpdateHelper(x, multiplier);
        _w = _w.add(wj); // add the additional liquidity to the total liquidity

        tokenId = tokenDepositUpdate(tokenId, wj);
        emit LiquidityDeposited(_msgSender(), tokenId, A, B);
        _emitCurveState();
    }

    /**
     * @dev This is the function to simulate a liquidity withdrawal from the pool.
     * @dev To get rj and uj, call the getLPToken function and pass in the rj and uj values
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param uj The amount of liquidity being withdrawn
     * @param rj The revenue accrued to the liquidity position
     * @param _uj The amount of liquidity being withdrawn in packedFloat format
     * @return Ax The amount of xToken to be received
     * @return Ay The amount of yToken to be received
     * @return revenueAccrued The amount of revenue accrued to the liquidity position
     * @return q The ratio of this provided liquidity unit to the total liquidity of the pool
     */
    function simulateWithdrawLiquidity(
        uint256 tokenId,
        uint256 uj,
        packedFloat _uj
    ) public view returns (uint256 Ax, uint256 Ay, uint256 revenueAccrued, packedFloat q, packedFloat L, packedFloat wj, packedFloat rj) {
        if (uj == 0 && _uj.eq(ALTBCEquations.FLOAT_0)) revert ZeroValueNotAllowed();
        else if (uj != 0) {
            _uj = (uj.toInt256()).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        }
        (wj, rj) = ILPToken(lpToken).getLPToken(tokenId);

        if (wj.lt(_uj)) revert LPTokenWithdrawalAmountExceedsAllowance();
        L = tbc.calculateL(x);
        packedFloat hn = tbc.calculateH(L, _w, _wInactive(), _collectedLPFees);

        // STEP 1 - Get q and multiplier
        q = _uj.div(_w);

        // STEP 2 - Calc amount out
        {
            packedFloat rawAx = q.mul(tbc.xMax.sub(x));
            Ax = rawAx.convertpackedFloatToWAD().toUint256();
        }
        {
            packedFloat rawAy = q.mul(tbc.calculateDn(x).sub(tbc.calculateL(x)));
            // check for lower bound before casting to int
            Ay = rawAy.lt(ALTBCEquations.FLOAT_WAD)
                ? 0
                : rawAy.convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)).toUint256();
        }

        packedFloat revenuePerLiquidity = hn.sub(rj);

        // STEP 3 - Calculate revenue accrued. This check is important due to the wInactive position rj value.
        revenueAccrued = revenuePerLiquidity.gt(ALTBCEquations.FLOAT_0)
            ? _uj.mul(revenuePerLiquidity).convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)).toUint256()
            : 0;
    }

    /**
     * @dev This is the function to withdraw partial liquidity from the pool.
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param uj The amount of liquidity being withdrawn
     * @param recipient address that receives withdrawn liquidity
     * @param _minAx The minimum acceptable amount of xToken actually withdrawn from liquidity.
     * @param _minAy The minimum acceptable amount of yToken actually withdrawn from liquidity.
     * @param expires Timestamp at which the withdraw transaction will expire.
     */
    function withdrawPartialLiquidity(
        uint256 tokenId,
        uint256 uj,
        address recipient,
        uint256 _minAx,
        uint256 _minAy,
        uint256 expires
    ) external checkExpiration(expires) {
        packedFloat _uj = (uj.toInt256()).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE);
        _withdrawLiquidity(tokenId, _uj, recipient, _minAx, _minAy);
    }

    /**
     * @dev This is the function to withdraw all token liquidity from the pool.
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param recipient address that receives withdrawn liquidity
     * @param _minAx The minimum acceptable amount of xToken actually withdrawn from liquidity.
     * @param _minAy The minimum acceptable amount of yToken actually withdrawn from liquidity.
     * @param expires Timestamp at which the withdraw transaction will expire.
     */
    function withdrawAllLiquidity(
        uint256 tokenId,
        address recipient,
        uint256 _minAx,
        uint256 _minAy,
        uint256 expires
    ) external checkExpiration(expires) {
        (packedFloat wj, ) = ILPToken(lpToken).getLPToken(tokenId);
        _withdrawLiquidity(tokenId, wj, recipient, _minAx, _minAy);
    }

    /**
     * @dev This is the function to withdraw liquidity from the pool.
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param _uj The amount of liquidity being withdrawn
     * @param recipient address that receives withdrawn liquidity
     * @param _minAx The minimum acceptable amount of xToken actually withdrawn from liquidity.
     * @param _minAy The minimum acceptable amount of yToken actually withdrawn from liquidity.
     */
    function _withdrawLiquidity(uint256 tokenId, packedFloat _uj, address recipient, uint256 _minAx, uint256 _minAy) internal {
        // We update the revenue of the lp token before calculating the amount out for efficiency purposes
        if (ILPToken(lpToken).ownerOf(tokenId) != _msgSender()) revert InvalidToken();

        (
            uint256 Ax,
            uint256 Ay,
            uint256 revenueAccrued,
            packedFloat q,
            packedFloat L,
            packedFloat wj,
            packedFloat rj
        ) = simulateWithdrawLiquidity(tokenId, 0, _uj);
        {
            packedFloat newWj = wj.sub(_uj);

            _checkSlippage(Ax, _minAx);
            _checkSlippage(Ay, _minAy);

            // Update pool state
            ILPToken(lpToken).updateLPTokenWithdrawal(tokenId, newWj, rj);
            if (tokenId == activeLpId) {
                (packedFloat __wInactive, ) = ILPToken(lpToken).getLPToken(inactiveLpId);
                checkInactiveLiquidity(newWj, __wInactive);
            }
        }

        packedFloat multiplier = ALTBCEquations.FLOAT_1.sub(q);

        // Update Z with current _w and _wInactive values
        if (tokenId == inactiveLpId) {
            tbc.Zn = tbc.Zn.add((q.mul(L)));
        } else {
            tbc.calculateZ(L, _w, _wInactive(), q, true);
        }

        // if multiplier is 0 the pool will have no liquidity and should be closed
        if (multiplier.eq(ALTBCEquations.FLOAT_0)) {
            _pause();
            _transferOwnership(address(0));
        } else {
            x = tbc._liquidityUpdateHelper(x, multiplier);
        }

        {
            // Update LPToken and W
            _w = _w.sub(_uj);

            // Transfer the liquidity amounts to the lp
            recipient = recipient == address(0) ? _msgSender() : recipient;

            IERC20(xToken).safeTransfer(recipient, Ax);
            IERC20(yToken).safeTransfer(recipient, Ay + revenueAccrued);
            _emitLiquidityWithdrawn(tokenId, Ax, Ay, revenueAccrued, recipient);
            _emitCurveState();
        }
    }

    // This is a helper function to avoid stack too deep errors
    /**
     * @dev This is the function to emit the LiquidityWithdrawn event.
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param Ax The amount of xToken to be received
     * @param Ay The amount of yToken to be received
     * @param revenueAccrued The amount of revenue accrued to the liquidity position
     * @param recipient The address that receives the withdrawn liquidity
     */
    function _emitLiquidityWithdrawn(uint256 tokenId, uint256 Ax, uint256 Ay, uint256 revenueAccrued, address recipient) private {
        emit LiquidityWithdrawn(_msgSender(), tokenId, Ax, Ay, revenueAccrued, recipient);
    }

    /**
     * @dev This is the function to withdraw revenue from the pool.
     * @param tokenId The tokenId owned by the liquidity provider.
     * @param Q The amount of revenue being withdrawn
     * @return revenue The amount of revenue being withdrawn
     */
    function withdrawRevenue(uint256 tokenId, uint256 Q, address recipient) external returns (uint256 revenue) {
        if (Q == 0) revert ZeroValueNotAllowed();
        if (ILPToken(lpToken).ownerOf(tokenId) != _msgSender() || (tokenId == inactiveLpId)) revert InvalidToken();
        packedFloat _Q = (Q.toInt256()).toPackedFloat(int(yDecimalDiff) - int(POOL_NATIVE_DECIMALS));
        (, packedFloat _wj, packedFloat _rj, packedFloat tokenRevenueAvailable, ) = _getRevenueAvailable(tokenId);
        if (_Q.gt(tokenRevenueAvailable)) revert QTooHigh();
        packedFloat updatedRj = _rj.add(_Q.div(_wj));
        ILPToken(lpToken).updateLPToken(tokenId, _wj, updatedRj);
        revenue = _normalizeTokenDecimals(false, Q);
        recipient = recipient == address(0) ? _msgSender() : recipient;
        IERC20(yToken).safeTransfer(recipient, revenue);
        emit RevenueWithdrawn(_msgSender(), tokenId, revenue, recipient);
    }

    /**
     * @dev This is the function to get the revenue available for a liquidity position.
     * @param tokenId The tokenId representing the liquidity position
     * @return _revenueAvailable The amount of revenue available for the liquidity position
     */
    function revenueAvailable(uint256 tokenId) public view returns (uint256 _revenueAvailable) {
        (, , , , _revenueAvailable) = _getRevenueAvailable(tokenId);
    }

    /**
     * @dev This is the function to get the revenue available for a liquidity provider.
     * @param tokenId The tokenId owned by the liquidity provider
     * @return hn The total revenue per liquidity unit for the pool
     * @return _wj The amount of liquidity units of the specified token
     * @return _rj The revenue accrued to the liquidity position
     * @return _revenueAvailable The amount of revenue available for the liquidity provider
     */
    function _getRevenueAvailable(
        uint256 tokenId
    )
        internal
        view
        returns (packedFloat hn, packedFloat _wj, packedFloat _rj, packedFloat _revenueAvailable, uint256 revenueAvailableUint)
    {
        hn = retrieveH();
        (_wj, _rj) = ILPToken(lpToken).getLPToken(tokenId);
        _revenueAvailable = _wj.calculateRevenueAvailable(hn, _rj);
        revenueAvailableUint = _revenueAvailable.lt(ALTBCEquations.FLOAT_WAD)
            ? 0
            : _revenueAvailable.convertpackedFloatToSpecificDecimals(int(POOL_NATIVE_DECIMALS) - int(yDecimalDiff)).toUint256();
    }

    /**
     * @dev This is the function to retrieve the current spot price of the x token.
     * @return sPrice the price in YToken Decimals
     * @notice x + 1 is used for returning the price of the next token sold, not the price of the last token sold
     */
    function _spotPrice() internal view override returns (packedFloat sPrice) {
        // Price P(N+1) = f(x(n+1));
        sPrice = tbc.calculatefx(x.add(int(1).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE)));
    }

    /**
     * @dev This function updates the state of the math values of the pool.
     */
    function _updateParameters() internal override {
        // Calculate Dn using Bn and cn before they get updated
        packedFloat oldBn = tbc.b;
        // Calculate Bn (Sn)
        tbc.calculateBn(x);
        // we update c only if x is not zero
        if (packedFloat.unwrap(x) > 0) tbc.calculateC(x, oldBn);
    }

    /**
     * @dev This function calculates the amount of token X required for the user to purchase a specific amount of Token Y (buy y with x : out perspective).
     * @param _amountOfY desired amount of token Y
     * @return amountOfX required amount of token X
     */
    function _calculateAmountOfXRequiredBuyingY(packedFloat _amountOfY) internal view override returns (packedFloat amountOfX) {
        packedFloat comparisonDn = tbc.calculateDn(tbc.xMin);
        packedFloat Dn = tbc.calculateDn(x);
        // Dn - An >= D(Xmin, bn, cn)
        if (Dn.sub(_amountOfY).lt(comparisonDn)) {
            revert NotEnoughCollateral();
        }

        // Xn+1 = 2Dn / (cn + sqrt(cn^2 + 2bn*Dn+1)) where Dn+1 = Dn - An
        packedFloat _updatedX = tbc.calculateXofNPlus1(Dn.sub(_amountOfY)); // XOutOfBounds is impossible to be triggered in this scenario. arithmetic overflow instead
        amountOfX = x.sub(_updatedX);
    }

    /**
     * @dev This function calculates the amount of token Y required for the user to purchase a specific amount of Token X (buy x with y : out perspective).
     * @param _amountOfX desired amount of token X (also known as An in the spec)
     * @return amountOfY required amount of token Y
     */
    function _calculateAmountOfYRequiredBuyingX(packedFloat _amountOfX) internal view override returns (packedFloat amountOfY) {
        // Xn + An
        packedFloat _updatedX = x.add(_amountOfX);

        // Xn + An <= Xmax
        if (_updatedX.gt(tbc.xMax)) revert XOutOfBounds(_updatedX.sub(tbc.xMax).sub(tbc.xMin).convertpackedFloatToWAD().toUint256());

        // Dn+1 - Dn
        packedFloat Dn = tbc.calculateDn(x);
        packedFloat DnPlusOne = tbc.calculateDn(_updatedX);
        amountOfY = DnPlusOne.sub(Dn);
    }

    /**
     * @dev This function calculates the amount of token Y the user will receive when selling token X (sell x for y : in perspective).
     * @param _amountOfX amount of token X to be sold
     * @return amountOfY amount of token Y to be received
     */
    function _calculateAmountOfYReceivedSellingX(packedFloat _amountOfX) internal view override returns (packedFloat amountOfY) {
        // Xn - An >= Xmin
        if (tbc.xMin.gt(x.sub(_amountOfX))) revert XOutOfBounds(tbc.xMin.add(_amountOfX.sub(x)).convertpackedFloatToWAD().toUint256());
        // Xn+1 = Xn - An
        packedFloat _updatedX = x.sub(_amountOfX);
        // Dn+1 - Dn
        packedFloat Dn = tbc.calculateDn(x);
        packedFloat DnPlusOne = tbc.calculateDn(_updatedX);
        amountOfY = Dn.sub(DnPlusOne);
    }

    /**
     * @dev This function calculates the amount of token X the user will receive when selling token Y (sell y for x : in perspective).
     * @param _amountOfY amount of token Y to be sold
     * @return amountOfX amount of token X to be received
     */
    function _calculateAmountOfXReceivedSellingY(packedFloat _amountOfY) internal view override returns (packedFloat amountOfX) {
        // Dn
        packedFloat Dn = tbc.calculateDn(x);
        packedFloat DMax = tbc.calculateDn(tbc.xMax);
        // Dn + An >= D(Xmax, bn, cn)
        if (Dn.add(_amountOfY).gt(DMax)) {
            revert DnTooLarge();
        }

        // Xn+1 = 2Dn / (cn + sqrt(cn^2 + 2bn*Dn+1)) where Dn+1 = Dn + An
        packedFloat _updatedX = tbc.calculateXofNPlus1(Dn.add(_amountOfY));

        amountOfX = _updatedX.sub(x);
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
     * @dev Check for ration  of inactive to active (token Id 2) liquidity, reverts if ratio is above threshold
     * @param _active active liquidity units
     * @param _inactive inactive liquidity units
     * @notice The threshold is set to 1% of the active liquidity units
     */
    function checkInactiveLiquidity(packedFloat _active, packedFloat _inactive) internal pure {
        if (_inactive.eq(ALTBCEquations.FLOAT_0)) return;
        if (_active.le(ALTBCEquations.FLOAT_0)) revert InactiveLiquidityExceedsLimit();
        if (_active.div(_inactive.add(_active)).lt(ACTIVE_LIQUIDITY_MINIMUM)) revert InactiveLiquidityExceedsLimit();
    }

    function retrieveH() public view returns (packedFloat h) {
        h = tbc.calculateH(tbc.calculateL(x), _w, _wInactive(), _collectedLPFees);
    }

    function _emitCurveState() internal override {
        emit ALTBCCurveState(tbc, x);
    }
}
