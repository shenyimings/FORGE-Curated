import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

// Add this mock oracle contract
contract MockOracle is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;

    constructor(int256 initialPrice, uint8 initialDecimals) {
        _price = initialPrice;
        _decimals = initialDecimals;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Oracle";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80
    ) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _price, 0, 1e18, 0);
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, _price, 0, 1e18, 0);
    }

    // Function to update the price (for testing purposes)
    function updatePriceAndDecimals(
        int256 newPrice,
        uint8 newDecimals
    ) external {
        _price = newPrice;
        _decimals = newDecimals;
    }
}
