// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/IPriceOracle.sol";
import "./Pricing.sol";
import "./Refundable.sol";

/**
 * @title Pyth implementation of IPriceOracle, acting as an adapter to allow LetterOfCredit and other contracts that use
 * IPriceOracle to integrate with Pyth.
 *
 * @custom:security-contact security@af.xyz
 */
contract PythPriceOracle is Ownable2Step, IPriceOracle, ERC165, Refundable {
    /***************
     * ERROR TYPES *
     ***************/

    error RelatedArraysLengthMismatch(uint256 _firstLength, uint256 _secondLength);
    error InvalidOraclePrice(address _tokenAddress, int64 _price, uint64 _conf);
    error InsufficientFee(uint256 _got, uint256 _need);
    error UnsupportedTokenAddress(address _tokenAddress);

    /******************
     * CONTRACT STATE *
     ******************/

    IPyth public immutable pythContract;
    /// The token address => `TokenInfo` map containing Pyth Price Feed ID and other information for the token.
    mapping(address => TokenInfo) public addressToTokenInfo;

    /**********
     * EVENTS *
     **********/

    event PriceFeedUpdated(address _tokenAddress, bytes32 _oldPriceFeedId, bytes32 _newPriceFeedId);

    /***********
     * STRUCTS *
     ***********/

    struct TokenInfo {
        bytes32 priceFeedId;
        uint8 decimals;
    }

    /*************
     * FUNCTIONS *
     *************/

    constructor(
        IPyth _pythContractAddress,
        address[] memory _tokenAddresses,
        bytes32[] memory _priceFeedIds
    ) Ownable(msg.sender) {
        pythContract = _pythContractAddress;

        _upsertPriceFeedIdsAsOwner(_tokenAddresses, _priceFeedIds);
    }

    /****************
     * IPriceOracle *
     ****************/

    /**
     * @notice Gets the existing price to trade the provided input token for the provided output token. Note: this
     * function takes the ERC-20 decimals of the tokens into account such that the price is the amount of the output
     * token that one would receive in exchange for 1 unit of the input token.
     * For example, if 1 WBTC = 16.32 WETH, 1e8 = 16.32e18, 1 = 16.32e18/1e8 = 163200000000
     * so 1 "satoshi" of WBTC is worth 163200000000 "wei" of WETH.
     *
     * @dev The price is pieced together from the <inputToken>/USD and <outputToken>/USD prices fetched from Pyth. For
     * more information, see Pyth Price Feeds here: https://pyth.network/developers/price-feed-ids.
     *
     *  Example:
     *      input (WETH): price: 158946315000; exponent: -8, decimals: 18
     *      output (USDC): price: 100000000; exponent: -8, decimals: 6
     *      WETH -> USDC should be 1589.46315000, scaled to account for decimals
     *
     * Generic calculation:
     * outputPerUnitInputPrice = inputPrice * 10**inputExponent * 10**outputDecimals / (outputPrice * 10**outputExponent * 10**inputDecimals)
     * Note: we'll account for precision below.
     *
     * WETH -> USDC example:
     *      outputPerUnitInputPrice = inputPrice * 10**inputExponent * 10**outputDecimals / (outputPrice * 10**outputExponent * 10**inputDecimals)
     *                              = 158946315000 * 10**-8 * 10**6 / (100000000 * 10**-8 * 10**18)
     *                              = 158946315000 * 10**6 / (100000000 * 10**18)
     *                              = 158946315000 / (100000000 * 10**12)
     *                              = 0.00000000158946315
     * Sanity Check:
     *                        1 wei = 0.00000000158946315 USDC
     *                        1 wei = 0.00000000000000158946315 USD (USDC / 10**6 = USD)
     *                        1 ETH = 0.00000000000000158946315 USD * 10**18
     *                        1 ETH = 1589.46315 USD
     *
     * Accounting for precision in integer math:
     *      How do we guarantee a minimum of X digits of precision in our price?
     *          outputPerUnitInputPrice = inputPrice * 10**inputExponent * 10**outputDecimals / (outputPrice * 10**outputExponent * 10**inputDecimals)
     *          Represented as separate price and exponent:
     *              price = inputPrice / outputPrice;
     *              exponent = inputExponent + outputDecimals - outputExponent - inputDecimals
     *
     *          pricePrecisionDecimals = log10(inputPrice) - log10(outputPrice)
     *          precisionBufferExponent = (pricePrecisionDecimals < X) ? (X - pricePrecisionDecimals) : 0
     *          price = 10**precisionBufferExponent * inputPrice / outputPrice
     *          exponent = inputExponent + outputDecimals - outputExponent - inputDecimals - precisionBufferExponent
     *
     * @dev It is assumed that the caller of this contract validates the timestamp of the returned `_price` for its uses.
     *
     * @inheritdoc IPriceOracle
     */
    function getPrice(
        address _inputTokenAddress,
        address _outputTokenAddress
    ) external view returns (Pricing.OraclePrice memory _price) {
        TokenInfo memory inputTokenInfo = _fetchAndValidateTokenInfo(_inputTokenAddress);
        TokenInfo memory outputTokenInfo = _fetchAndValidateTokenInfo(_outputTokenAddress);

        // NB: getPriceUnsafe because callers of this function do their own recency checks.
        // Get token USD prices & ensure positive
        PythStructs.Price memory inputUsdPrice = pythContract.getPriceUnsafe(inputTokenInfo.priceFeedId);
        if (inputUsdPrice.price <= 0 || inputUsdPrice.conf >= uint64(inputUsdPrice.price))
            revert InvalidOraclePrice(_inputTokenAddress, inputUsdPrice.price, inputUsdPrice.conf);

        PythStructs.Price memory outputUsdPrice = pythContract.getPriceUnsafe(outputTokenInfo.priceFeedId);
        if (outputUsdPrice.price <= 0 || outputUsdPrice.conf >= uint64(outputUsdPrice.price))
            revert InvalidOraclePrice(_outputTokenAddress, outputUsdPrice.price, outputUsdPrice.conf);

        // pricePrecisionDecimals = log10(inputPrice) - log10(outputPrice)
        int256 pricePrecisionDecimals = int256(Math.log10(uint256(int256(inputUsdPrice.price)))) -
            int256(Math.log10(uint256(int256(outputUsdPrice.price))));

        // Require at least MAX(outputTokenDecimals, 18) digits of precision (18 is arbitrary at the moment but is thought to be good enough).
        int256 requiredDigitsOfPrecision;
        if (outputTokenInfo.decimals < 18) {
            requiredDigitsOfPrecision = 18;
        } else {
            requiredDigitsOfPrecision = int256(uint256(outputTokenInfo.decimals));
        }
        int256 precisionBufferExponent = requiredDigitsOfPrecision - pricePrecisionDecimals;
        if (precisionBufferExponent < 0) {
            precisionBufferExponent = 0;
        }

        // price = 10**precisionBufferExponent * inputPrice / outputPrice
        _price.price =
            (10 ** uint256(precisionBufferExponent) * uint256(uint64(inputUsdPrice.price))) /
            uint256(uint64(outputUsdPrice.price));

        // exponent = inputExponent + outputDecimals - outputExponent - inputDecimals - precisionBufferExponent
        _price.exponent =
            inputUsdPrice.expo +
            int32(uint32(outputTokenInfo.decimals)) -
            outputUsdPrice.expo -
            int32(uint32(inputTokenInfo.decimals)) -
            int32(precisionBufferExponent);

        if (inputUsdPrice.publishTime < outputUsdPrice.publishTime) {
            _price.publishTime = inputUsdPrice.publishTime;
        } else {
            _price.publishTime = outputUsdPrice.publishTime;
        }
    }

    /*
     * @inheritdoc IPriceOracle
     */
    function updatePrice(
        address _inputTokenAddress,
        address _outputTokenAddress,
        bytes calldata _oracleData
    ) external payable refundExcess returns (Pricing.OraclePrice memory) {
        _fetchAndValidateTokenInfo(_inputTokenAddress);
        _fetchAndValidateTokenInfo(_outputTokenAddress);

        bytes[] memory updateData = abi.decode(_oracleData, (bytes[]));

        uint256 fee = pythContract.getUpdateFee(updateData);
        if (msg.value < fee) revert InsufficientFee(msg.value, fee);

        pythContract.updatePriceFeeds{value: fee}(updateData);

        return this.getPrice(_inputTokenAddress, _outputTokenAddress);
    }

    /*
     * @inheritdoc IPriceOracle
     */
    function getUpdateFee(bytes calldata _oracleData) external view returns (uint256) {
        bytes[] memory updateData = abi.decode(_oracleData, (bytes[]));
        return pythContract.getUpdateFee(updateData);
    }

    /***********
     * ERC-165 *
     ***********/

    /**
     * Indicates support for IERC165 and IPriceOracle.
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceID) public view override returns (bool) {
        return interfaceID == type(IPriceOracle).interfaceId || super.supportsInterface(interfaceID);
    }

    /**
     * Fetches token info for the provided token address, if it exists in the `addressToTokenInfo` storage field. If it
     * does not exist, this will revert with an UnsupportedTokenAddress error.
     * @param _address The address of the token to fetch.
     * @return _tokenInfo The resulting `TokenInfo` object on successful fetch.
     */
    function _fetchAndValidateTokenInfo(address _address) private view returns (TokenInfo memory _tokenInfo) {
        _tokenInfo = addressToTokenInfo[_address];
        if (_tokenInfo.priceFeedId == bytes32(0)) revert UnsupportedTokenAddress(_address);
    }

    /**
     * Upserts the TokenInfo associated with the provided token addresses in contract storage.
     * @param _tokenAddresses The addresses of the tokens to upsert. Note: indexes in this array correspond 1:1 with indexes in the `_priceFeedIds` array.
     * @param _priceFeedIds The price feed ID of the token associated with the corresponding index of the `_tokenAddresses` array.
     */
    function upsertPriceFeedIds(address[] memory _tokenAddresses, bytes32[] memory _priceFeedIds) external onlyOwner {
        _upsertPriceFeedIdsAsOwner(_tokenAddresses, _priceFeedIds);
    }

    /**
     * Upserts the TokenInfo associated with the provided token addresses in contract storage.
     * @dev This function does no authorization, instead assuming that authorization has been done by the caller of this function.
     * @param _tokenAddresses The addresses of the tokens to upsert. Note: indexes in this array correspond 1:1 with indexes in the `_priceFeedIds` array.
     * @param _priceFeedIds The price feed ID of the token associated with the corresponding index of the `_tokenAddresses` array.
     */
    function _upsertPriceFeedIdsAsOwner(address[] memory _tokenAddresses, bytes32[] memory _priceFeedIds) private {
        if (_tokenAddresses.length != _priceFeedIds.length)
            revert RelatedArraysLengthMismatch(_tokenAddresses.length, _priceFeedIds.length);

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            TokenInfo storage tokenInfo = addressToTokenInfo[_tokenAddresses[i]];
            bytes32 oldPriceFeedId = tokenInfo.priceFeedId;
            tokenInfo.priceFeedId = _priceFeedIds[i];
            if (_priceFeedIds[i] == bytes32(0)) {
                tokenInfo.decimals = 0;
            } else {
                uint8 decimals = IERC20Metadata(_tokenAddresses[i]).decimals();
                tokenInfo.decimals = decimals;
            }
            emit PriceFeedUpdated(_tokenAddresses[i], oldPriceFeedId, _priceFeedIds[i]);
        }
    }
}
