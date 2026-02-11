// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {Id, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";

// Internal imports
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {IMorphoLendingAdapterFactory} from "src/interfaces/IMorphoLendingAdapterFactory.sol";
import {MorphoLendingAdapterFactoryTest} from "./MorphoLendingAdapterFactory.t.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";

contract MorphoLendingAdapterFactoryDeployAdapterTest is MorphoLendingAdapterFactoryTest {
    function testFuzz_deployAdapter(address sender, address authorizedCreator, bytes32 baseSaltA, bytes32 baseSaltB)
        public
    {
        vm.assume(baseSaltA != baseSaltB);
        address expectedAddress = factory.computeAddress(sender, baseSaltA);

        vm.expectEmit(true, true, true, true);
        emit IMorphoLendingAdapterFactory.MorphoLendingAdapterDeployed(IMorphoLendingAdapter(expectedAddress));
        vm.expectEmit(true, true, true, true);
        emit Initializable.Initialized(1);
        vm.prank(sender);
        IMorphoLendingAdapter lendingAdapterA = factory.deployAdapter(defaultMarketId, authorizedCreator, baseSaltA);

        assertEq(address(lendingAdapterA), expectedAddress);
        assertEq(abi.encode(lendingAdapterA.morphoMarketId()), abi.encode(defaultMarketId));

        // Cannot initialize again
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        MorphoLendingAdapter(address(lendingAdapterA)).initialize(defaultMarketId, authorizedCreator);

        // Setup another market to deploy another adapter using a different market
        Id _marketId = Id.wrap("randomId");
        MarketParams memory _marketParams = MarketParams({
            loanToken: address(debtToken),
            collateralToken: address(collateralToken),
            oracle: makeAddr("oracle"),
            irm: makeAddr("irm"),
            lltv: 0.95e18
        });
        morpho.mockSetMarketParams(_marketId, _marketParams);

        // Cannot deploy another adapter with the same base salt
        vm.expectRevert(abi.encodeWithSelector(Errors.FailedDeployment.selector));
        vm.prank(sender);
        factory.deployAdapter(_marketId, authorizedCreator, baseSaltA);

        expectedAddress = factory.computeAddress(sender, baseSaltB);

        vm.expectEmit(true, true, true, true);
        emit IMorphoLendingAdapterFactory.MorphoLendingAdapterDeployed(IMorphoLendingAdapter(expectedAddress));
        vm.expectEmit(true, true, true, true);
        emit Initializable.Initialized(1);
        vm.prank(sender);
        IMorphoLendingAdapter lendingAdapterB = factory.deployAdapter(_marketId, authorizedCreator, baseSaltB);

        assertEq(address(lendingAdapterB), expectedAddress);
        assertEq(abi.encode(lendingAdapterB.morphoMarketId()), abi.encode(_marketId));

        // Cannot initialize again
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        MorphoLendingAdapter(address(lendingAdapterB)).initialize(_marketId, authorizedCreator);
    }
}
