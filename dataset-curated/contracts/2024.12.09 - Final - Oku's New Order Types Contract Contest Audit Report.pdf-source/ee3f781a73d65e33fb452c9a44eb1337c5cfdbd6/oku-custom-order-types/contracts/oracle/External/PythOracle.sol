// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../IPythRelay.sol";
import "../../interfaces/pyth/IPyth.sol";


contract PythOracle is IPythRelay {
    IPyth public immutable pythOracle;
    bytes32 public immutable tokenId;
    uint256 public immutable noOlderThan;
    address public immutable underlying;

    constructor(
        IPyth _pythOraclContract,
        bytes32 _tokenId,
        uint256 _noOlderThan,
        address _underlying
    ) {
        pythOracle = _pythOraclContract;
        tokenId = _tokenId;
        noOlderThan = _noOlderThan;
        underlying = _underlying;
    }

    function currentValue() external view override returns (uint256) {
        IPyth.Price memory price = pythOracle.getPriceUnsafe(tokenId);
        require(
            price.publishTime < block.timestamp - noOlderThan,
            "Stale Price"
        );
        return uint256(uint64(price.price));
    }

    function updatePrice(
        bytes[] calldata priceUpdate
    ) external payable override returns (uint256 updatedPrice) {
        // Submit a priceUpdate to the Pyth contract to update the on-chain price.
        // Updating the price requires paying the fee returned by getUpdateFee.
        // WARNING: These lines are required to ensure the getPriceNoOlderThan call below succeeds. If you remove them, transactions may fail with "0x19abf40e" error.
        uint fee = pythOracle.getUpdateFee(priceUpdate);
        pythOracle.updatePriceFeeds{value: fee}(priceUpdate);

        IPyth.Price memory price = pythOracle.getPriceNoOlderThan(
            tokenId,
            uint256(uint64(noOlderThan))
        );
        updatedPrice = uint256(uint64(price.price));
    }

    function getUpdateFee(bytes[] calldata priceUpdate) external view override returns (uint fee){
        return pythOracle.getUpdateFee(priceUpdate);
    }
}
