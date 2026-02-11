// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import {Ownable2Step, Ownable} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {Pausable} from "../../../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {IERC20Metadata} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "./IPool.sol";
import "../../common/IErrors.sol";
import {CalculatorBase, packedFloat} from "./CalculatorBase.sol";
import {CumulativePrice} from "./CumulativePrice.sol";
import {FeeInfo, TBCType} from "../../common/TBC.sol";
import {MathLibs, Float} from "../mathLibs/MathLibs.sol";
import {LPToken} from "../../../src/common/LPToken.sol";
import {Descriptor} from "../../common/NFTSVG.sol";

/**
 * @title Pool Base
 * @dev This contract implements the core of the Pool interface and is meant to be an abstract base for all the pools.
 * Any pool implementation must inherits this contract and implement all the functions from CalculatorBase.
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract PoolBase is IPool, CalculatorBase, Ownable2Step, Pausable, CumulativePrice, LPToken {
    using SafeERC20 for IERC20;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    address public immutable xToken;
    address public immutable yToken;
    int256 constant POOL_NATIVE_DECIMALS_NEGATIVE = 0 - int(POOL_NATIVE_DECIMALS);

    /**
     * @dev difference in decimal precision between y token and x token
     */

    uint256 public immutable yDecimalDiff;

    /**
     * @dev the lower bound of x
     */
    // slither-disable-next-line constable-states // updated in child contract
    packedFloat public xMin;

    /**
     * @dev balance of x token that has been swapped out of the Pool
     */
    packedFloat public x;

    /**
     * @dev lifetime revenue accrued by the pool
     */
    // slither-disable-next-line constable-states // updated in child contract
    packedFloat public h;

    /**
     * @dev lifetime revenue claimed from the pool
     */
    // slither-disable-next-line constable-states // updated in child contract
    uint256 public r;

    /**
     * @dev fee percentage for swaps for the LP
     */
    uint16 public lpFee;

    /**
     * @dev fee percentage for swaps for the protocol
     */
    uint16 public protocolFee;

    /**
     * @dev protocol-fee collector address
     */
    address public protocolFeeCollector;

    /**
     * @dev proposed protocol-fee collector address
     */
    address public proposedProtocolFeeCollector;

    /**
     * @dev currently claimable fee balance
     */
    packedFloat _collectedLPFees;

    /**
     * @dev currently claimable protocol fee balance
     */
    uint256 public collectedProtocolFees;

    /**
     * @dev inactive liquidity share
     */
    packedFloat _wInactive;

    /**
     * @dev total liquidity share
     */
    packedFloat _w;

    modifier onlyProtocolFeeCollector() {
        if (_msgSender() != protocolFeeCollector) revert NotProtocolFeeCollector();
        _;
    }

    modifier onlyProposedProtocolFeeCollector() {
        if (_msgSender() != proposedProtocolFeeCollector) revert NotProposedProtocolFeeCollector();
        _;
    }

    /**
     * @dev constructor
     * @param _xToken address of the X token (x axis)
     * @param _yToken address of the Y token (y axis)
     * @param fees fee information
     */
    constructor(
        address _xToken,
        address _yToken,
        FeeInfo memory fees,
        string memory _name,
        string memory _symbol
    ) Ownable(_msgSender()) LPToken(_name, _symbol) {
        _validateInput(_xToken, _yToken, fees._protocolFeeCollector);
        // slither-disable-start missing-zero-check // This is done in the _validateInput function
        xToken = _xToken;
        yToken = _yToken;
        protocolFeeCollector = _msgSender(); // temporary measure to avoid role failure
        setLPFee(fees._lpFee);
        setProtocolFee(fees._protocolFee);
        protocolFeeCollector = fees._protocolFeeCollector;
        // slither-disable-end missing-zero-check
        yDecimalDiff = POOL_NATIVE_DECIMALS - IERC20Metadata(_yToken).decimals();

        /// implementation contract must transfer ownership and emit a PoolDeployed event
    }

    /**
     * @dev This is the main function of the pool to swap.
     * @param _tokenIn the address of the token being given to the pool in exchange for another token
     * @param _amountIn the amount of the ERC20 _tokenIn to exchange into the Pool
     * @param _minOut the amount of the other token in the pair minimum to be received for the
     * _amountIn of _tokenIn.
     * @return amountOut the actual amount of the token coming out of the Pool as result of the swap
     * @return lpFeeAmount the amount of the Y token that's being dedicated to fees for the LP
     * @return protocolFeeAmount the amount of the Y token that's being dedicated to fees for the protocol
     */
    function swap(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _minOut
    ) external whenNotPaused returns (uint256 amountOut, uint256 lpFeeAmount, uint256 protocolFeeAmount) {
        _updateCumulativePrice(spotPrice(), block.timestamp);
        emit CumulativePriceUpdated(lastBlockTimestamp, cumulativePrice);

        bool sellingX = _tokenIn == xToken;
        //slither-disable-start reentrancy-benign // the recipient of the transfer is this contract
        uint256 beforeBalance = IERC20(sellingX ? xToken : yToken).balanceOf(address(this));
        IERC20(sellingX ? xToken : yToken).safeTransferFrom(_msgSender(), address(this), _amountIn);
        uint256 afterBalance = IERC20(sellingX ? xToken : yToken).balanceOf(address(this));
        _amountIn = afterBalance - beforeBalance;

        if (_minOut == 0) revert ZeroValueNotAllowed();
        (amountOut, lpFeeAmount, protocolFeeAmount) = simSwap(_tokenIn, _amountIn);
        _checkSlippage(amountOut, _minOut);
        packedFloat xOld = x;

        x = sellingX ? x.sub(int(_amountIn).toPackedFloat(-18)) : x.add(int(amountOut).toPackedFloat(-18));
        // slither-disable-end reentrancy-benign
        // slither-disable-start reentrancy-events // the recipient of the initial transfer is this contract
        _updateParameters(xOld);

        _collectedLPFees = _collectedLPFees.add(int(lpFeeAmount).toPackedFloat(int(yDecimalDiff) - int(POOL_NATIVE_DECIMALS)).div(_w));
        emit LPFeeGenerated(lpFeeAmount);
        collectedProtocolFees += protocolFeeAmount;
        emit ProtocolFeeGenerated(protocolFeeAmount);

        emit Swap(_tokenIn, _amountIn, amountOut, _minOut);
        // slither-disable-end reentrancy-events
        IERC20(sellingX ? yToken : xToken).safeTransfer(_msgSender(), amountOut);
    }

    /**
     * @dev This is a simulation of the swap function. Useful to get marginal prices
     * @param _tokenIn the address of the token being sold
     * @param _amountIn the amount of the ERC20 _tokenIn to sell to the Pool
     * @return amountOut the amount of the token coming out of the Pool as result of the swap (main returned value)
     * @return lpFeeAmount the amount of the Y token that's being dedicated to fees for the LP
     * @return protocolFeeAmount the amount of the Y token that's being dedicated to fees for the protocol
     */
    function simSwap(
        address _tokenIn,
        uint256 _amountIn
    ) public view returns (uint256 amountOut, uint256 lpFeeAmount, uint256 protocolFeeAmount) {
        bool sellingX = _tokenIn == xToken;
        if (!sellingX && _tokenIn != yToken) revert InvalidToken();

        uint minAmountIn = 1;
        if (lpFee > 0 && !sellingX) ++minAmountIn;
        if (protocolFee > 0 && !sellingX) ++minAmountIn;
        if (_amountIn < minAmountIn) revert ZeroValueNotAllowed();

        if (!sellingX) {
            lpFeeAmount = _determineFeeAmountSell(_amountIn, lpFee);
            protocolFeeAmount = _determineFeeAmountSell(_amountIn, protocolFee);
            _amountIn -= (lpFeeAmount + protocolFeeAmount); // fees are always coming out from the pool
            _amountIn = _normalizeTokenDecimals(true, _amountIn);
        }
        packedFloat rawAmountOut = sellingX
            ? _calculateAmountOfYReceivedSellingX(int(_amountIn).toPackedFloat(-18))
            : _calculateAmountOfXReceivedSellingY(int(_amountIn).toPackedFloat(-18));
        amountOut = uint(rawAmountOut.convertpackedFloatToWAD());
        if (sellingX) {
            amountOut = _normalizeTokenDecimals(false, amountOut);
            // slither-disable-start incorrect-equality
            if (amountOut == 0) return (0, 0, 0);
            // slither-disable-end incorrect-equality
            lpFeeAmount = _determineFeeAmountSell(amountOut, lpFee);
            protocolFeeAmount = _determineFeeAmountSell(amountOut, protocolFee);
            amountOut -= (lpFeeAmount + protocolFeeAmount);
        }
    }

    /**
     * @dev This is a simulation of the swap function from the perspective of purchasing a specific amount. Useful to get marginal price.
     * @param _tokenout the address of the token being bought
     * @param _amountOut the amount of the ERC20 _tokenOut to buy from the Pool
     * @return amountIn the amount necessary of the token coming into the Pool for the desired amountOut of the swap (main returned value)
     * @return lpFeeAmount the amount of the Y token that's being dedicated to fees for the LP
     * @return protocolFeeAmount the amount of the Y token that's being dedicated to fees for the protocol
     * @notice lpFeeAmount and protocolFeeAmount are already factored in the amountIn. This is useful only to know how much of the amountIn
     * will go towards fees.
     */
    function simSwapReversed(
        address _tokenout,
        uint256 _amountOut
    ) public view returns (uint256 amountIn, uint256 lpFeeAmount, uint256 protocolFeeAmount) {
        bool buyingX = _tokenout == xToken;
        if (!buyingX && _tokenout != yToken) revert InvalidToken();

        if (buyingX) {
            packedFloat amountInRaw = _calculateAmountOfYRequiredBuyingX(int(_amountOut).toPackedFloat(-18));
            uint256 uamountInRaw = uint(amountInRaw.convertpackedFloatToWAD());
            uamountInRaw = _normalizeTokenDecimals(false, uamountInRaw); // reversed logic because swap is reversed
            (protocolFeeAmount, lpFeeAmount) = _determineProtocolAndLPFeesBuy(uamountInRaw);
            amountIn = uamountInRaw + lpFeeAmount + protocolFeeAmount;
        } else {
            (protocolFeeAmount, lpFeeAmount) = _determineProtocolAndLPFeesBuy(_amountOut);
            _amountOut = _normalizeTokenDecimals(true, _amountOut + protocolFeeAmount + lpFeeAmount); // reversed logic because swap is reversed
            packedFloat amountInRaw = _calculateAmountOfXRequiredBuyingY(int(_amountOut).toPackedFloat(-18));
            amountIn = uint(amountInRaw.convertpackedFloatToWAD());
        }
    }

    /**
     * @dev This is the function to activate/deactivate trading.
     * @param _enable pass True to enable or False to disable
     */
    function enableSwaps(bool _enable) external virtual onlyOwner {
        if (_enable) _unpause();
        else _pause();
    }

    /**
     * @dev This is the function to update the LP fees per trading.
     * @param _fee percentage of the transaction that will get collected as fees (in percentage basis points:
     * 1500 -> 15.00%; 500 -> 5.00%; 1 -> 0.01%)
     */
    function setLPFee(uint16 _fee) public onlyOwner {
        if (_fee > MAX_LP_FEE) revert LPFeeAboveMax(_fee, MAX_LP_FEE);
        lpFee = _fee;
        emit LPFeeSet(_fee);
    }

    /**
     * @dev This is the function to update the protocol fees per trading.
     * @param _protocolFee percentage of the transaction that will get collected as fees (in percentage basis points:
     * 10000 -> 100.00%; 500 -> 5.00%; 1 -> 0.01%)
     */
    function setProtocolFee(uint16 _protocolFee) public onlyProtocolFeeCollector {
        if (_protocolFee > MAX_PROTOCOL_FEE) revert ProtocolFeeAboveMax({proposedFee: _protocolFee, maxFee: MAX_PROTOCOL_FEE});
        protocolFee = _protocolFee;
        emit ProtocolFeeSet(_protocolFee);
    }

    /**
     * @dev This is the function to add XToken liquidity to the pool.
     * @param _amount the amount of X token to transfer from the sender to the pool
     */
    function addXSupply(uint256 _amount) external virtual onlyOwner {
        emit LiquidityXTokenAdded(xToken, _amount);
        // slither-disable-start reentrancy-benign // the transfer doesn't update any state variable directly and the pool is the recipient
        uint256 beforeBalance = IERC20(xToken).balanceOf(address(this));
        IERC20(xToken).safeTransferFrom(_msgSender(), address(this), _amount);
        uint256 afterBalance = IERC20(xToken).balanceOf(address(this));
        // slither-disable-end reentrancy-benign
        _amount = afterBalance - beforeBalance;
        _validateLiquidityAdd(int(afterBalance).toPackedFloat(-18));
        _mintTokenAndUpdate(_msgSender(), (int(_amount).toPackedFloat(POOL_NATIVE_DECIMALS_NEGATIVE)), packedFloat.wrap(0), false, _amount, 0);
    }

    /**
     * @dev This function collects the protocol fees from the Pool.
     */
    function collectProtocolFees() external onlyProtocolFeeCollector {
        uint256 collectedAmount = collectedProtocolFees;
        delete collectedProtocolFees;
        emit ProtocolFeesCollected(_msgSender(), collectedAmount);
        IERC20(yToken).safeTransfer(_msgSender(), collectedAmount);
    }

    /**
     * @dev function to propose a new protocol fee collector
     * @param _protocolFeeCollector the new fee collector
     * @notice that only the current fee collector address can call this function
     */
    function proposeProtocolFeeCollector(address _protocolFeeCollector) external onlyProtocolFeeCollector {
        // slither-disable-start missing-zero-check // unnecessary
        proposedProtocolFeeCollector = _protocolFeeCollector;
        // slither-disable-end missing-zero-check
        emit ProtocolFeeCollectorProposed(_protocolFeeCollector);
    }

    /**
     * @dev function to confirm a new protocol fee collector
     * @notice that only the already proposed fee collector can call this function
     */
    function confirmProtocolFeeCollector() external onlyProposedProtocolFeeCollector {
        delete proposedProtocolFeeCollector;
        protocolFeeCollector = _msgSender();
        emit ProtocolFeeCollectorConfirmed(_msgSender());
    }

    /**
     * @dev This function gets the liquidity in the pool for xToken in WAD.
     * @return the liquidity in the pool for xToken in WAD
     */
    function xTokenLiquidity() external view returns (uint256) {
        return IERC20(xToken).balanceOf(address(this));
    }

    /**
     * @dev This function gets the liquidity in the pool for yToken in WAD
     * @return the liquidity in the pool for yToken in WAD
     */
    function yTokenLiquidity() external view returns (uint256) {
        uint revenue = _totalRevenue();
        revenue = _normalizeTokenDecimals(false, revenue);
        return (IERC20(yToken).balanceOf(address(this)) + r) - (collectedProtocolFees + revenue);
    }

    /**
     * @dev This function returns the total revenue in the pool for yToken in WAD
     * @return the revenue in the pool for yToken in WAD
     */
    function totalRevenue() public view returns (uint256) {
        return _totalRevenue();
    }

    /**
     * @dev This is the function to retrieve the current spot price of the x token.
     * @return sPrice the price in YToken Decimals
     */
    function spotPrice() public view returns (uint256 sPrice) {
        packedFloat sPriceRaw = _spotPrice();
        sPrice = uint(sPriceRaw.convertpackedFloatToWAD());

        if (yDecimalDiff != 0) {
            sPrice = _normalizeTokenDecimals(false, sPrice);
        }
    }

    /**
     * @dev tells current LP fees accumulated in the pool
     * @return currently claimable LP fee balance
     */
    function collectedLPFees() external view returns (uint256) {
        return _normalizeTokenDecimals(false, uint((_collectedLPFees.mul(_w)).convertpackedFloatToWAD()));
    }

    /**
     * @dev tells current LP fees accumulated in the pool
     * @return currently claimable LP fee balance
     */
    function collectedLPFeesPerLiquidityUnit() external view returns (uint256) {
        return _normalizeTokenDecimals(false, uint(_collectedLPFees.convertpackedFloatToWAD()));
    }

    /**
     * @dev A helper function to validate most of constructor's inputs.
     * @param _xToken address of the X token (x axis)
     * @param _yToken address of the Y token (y axis)
     */
    function _validateInput(address _xToken, address _yToken, address _protocolFeeCollector) internal view {
        if (_xToken == address(0) || _yToken == address(0) || _protocolFeeCollector == address(0)) revert ZeroAddress();
        if (_xToken == _yToken) revert XandYTokensAreTheSame();
        if (IERC20Metadata(_xToken).decimals() != 18) revert XTokenDecimalsIsNot18();
        if (IERC20Metadata(_yToken).decimals() > 18) revert YTokenDecimalsGT18();
    }

    /**
     * @dev This function normalizes an input amount to or from native decimal value.
     * @param isInput if true, it assumes that the tokens are being received into the pool and therefore it
     * multiplies/adds the zeros necessary to make it a native-decimal value. It divides otherwise.
     * @param rawAmount amount to normalize
     * @return normalizedAmount the normalized value
     */
    function _normalizeTokenDecimals(bool isInput, uint rawAmount) internal view returns (uint normalizedAmount) {
        if (yDecimalDiff == 0) normalizedAmount = rawAmount;
        else normalizedAmount = isInput ? rawAmount * (10 ** yDecimalDiff) : rawAmount / (10 ** yDecimalDiff);
    }

    /**
     * @dev This function determines the amount of fees when doing a simSwap (Sell simulation).
     * @param amountOfY the amount to calculate the fees from
     * @return feeAmount the amount of fees
     *
     */
    function _determineFeeAmountSell(uint256 amountOfY, uint16 _fee) private pure returns (uint256 feeAmount) {
        if (_fee > 0) feeAmount = (amountOfY * _fee) / PERCENTAGE_DENOM + 1;
    }

    /**
     * @dev This function determines the adjusted amount of y tokens needed accounting for fees when doing a simSwapReverse (buy simulation).
     * Equation:
     *
     * yAmount - yAmount * fee = realYAmount, in other words: yAmount * (1 - fee) = realYAmount
     * Thefore,
     * adjustedYAmount = yAmount / (1 - fee),
     * and
     * yAmount * fee = adjustedYAmount - yAmount,
     * which gives us
     * yAmount * fee =  yAmount / (1 - fee) - yAmount = (yAmount * fee) / (1 - fee)
     *
     * @param originalAmountOfY the amount to adjust with fees
     * @return yFees the amount necessary to add to yAmount to get the expected yAmount after fees
     */
    function _determineFeeAmountBuy(uint256 originalAmountOfY, uint16 _fee) private pure returns (uint256 yFees) {
        yFees = (originalAmountOfY * _fee) / (PERCENTAGE_DENOM - _fee) + 1; // we add 1 to round up
    }

    /**
     * @dev this functions returns the value of both protocol and LP fees that need to be added to the original amount of yTokens in order
     * for it to have the desired effect in simSwapReversed (buy simulation).
     * @param originalAmountOfY the net amount of yTokens expressed in its native decimals that are desired to be used in a buy operation.
     * @return amountProtocolFee the amount of yTokens that will be destined towards protocol fees expressed in WADs of yTokens.
     * This value should be added to originalAmountOfY for it to have the desired effect.
     * @return amountLPFee the amount of yTokens that will be destined towards LP fees expressed in WADs of yTokens. This
     * value should be added to originalAmountOfY for it to have the desired effect.
     */
    function _determineProtocolAndLPFeesBuy(
        uint256 originalAmountOfY
    ) internal view returns (uint256 amountProtocolFee, uint256 amountLPFee) {
        if (lpFee + protocolFee == 0) return (0, 0);
        else {
            uint totalAmountFees = _determineFeeAmountBuy(originalAmountOfY, lpFee + protocolFee);
            if (lpFee == 0) (amountProtocolFee, amountLPFee) = (totalAmountFees, 0);
            else if (protocolFee == 0) (amountProtocolFee, amountLPFee) = (0, totalAmountFees);
            else {
                ++totalAmountFees; // we add 1 to the total amount of fees to account for rounding down edge cases where 1 of the 2 results could be 0
                if (lpFee > protocolFee) {
                    amountLPFee = (totalAmountFees * lpFee) / (protocolFee + lpFee);
                    amountProtocolFee = totalAmountFees - amountLPFee;
                } else {
                    amountProtocolFee = (totalAmountFees * protocolFee) / (protocolFee + lpFee);
                    amountLPFee = totalAmountFees - amountProtocolFee;
                }
            }
        }
    }

    /**
     * @dev This function checks to verify the amount out will be greater than or equal to the minimum expected amount out.
     * @param _amountOut the actual amount being provided out by the swap
     * @param _minOut the expected amount out to compare against
     */
    function _checkSlippage(uint256 _amountOut, uint256 _minOut) internal pure {
        if (_amountOut < (_minOut - 1)) revert("max slippage reached");
    }

    /**
     * @dev returns the current total liquidity in the Pool
     * @return w
     */
    function w() external view returns (uint256) {
        return uint(_w.convertpackedFloatToWAD());
    }

    function wInactive() external view returns (uint256) {
        return uint(_wInactive.convertpackedFloatToWAD());
    }

    /**
     * @dev Overrides the tokenURI function from ERC721 to generate an NFT with pool information
     * @param tokenId The token ID to generate the URI for
     * @return The token URI with SVG image and metadata
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert URIQueryForNonexistentToken();

        string memory xTokenSymbol = IERC20Metadata(xToken).symbol();
        string memory yTokenSymbol = IERC20Metadata(yToken).symbol();

        Descriptor.ConstructTokenURIParams memory params = Descriptor.ConstructTokenURIParams({
            tokenId: tokenId,
            xTokenAddress: xToken,
            yTokenAddress: yToken,
            xTokenSymbol: xTokenSymbol,
            yTokenSymbol: yTokenSymbol,
            fee: lpFee,
            poolManager: address(this)
        });

        return Descriptor.constructTokenURI(params);
    }

    /**
     * @dev This function gets the total revenue in the pool for yToken in WAD
     * @return revenue The revenue in the pool for yToken in WAD
     */
    function _totalRevenue() internal view returns (uint256 revenue) {
        revenue = uint((h.mul(_w)).convertpackedFloatToWAD());
    }
}
