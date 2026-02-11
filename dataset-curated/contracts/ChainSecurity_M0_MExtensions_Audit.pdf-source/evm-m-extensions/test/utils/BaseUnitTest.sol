// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { ContinuousIndexingMath } from "../../lib/common/src/libs/ContinuousIndexingMath.sol";
import { IndexingMath } from "../../lib/common/src/libs/IndexingMath.sol";
import { Upgrades, UnsafeUpgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { SwapFacility } from "../../src/swap/SwapFacility.sol";

import { MockM, MockRateOracle, MockRegistrar } from "../utils/Mocks.sol";

import { Helpers } from "./Helpers.sol";

contract BaseUnitTest is Helpers, Test {
    uint16 public constant YIELD_FEE_RATE = 2000; // 20%

    bytes32 public constant EARNERS_LIST = "earners";
    uint32 public constant M_EARNER_RATE = ContinuousIndexingMath.BPS_SCALED_ONE / 10; // 10% APY

    uint56 public constant EXP_SCALED_ONE = 1e12;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant M_SWAPPER_ROLE = keccak256("M_SWAPPER_ROLE");

    MockM public mToken;
    MockRateOracle public rateOracle;
    MockRegistrar public registrar;
    SwapFacility public swapFacility;

    uint40 public startTimestamp = 0;
    uint128 public expectedCurrentIndex;
    uint32 public mYiedFeeEarnerRate;

    address public admin = makeAddr("admin");
    address public blacklistManager = makeAddr("blacklistManager");
    address public yieldRecipient = makeAddr("yieldRecipient");
    address public yieldRecipientManager = makeAddr("yieldRecipientManager");

    address public feeRecipient = makeAddr("feeRecipient");
    address public yieldFeeManager = makeAddr("yieldFeeManager");
    address public claimRecipientManager = makeAddr("claimRecipientManager");

    address public alice;
    uint256 public aliceKey;

    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public charlie = makeAddr("charlie");
    address public david = makeAddr("david");

    address[] public accounts;

    function setUp() public virtual {
        vm.warp(startTimestamp);

        mToken = new MockM();
        rateOracle = new MockRateOracle();

        registrar = new MockRegistrar();

        swapFacility = SwapFacility(
            UnsafeUpgrades.deployUUPSProxy(
                address(new SwapFacility(address(mToken), address(registrar), makeAddr("swapAdapter"))),
                abi.encodeWithSelector(SwapFacility.initialize.selector, admin)
            )
        );

        mToken.setEarnerRate(M_EARNER_RATE);

        (alice, aliceKey) = makeAddrAndKey("alice");
        accounts = [alice, bob, charlie, david];

        expectedCurrentIndex = 1_100000068703;
        mYiedFeeEarnerRate = _getEarnerRate(M_EARNER_RATE, YIELD_FEE_RATE);

        vm.prank(admin);
        swapFacility.grantRole(M_SWAPPER_ROLE, alice);
    }

    /* ============ Utils ============ */

    function _getBalanceWithYield(
        uint240 balance,
        uint112 principal,
        uint128 index
    ) internal pure returns (uint240 balanceWithYield_, uint240 yield_) {
        balanceWithYield_ = IndexingMath.getPresentAmountRoundedDown(principal, index);
        yield_ = (balanceWithYield_ <= balance) ? 0 : balanceWithYield_ - balance;
    }

    function _getMaxAmount(uint128 index_) internal pure returns (uint240) {
        return (uint240(type(uint112).max) * index_) / EXP_SCALED_ONE;
    }

    /* ============ Fuzz Utils ============ */

    function _getFuzzedBalances(
        uint128 index,
        uint240 balanceWithYield,
        uint240 balance,
        uint240 maxAmount
    ) internal pure returns (uint240, uint240) {
        balanceWithYield = uint240(bound(balanceWithYield, 0, maxAmount));
        balance = uint240(bound(balance, (balanceWithYield * EXP_SCALED_ONE) / index, balanceWithYield));

        return (balanceWithYield, balance);
    }

    function _getFuzzedIndices(
        uint128 currentMIndex_,
        uint128 enableMIndex_,
        uint128 disableIndex_
    ) internal pure returns (uint128, uint128, uint128) {
        currentMIndex_ = uint128(bound(currentMIndex_, EXP_SCALED_ONE, 10 * EXP_SCALED_ONE));
        enableMIndex_ = uint128(bound(enableMIndex_, EXP_SCALED_ONE, currentMIndex_));

        disableIndex_ = uint128(
            bound(disableIndex_, EXP_SCALED_ONE, (currentMIndex_ * EXP_SCALED_ONE) / enableMIndex_)
        );

        return (currentMIndex_, enableMIndex_, disableIndex_);
    }
}
