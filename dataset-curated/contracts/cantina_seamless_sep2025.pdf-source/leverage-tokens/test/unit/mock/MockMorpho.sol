// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {Id, IMorphoBase, Market, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {LeverageRouter} from "src/periphery/LeverageRouter.sol";

contract MockMorpho is Test {
    mapping(Id => MarketParams) public idToMarketParams;

    mapping(Id => Market) public idToMarket;

    constructor(Id marketId, MarketParams memory marketParams) {
        idToMarketParams[marketId] = marketParams;
    }

    /// @dev This function is used by Morpho periphery libraries to fetch storage variables from Morpho. In unit tests, its return value should be mocked
    function extSloads(bytes32[] memory slot) external view returns (bytes32[] memory data) {}

    function market(Id id) external view returns (Market memory) {
        return idToMarket[id];
    }

    function mockSetMarket(Id id, Market memory _market) external {
        idToMarket[id] = _market;
    }

    function mockSetMarketParams(Id marketId, MarketParams memory marketParams) external {
        idToMarketParams[marketId] = marketParams;
    }

    function accrueInterest(MarketParams memory marketParams) external {}

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256, /* shares */
        address, /* onBehalf */
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        // Mocked return values that are not used in test.
        assetsBorrowed = assets;
        sharesBorrowed = assets;

        IERC20(marketParams.loanToken).transfer(receiver, assets);
    }

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256, /* shares */
        address, /* onBehalf */
        bytes memory /* data */
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        // Mocked return values that are not used in test.
        assetsRepaid = assets;
        sharesRepaid = assets;

        IERC20(marketParams.loanToken).transferFrom(msg.sender, address(this), assets);
    }

    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address, /* onBehalf */
        bytes memory /* data */
    ) external {
        IERC20(marketParams.collateralToken).transferFrom(msg.sender, address(this), assets);
    }

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address, /* onBehalf */
        address receiver
    ) external {
        IERC20(marketParams.collateralToken).transfer(receiver, assets);
    }

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        deal(token, msg.sender, IERC20(token).balanceOf(msg.sender) + assets);
        LeverageRouter(payable(msg.sender)).onMorphoFlashLoan(assets, data);

        require(
            IERC20(token).allowance(msg.sender, address(this)) >= assets,
            "MockMorpho: Morpho not approved to spend enough assets to repay flash loan"
        );
    }
}
