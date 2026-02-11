// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {Id, MarketParams, IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";
import {MockMorpho} from "../../mock/MockMorpho.sol";

contract MorphoLendingAdapterInitializeTest is MorphoLendingAdapterTest {
    /// forge-config: default.fuzz.runs = 1
    function testFuzz_initialize(Id marketId, MarketParams memory marketParams) public {
        morpho.mockSetMarketParams(marketId, marketParams);

        // Mock the calls to get the decimals of the loan token and collateral token in the initialize function. Not important
        // for the test, but reverts if not mocked
        vm.mockCall(
            address(marketParams.loanToken), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18)
        );
        vm.mockCall(
            address(marketParams.collateralToken),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(18)
        );

        MorphoLendingAdapter _lendingAdapter = new MorphoLendingAdapter(leverageManager, IMorpho(address(morpho)));
        assertEq(address(_lendingAdapter.leverageManager()), address(leverageManager));
        assertEq(address(_lendingAdapter.morpho()), address(morpho));

        vm.expectEmit(true, true, true, true);
        emit IMorphoLendingAdapter.MorphoLendingAdapterInitialized(marketId, marketParams, authorizedCreator);
        vm.expectEmit(true, true, true, true);
        emit Initializable.Initialized(1);
        _lendingAdapter.initialize(marketId, authorizedCreator);

        assertEq(address(_lendingAdapter.leverageManager()), address(leverageManager));
        assertEq(address(_lendingAdapter.morpho()), address(morpho));

        (address loanToken, address _collateralToken, address oracle, address irm, uint256 lltv) =
            _lendingAdapter.marketParams();
        assertEq(loanToken, marketParams.loanToken);
        assertEq(_collateralToken, marketParams.collateralToken);
        assertEq(oracle, marketParams.oracle);
        assertEq(irm, marketParams.irm);
        assertEq(lltv, marketParams.lltv);
        assertEq(_lendingAdapter.authorizedCreator(), authorizedCreator);
    }

    function test_initialize_RevertIf_Initialized() public {
        MorphoLendingAdapter _lendingAdapter = new MorphoLendingAdapter(leverageManager, IMorpho(address(morpho)));
        _lendingAdapter.initialize(defaultMarketId, authorizedCreator);

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        _lendingAdapter.initialize(defaultMarketId, authorizedCreator);
    }
}
