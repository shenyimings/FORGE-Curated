// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                           
*/

//contracts
import {Roles} from "src/Roles.sol";
import {Operator} from "src/Operator/Operator.sol";
import {RewardDistributor} from "src/rewards/RewardDistributor.sol";
import {JumpRateModelV4} from "src/interest/JumpRateModelV4.sol";

import {Types} from "./utils/Types.sol";
import {Events} from "./utils/Events.sol";
import {Helpers} from "./utils/Helpers.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "./mocks/OracleMock.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract Base_Unit_Test is Events, Helpers, Types {
    // ----------- USERS ------------
    address public alice;
    address public bob;
    address public foo;

    // ----------- TOKENS ------------
    ERC20Mock public usdc;
    ERC20Mock public weth;
    ERC20Mock public dai;

    // ----------- MALDA ------------
    Roles public roles;
    Operator public operator;
    OracleMock public oracleOperator;
    RewardDistributor public rewards;
    JumpRateModelV4 public interestModel;

    function setUp() public virtual {
        alice = _spawnAccount(ALICE_KEY, "Alice");
        bob = _spawnAccount(BOB_KEY, "Bob");
        foo = _spawnAccount(FOO_KEY, "Foo");

        usdc = _deployToken("USDC", "USDC", 6);
        weth = _deployToken("WETH", "WETH", 18);
        dai = _deployToken("DAI", "DAI", 18);

        roles = new Roles(address(this));
        vm.label(address(roles), "Roles");

        RewardDistributor rewardsImpl = new RewardDistributor();
        bytes memory rewardsInitData = abi.encodeWithSelector(RewardDistributor.initialize.selector, address(this));
        ERC1967Proxy rewardsProxy = new ERC1967Proxy(address(rewardsImpl), rewardsInitData);
        rewards = RewardDistributor(address(rewardsProxy));
        vm.label(address(rewards), "RewardDistributor");

        Operator oprImp = new Operator();
        bytes memory operatorInitData =
            abi.encodeWithSelector(Operator.initialize.selector, address(roles), address(rewards), address(this));
        ERC1967Proxy operatorProxy = new ERC1967Proxy(address(oprImp), operatorInitData);
        operator = Operator(address(operatorProxy));
        vm.label(address(operator), "Operator");

        // /**
        // * @notice Construct an interest rate model
        // * @param blocksPerYear_ The estimated number of blocks per year
        // * @param baseRatePerYear The base APR, scaled by 1e18
        // * @param multiplierPerYear The rate increase in interest wrt utilization, scaled by 1e18
        // * @param jumpMultiplierPerYear The multiplier per block after utilization point
        // * @param kink_ The utilization point where the jump multiplier applies
        // * @param owner_ The owner of the contract
        // * @param name_ A user-friendly name for the contract
        // */
        //    "interestModel": {
        //         "baseRate": 792744799,
        //         "blocksPerYear": 31536000,
        //         "jumpMultiplier": 251900000000,
        //         "kink": 400000000000000000,
        //         "multiplier": 1981000000,
        //         "name": "mezETH Interest Model"
        //       },
        interestModel = new JumpRateModelV4(
            3153600, 792744799, 1981000000, 251900000000, 400000000000000000, address(this), "InterestModel"
        );
        vm.label(address(interestModel), "InterestModel");

        oracleOperator = new OracleMock(address(this));
        vm.label(address(oracleOperator), "oracleOperator");

        // **** SETUP ****
        rewards.setOperator(address(operator));
        operator.setPriceOracle(address(oracleOperator));
    }

    // ----------- MODIFIERS ------------
    modifier whenPriceIs(uint256 price) {
        oracleOperator.setPrice(price);
        _;
    }

    modifier whenUnderlyingPriceIs(uint256 price) {
        oracleOperator.setUnderlyingPrice(price);
        _;
    }

    modifier inRange(uint256 _value, uint256 _min, uint256 _max) {
        vm.assume(_value >= _min && _value <= _max);
        _;
    }

    modifier resetContext(address _executor) {
        _resetContext(_executor);
        _;
    }

    modifier erc20Approved(address _token, address _executor, address _on, uint256 _amount) {
        _erc20Approve(_token, _executor, _on, _amount);
        _;
    }
}
