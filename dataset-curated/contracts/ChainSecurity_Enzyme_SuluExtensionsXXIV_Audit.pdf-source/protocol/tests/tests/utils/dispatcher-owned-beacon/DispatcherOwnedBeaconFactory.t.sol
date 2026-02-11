// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IntegrationTest} from "tests/bases/IntegrationTest.sol";

import {IDispatcherOwnedBeaconFactory} from "tests/interfaces/internal/IDispatcherOwnedBeaconFactory.sol";

contract DispatcherOwnedBeaconFactoryTest is IntegrationTest {
    IDispatcherOwnedBeaconFactory beaconFactory;

    function setUp() public override {
        setUpStandaloneEnvironment();

        MockImplementation implementation = new MockImplementation();

        beaconFactory = __deployBeaconFactory({_implementation: address(implementation)});
    }

    // DEPLOYMENT

    function __deployBeaconFactory(address _implementation)
        private
        returns (IDispatcherOwnedBeaconFactory beaconFactory_)
    {
        return IDispatcherOwnedBeaconFactory(
            deployCode("DispatcherOwnedBeaconFactory.sol", abi.encode(core.persistent.dispatcher, _implementation))
        );
    }

    // TESTS

    function test_deployProxy_success() public {
        uint256 foo = 123;

        bytes memory constructData = abi.encodeWithSelector(MockImplementation.init.selector, foo);

        address proxyAddress = beaconFactory.deployProxy({_constructData: constructData});

        assertEq(MockImplementation(proxyAddress).foo(), foo);
    }
}

contract MockImplementation {
    uint256 public foo;

    function init(uint256 _foo) external {
        foo = _foo;
    }
}
