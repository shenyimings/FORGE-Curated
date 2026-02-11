// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Factory} from "src/Factory.sol";
import {DistributorFactory} from "src/factories/DistributorFactory.sol";
import {GGVStrategyFactory} from "src/factories/GGVStrategyFactory.sol";
import {StvPoolFactory} from "src/factories/StvPoolFactory.sol";
import {StvStETHPoolFactory} from "src/factories/StvStETHPoolFactory.sol";
import {TimelockFactory} from "src/factories/TimelockFactory.sol";
import {WithdrawalQueueFactory} from "src/factories/WithdrawalQueueFactory.sol";
import {DummyImplementation} from "src/proxy/DummyImplementation.sol";

contract FactoryHelper {
    Factory.SubFactories public subFactories;
    Factory.TimelockConfig public defaultTimelockConfig;

    constructor() {
        subFactories.stvPoolFactory = address(new StvPoolFactory());
        subFactories.stvStETHPoolFactory = address(new StvStETHPoolFactory());
        subFactories.withdrawalQueueFactory = address(new WithdrawalQueueFactory());
        subFactories.distributorFactory = address(new DistributorFactory());
        subFactories.timelockFactory = address(new TimelockFactory());

        defaultTimelockConfig =
            Factory.TimelockConfig({minDelaySeconds: 7 days, proposer: address(this), executor: address(this)});
    }

    function deployMainFactory(address locatorAddress) external returns (Factory factory) {
        factory = new Factory(locatorAddress, subFactories);
    }
}
