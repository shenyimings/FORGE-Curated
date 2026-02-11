// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "../Pricing.sol";
import "../interfaces/IPriceOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title Mock price oracle that may be used to set prices and test LOC interactions with a price oracle.
 */
contract MockPriceOracle is IPriceOracle, Ownable, IERC165 {
    bytes4 constant IPRICE_ORACLE_INTERFACE_ID =
        this.getPrice.selector ^ this.updatePrice.selector ^ this.getUpdateFee.selector;

    mapping(address => mapping(address => Pricing.OraclePrice)) private prices;

    constructor() Ownable(msg.sender) {}

    /**
     * @inheritdoc IPriceOracle
     */
    function getPrice(
        address _inputTokenAddress,
        address _outputTokenAddress
    ) external view returns (Pricing.OraclePrice memory _price) {
        _price = prices[_inputTokenAddress][_outputTokenAddress];
        require(_price.publishTime > 0, "no price");
    }

    /**
     * @notice Mocked version of updatePrice function, allowing an oracle price to be set.
     * @dev This may be used for testing LetterOfCredit::convertLOC(...) and LetterOfCredit::redeemLOC(...), passing
     * an opaque byte array through the LetterOfCredit contract to this mock oracle contract to update and return its price.
     * Note: the expected format of the provided `_oracleData` is `abi.encode(price,exponent)`.
     *
     * @inheritdoc IPriceOracle
     */
    function updatePrice(
        address _inputTokenAddress,
        address _outputTokenAddress,
        bytes calldata _oracleData
    ) external payable returns (Pricing.OraclePrice memory _price) {
        require(_oracleData.length == 64, "bad oracle data");

        uint256 price;
        int32 exponent;

        assembly {
            price := calldataload(0x84) // Skip 4 bytes for method id, 32 bytes for input address, 32 bytes for output address, and 32 bytes for pointer to bytes start, 32 bytes for byte length
            exponent := calldataload(0xa4)
        }

        _price = Pricing.OraclePrice(price, exponent, block.timestamp);

        prices[_inputTokenAddress][_outputTokenAddress] = _price;
    }

    /**
     * @notice Sets the price between the input and output token of a potential trade.
     * @dev Note: the `_price` should be the output-amount-per-one-input-token, which includes the difference in
     * decimals of the respective ERC-20 tokens.
     * @dev The `_exponent` makes up for the fact that `_price` cannot be a float in the EVM. The `_price` should be
     * multiplied by 10**_exponent in order to get the true price. Note: order of operations is very important in order
     * to not truncate.
     * @param _inputTokenAddress The address of the token to be input into the hypothetical trade in exchange for the output token.
     * @param _outputTokenAddress The address of the token to be received as a result of this hypothetical trade.
     * @param _price The output-per-unit-input token price, including decimal discrepancy between the two assets.
     * @param _exponent The exponent to make up for the fact that the `_price` cannot represent floats.
     * @param _publishTime The publish time in seconds since the epoch for this price.
     */
    function setMockPrice(
        address _inputTokenAddress,
        address _outputTokenAddress,
        uint256 _price,
        int32 _exponent,
        uint256 _publishTime
    ) external onlyOwner {
        require(prices[_inputTokenAddress][_outputTokenAddress].publishTime <= _publishTime, "publish price stale");
        prices[_inputTokenAddress][_outputTokenAddress] = Pricing.OraclePrice(_price, _exponent, _publishTime);
    }

    /**
     * @notice Gets the fee required to use the provided `_oracleData` in a call to `updatePrice`.
     * @return The fee that must be passed as msg.value to `updatePrice` to submit the provided oracle data.
     */
    function getUpdateFee(bytes calldata) external pure returns (uint256) {
        return 0;
    }

    /**
     * Indicates support for IERC165 and IPriceOracle.
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceID) public pure override returns (bool) {
        return interfaceID == type(IERC165).interfaceId || interfaceID == type(IPriceOracle).interfaceId;
    }
}
