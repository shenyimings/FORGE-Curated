// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStrategyFactory} from "src/interfaces/IStrategyFactory.sol";
import {GGVStrategy} from "src/strategy/GGVStrategy.sol";
import {StrategyCallForwarder} from "src/strategy/StrategyCallForwarder.sol";

contract GGVStrategyFactory is IStrategyFactory {
    bytes32 public immutable STRATEGY_ID = keccak256("strategy.ggv.v1");
    address public immutable TELLER;
    address public immutable BORING_QUEUE;

    constructor(address _teller, address _boringQueue) {
        require(_teller.code.length > 0, "TELLER: not a contract");
        require(_boringQueue.code.length > 0, "BORING_QUEUE: not a contract");
        TELLER = _teller;
        BORING_QUEUE = _boringQueue;
    }

    function deploy(address _pool, bytes calldata _deployBytes) external returns (address impl) {
        // _deployBytes is unused for GGVStrategy, but required by IStrategyFactory interface
        _deployBytes;
        address strategyCallForwarderImpl = address(new StrategyCallForwarder());
        impl = address(new GGVStrategy(STRATEGY_ID, strategyCallForwarderImpl, _pool, TELLER, BORING_QUEUE));
    }
}
