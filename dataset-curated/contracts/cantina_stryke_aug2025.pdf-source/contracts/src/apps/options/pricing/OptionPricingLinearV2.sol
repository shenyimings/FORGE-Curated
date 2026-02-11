// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Libraries
import {SafeMath} from "../../../libraries/math/SafeMath.sol";
import {BlackScholes} from "./external/BlackScholes.sol";

// Contracts
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract OptionPricingLinearV2 is Ownable {
    using SafeMath for uint256;

    // The offset for volatility calculation in 1e4 precision
    mapping(address => uint256) public volatilityOffset;

    // The multiplier for volatility calculation in 1e4 precision
    mapping(address => uint256) public volatilityMultiplier;

    // The % of the price of asset which is the minimum option price possible in 1e8 precision
    mapping(address => uint256) public minOptionPricePercentage;

    // The decimal precision for volatility calculation
    uint256 public constant VOLATILITY_PRECISION = 1e4;

    // Time to expiry => volatility
    mapping(address => mapping(uint256 => uint256)) public ttlToVol;

    // IV Setter addresses
    mapping(address => bool) public ivSetter;

    error NotIVSetter();
    error Vol_Not_Set();
    error ArrayLengthMismatch();

    constructor() Ownable(msg.sender) {
        ivSetter[msg.sender] = true;
    }

    /*---- GOVERNANCE FUNCTIONS ----*/

    /// @notice Updates the IV setter
    /// @param _setter Address of the setter
    /// @param _status Status  to set
    /// @dev Only the owner of the contract can call this function
    function updateIVSetter(address _setter, bool _status) external onlyOwner {
        ivSetter[_setter] = _status;
    }

    /// @notice Updates the implied volatility (IV) for the given time to expirations (TTLs).\
    /// @param _optionsMarket The address of the options market
    /// @param _ttls The TTLs to update the IV for.
    /// @param _ttlIV The new IVs for the given TTLs.
    /// @dev Only the IV SETTER can call this function.
    function updateIVs(address _optionsMarket, uint256[] calldata _ttls, uint256[] calldata _ttlIV) external {
        if (!ivSetter[msg.sender]) revert NotIVSetter();
        if (_ttls.length != _ttlIV.length) revert ArrayLengthMismatch();

        for (uint256 i; i < _ttls.length; i++) {
            ttlToVol[_optionsMarket][_ttls[i]] = _ttlIV[i];
        }
    }

    /// @notice updates the offset for volatility calculation
    /// @param _optionsMarket The address of the options market
    /// @param _volatilityOffset the new offset
    /// @return whether offset was updated
    function updateVolatilityOffset(address _optionsMarket, uint256 _volatilityOffset)
        external
        onlyOwner
        returns (bool)
    {
        volatilityOffset[_optionsMarket] = _volatilityOffset;

        return true;
    }

    /// @notice updates the multiplier for volatility calculation
    /// @param _optionsMarket The address of the options market
    /// @param _volatilityMultiplier the new multiplier
    /// @return whether multiplier was updated
    function updateVolatilityMultiplier(address _optionsMarket, uint256 _volatilityMultiplier)
        external
        onlyOwner
        returns (bool)
    {
        volatilityMultiplier[_optionsMarket] = _volatilityMultiplier;

        return true;
    }

    /// @notice updates % of the price of asset which is  the minimum option price possible
    /// @param _optionsMarket The address of the options market
    /// @param _minOptionPricePercentage the new %
    /// @return whether % was updated
    function updateMinOptionPricePercentage(address _optionsMarket, uint256 _minOptionPricePercentage)
        external
        onlyOwner
        returns (bool)
    {
        minOptionPricePercentage[_optionsMarket] = _minOptionPricePercentage;

        return true;
    }

    /*---- VIEWS ----*/

    struct OptionPriceParams {
        address optionsMarket;
        address hook;
        bool isPut;
        uint256 expiry;
        uint256 ttl;
        uint256 strike;
        uint256 lastPrice;
    }

    /// @notice computes the option price (with liquidity multiplier)
    /// @param _hook The address of the hook
    /// @param _isPut is put option
    /// @param _expiry expiry timestamp
    /// @param _ttl time to live for the option
    /// @param _strike strike price
    /// @param _lastPrice current price
    function getOptionPrice(
        address _hook,
        bool _isPut,
        uint256 _expiry,
        uint256 _ttl,
        uint256 _strike,
        uint256 _lastPrice
    ) external view returns (uint256) {
        return _getOptionPrice(
            OptionPriceParams({
                optionsMarket: msg.sender,
                hook: _hook,
                isPut: _isPut,
                expiry: _expiry,
                ttl: _ttl,
                strike: _strike,
                lastPrice: _lastPrice
            })
        );
    }

    /// @notice computes the option price (with liquidity multiplier)
    /// @param _optionsMarket the address of the options market
    /// @param _hook The address of the hook
    /// @param _isPut is put option
    /// @param _expiry expiry timestamp
    /// @param _ttl time to live for the option
    /// @param _strike strike price
    /// @param _lastPrice current price
    function getOptionPriceViaAdddress(
        address _optionsMarket,
        address _hook,
        bool _isPut,
        uint256 _expiry,
        uint256 _ttl,
        uint256 _strike,
        uint256 _lastPrice
    ) external view returns (uint256) {
        return _getOptionPrice(
            OptionPriceParams({
                optionsMarket: _optionsMarket,
                hook: _hook,
                isPut: _isPut,
                expiry: _expiry,
                ttl: _ttl,
                strike: _strike,
                lastPrice: _lastPrice
            })
        );
    }

    function _getOptionPrice(OptionPriceParams memory _params) internal view returns (uint256) {
        uint256 timeToExpiry = _params.expiry.sub(block.timestamp).div(864);

        uint256 volatility = ttlToVol[_params.optionsMarket][_params.ttl];

        if (volatility == 0) revert Vol_Not_Set();

        volatility = getVolatility(_params.optionsMarket, _params.strike, _params.lastPrice, volatility);

        uint256 optionPrice = BlackScholes.calculate(
            _params.isPut ? 1 : 0, _params.lastPrice, _params.strike, timeToExpiry, 0, volatility
        ) // 0 - Put, 1 - Call
                // Number of days to expiry mul by 100
            .div(BlackScholes.DIVISOR);

        uint256 minOptionPrice = _params.lastPrice.mul(minOptionPricePercentage[_params.optionsMarket]).div(1e10);

        if (minOptionPrice > optionPrice) {
            return minOptionPrice;
        }

        return optionPrice;
    }
    /// @notice computes the option price (with liquidity multiplier)
    /// @param hook the address of the hook
    /// @param isPut is put option
    /// @param ttl time to live for the option
    /// @param strike strike price
    /// @param lastPrice current price

    function getOptionPriceViaTTL(address hook, bool isPut, uint256 ttl, uint256 strike, uint256 lastPrice)
        external
        view
        returns (uint256)
    {
        return _getOptionPriceViaTTL(
            OptionPriceParams({
                optionsMarket: msg.sender,
                hook: hook,
                isPut: isPut,
                expiry: 0,
                ttl: ttl,
                strike: strike,
                lastPrice: lastPrice
            })
        );
    }

    /// @notice computes the option price (with liquidity multiplier)
    /// @param optionsMarket the address of the options market
    /// @param hook the address of the hook
    /// @param isPut is put option
    /// @param ttl time to live for the option
    /// @param strike strike price
    /// @param lastPrice current price
    function getOptionPriceViaTTLViaAddress(
        address optionsMarket,
        address hook,
        bool isPut,
        uint256 ttl,
        uint256 strike,
        uint256 lastPrice
    ) external view returns (uint256) {
        return _getOptionPriceViaTTL(
            OptionPriceParams({
                optionsMarket: optionsMarket,
                hook: hook,
                isPut: isPut,
                expiry: 0,
                ttl: ttl,
                strike: strike,
                lastPrice: lastPrice
            })
        );
    }

    function _getOptionPriceViaTTL(OptionPriceParams memory _params) internal view returns (uint256) {
        uint256 timeToExpiry = _params.ttl.div(864);

        uint256 volatility = ttlToVol[_params.optionsMarket][_params.ttl];

        if (volatility == 0) revert();

        volatility = getVolatility(_params.optionsMarket, _params.strike, _params.lastPrice, volatility);

        uint256 optionPrice = BlackScholes.calculate(
            _params.isPut ? 1 : 0, _params.lastPrice, _params.strike, timeToExpiry, 0, volatility
        ) // 0 - Put, 1 - Call
                // Number of days to expiry mul by 100
            .div(BlackScholes.DIVISOR);

        uint256 minOptionPrice = _params.lastPrice.mul(minOptionPricePercentage[_params.optionsMarket]).div(1e10);

        if (minOptionPrice > optionPrice) {
            return minOptionPrice;
        }

        return optionPrice;
    }

    /// @notice computes the volatility for a strike
    /// @param _optionsMarket the address of the options market
    /// @param strike strike price
    /// @param lastPrice current price
    /// @param volatility volatility
    function getVolatility(address _optionsMarket, uint256 strike, uint256 lastPrice, uint256 volatility)
        public
        view
        returns (uint256)
    {
        uint256 percentageDifference = strike.mul(1e2).mul(VOLATILITY_PRECISION).div(lastPrice); // 1e4 in percentage precision (1e6 is 100%)

        if (strike > lastPrice) {
            percentageDifference = percentageDifference.sub(1e6);
        } else {
            percentageDifference = uint256(1e6).sub(percentageDifference);
        }

        uint256 scaleFactor = volatilityOffset[_optionsMarket]
            + (percentageDifference.mul(volatilityMultiplier[_optionsMarket]).div(VOLATILITY_PRECISION));

        return (volatility.mul(scaleFactor).div(VOLATILITY_PRECISION));
    }
}
