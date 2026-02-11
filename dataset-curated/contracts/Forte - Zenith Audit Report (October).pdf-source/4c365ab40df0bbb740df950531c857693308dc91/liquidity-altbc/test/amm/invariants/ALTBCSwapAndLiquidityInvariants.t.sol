/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {packedFloat, MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {GenericERC20} from "liquidity-base/src/example/ERC20/GenericERC20.sol";
import {TestCommonSetup} from "liquidity-base/test/util/TestCommonSetup.sol";
import {TestCommon, LPToken} from "liquidity-base/test/util/TestCommon.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ALTBCPool} from "src/amm/ALTBCPool.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import {packedFloat, MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

contract SwapAndLiquidityHelper is TestCommon {
    using MathLibs for packedFloat;
    using MathLibs for int256;
    using MathLibs for ALTBCDef;

    address[] public actors;

    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    uint public totalRevenueClaimed;
    uint public virtualRevenueClaimed;

    ALTBCPool altbcPool;
    mapping(address owner => uint256) public LPTokenByOwner;

    constructor(LPToken _lpToken, PoolBase _poolBase, uint numberOfActors) {
        altbcPool = ALTBCPool(address(_poolBase));
        for (uint i = 0; i < numberOfActors; i++) actors.push(address(uint160(i + 0xac01)));
        virtualRevenueClaimed = getTotalRevenue(_lpToken);
    }

    function getTotalRevenue(LPToken _lpToken) internal view returns (uint) {
        packedFloat h = altbcPool.retrieveH();
        (packedFloat wInactive, ) = _lpToken.getLPToken(altbcPool.inactiveLpId());
        return uint((h.mul(int(altbcPool.w()).toPackedFloat(int(-18)).sub(wInactive))).convertpackedFloatToWAD());
    }

    function sellY(uint _amountIn) public {
        IERC20(altbcPool.yToken()).balanceOf(address(this));
        IERC20(altbcPool.xToken()).balanceOf(address(this));
        _amountIn = bound(_amountIn, 1, 1e11);
        (uint256 expectedAmountOut, , ) = altbcPool.simSwap(altbcPool.yToken(), _amountIn);
        IERC20(altbcPool.yToken()).approve(address(altbcPool), _amountIn);
        altbcPool.swap(altbcPool.yToken(), _amountIn, expectedAmountOut / 2 + 1, address(0), getValidExpiration());
    }

    function sellX(uint _amountIn, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint xBalance = IERC20(altbcPool.xToken()).balanceOf(currentActor);
        _amountIn = bound(_amountIn, 1, xBalance / 2);
        IERC20(altbcPool.xToken()).approve(address(altbcPool), _amountIn);
        (uint256 expectedAmountOut, , ) = altbcPool.simSwap(altbcPool.xToken(), _amountIn);
        altbcPool.swap(altbcPool.xToken(), _amountIn, expectedAmountOut, currentActor, getValidExpiration());
    }

    function depositLiquidity(uint _amount, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint xBalance = IERC20(altbcPool.xToken()).balanceOf(currentActor);
        _amount = bound(_amount, 1, xBalance - 2);
        IERC20(altbcPool.yToken()).approve(address(altbcPool), _amount);
        IERC20(altbcPool.xToken()).approve(address(altbcPool), _amount);
        uint existingTokenId = LPTokenByOwner[currentActor];
        uint deltaVirtualClaimedRev;
        if (existingTokenId == 0) {
            uint currentTokenId = lpToken.currentTokenId() + 1;
            altbcPool.depositLiquidity(0, _amount, _amount, 1, 1, getValidExpiration());
            LPTokenByOwner[currentActor] = currentTokenId;
            (packedFloat wj, ) = lpToken.getLPToken(currentTokenId);
            deltaVirtualClaimedRev = uint((wj.mul(altbcPool.retrieveH())).convertpackedFloatToSpecificDecimals(18));
        } else {
            (packedFloat wBefore, ) = lpToken.getLPToken(existingTokenId);
            altbcPool.depositLiquidity(existingTokenId, _amount, _amount, 1, 1, getValidExpiration());
            (packedFloat wAfter, ) = lpToken.getLPToken(existingTokenId);
            deltaVirtualClaimedRev = uint(((wAfter.sub(wBefore)).mul(altbcPool.retrieveH())).convertpackedFloatToSpecificDecimals(18));
        }
        virtualRevenueClaimed += deltaVirtualClaimedRev;
    }

    function withdrawLiquidity(uint _amount, uint256 actorIndexSeed) public useActor(actorIndexSeed) {
        uint existingTokenId = LPTokenByOwner[currentActor];
        (packedFloat wj, ) = lpToken.getLPToken(existingTokenId);
        _amount = bound(_amount, 1, uint(wj.convertpackedFloatToWAD()));
        altbcPool.withdrawPartialLiquidity(existingTokenId, _amount, currentActor, 1, 1, getValidExpiration());
        (packedFloat wAfter, ) = lpToken.getLPToken(existingTokenId);
        uint deltaVirtualClaimedRev = uint(((wj.sub(wAfter)).mul(altbcPool.retrieveH())).convertpackedFloatToSpecificDecimals(18));
        virtualRevenueClaimed -= deltaVirtualClaimedRev;
    }

    function withdrawRevenue(uint _amount) public {
        uint existingTokenId = LPTokenByOwner[address(this)];
        if (existingTokenId == 0) {
            depositLiquidity(_amount, 0);
        } else {
            uint revenue = altbcPool.revenueAvailable(existingTokenId);
            _amount = bound(_amount, 0, revenue);
            altbcPool.withdrawRevenue(existingTokenId, _amount, address(this));
        }
    }
}

/**
 * @title Test all invariants in relation to adding liquidity to the altbcPool.
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract SwapAndLiquidityInvariants is TestCommonSetup, ALTBCTestSetup {
    SwapAndLiquidityHelper _helper;

    uint xTokenLiquidity;
    uint yTokenLiquidity;

    uint initialPrice;
    uint initialW;
    uint nActors = 5;

    function _setUp() public {
        _setupPool(false);
        _helper = new SwapAndLiquidityHelper(lpToken, pool, nActors);
        vm.startPrank(admin);
        for (uint i = 0; i < nActors; i++) {
            GenericERC20(pool.yToken()).mint(address(_helper.actors(i)), 1e30);
            GenericERC20(pool.xToken()).transfer(address(_helper.actors(i)), 1e22);
        }
        // initial swap to make sure the pool has both tokens available to trade
        uint _amountIn = 1e22;
        pool.swap(pool.yToken(), _amountIn, 1, address(0), getValidExpiration());
        vm.stopPrank();
    }
}

contract SellYAndLiquidityInvariants is SwapAndLiquidityInvariants {
    function setUp() public {
        _setUp();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SwapAndLiquidityHelper(address(_helper)).depositLiquidity.selector;
        selectors[1] = SwapAndLiquidityHelper(address(_helper)).withdrawLiquidity.selector;
        selectors[2] = SwapAndLiquidityHelper(address(_helper)).withdrawRevenue.selector;
        selectors[3] = SwapAndLiquidityHelper(address(_helper)).sellY.selector;
        targetContract(address(_helper));
        targetSelector(FuzzSelector({addr: address(_helper), selectors: selectors}));
        targetSender(alice);

        initialPrice = pool.spotPrice();
    }

    function invariant_priceCannotDecrease() public view {
        assert(pool.spotPrice() >= initialPrice);
    }
}

contract SellXAndLiquidityInvariants is SwapAndLiquidityInvariants {
    function setUp() public {
        _setUp();
        vm.startPrank(admin);
        (uint expected, , ) = pool.simSwapReversed(pool.xToken(), X_TOKEN_MAX_SUPPLY / 100);
        pool.swap(pool.yToken(), expected, 1, address(_helper), getValidExpiration());
        vm.stopPrank();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SwapAndLiquidityHelper(address(_helper)).depositLiquidity.selector;
        selectors[1] = SwapAndLiquidityHelper(address(_helper)).withdrawLiquidity.selector;
        selectors[2] = SwapAndLiquidityHelper(address(_helper)).withdrawRevenue.selector;
        selectors[3] = SwapAndLiquidityHelper(address(_helper)).sellX.selector;
        targetContract(address(_helper));
        targetSelector(FuzzSelector({addr: address(_helper), selectors: selectors}));
        targetSender(alice);

        initialPrice = pool.spotPrice();
    }

    function invariant_priceCannotDecrease() public view {
        assert(pool.spotPrice() <= initialPrice);
    }
}

contract RevenueIncreaseInvariants is SwapAndLiquidityInvariants {
    function setUp() public {
        _setUp();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = SwapAndLiquidityHelper(address(_helper)).depositLiquidity.selector;
        selectors[1] = SwapAndLiquidityHelper(address(_helper)).withdrawLiquidity.selector;
        selectors[2] = SwapAndLiquidityHelper(address(_helper)).withdrawRevenue.selector;
        selectors[3] = SwapAndLiquidityHelper(address(_helper)).sellX.selector;
        selectors[4] = SwapAndLiquidityHelper(address(_helper)).sellY.selector;
        targetContract(address(_helper));
        targetSelector(FuzzSelector({addr: address(_helper), selectors: selectors}));
        targetSender(alice);

        initialW = pool.w();
    }

    function invariant_revenueCannotDecrease() public view {
        assert(pool.w() >= initialW);
    }
}

contract RevenueConsistencyInvariants is SwapAndLiquidityInvariants {
    using ALTBCEquations for ALTBCDef;
    using MathLibs for packedFloat;
    using MathLibs for int256;

    uint constant TOLERANCE_NUM = 1;
    uint constant TOLERANCE_DEN = 10 ** 19;
    function setUp() public {
        _setUp();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = SwapAndLiquidityHelper(address(_helper)).depositLiquidity.selector;
        selectors[1] = SwapAndLiquidityHelper(address(_helper)).withdrawLiquidity.selector;
        selectors[2] = SwapAndLiquidityHelper(address(_helper)).withdrawRevenue.selector;
        selectors[3] = SwapAndLiquidityHelper(address(_helper)).sellX.selector;
        selectors[4] = SwapAndLiquidityHelper(address(_helper)).sellY.selector;
        targetContract(address(_helper));
        targetSelector(FuzzSelector({addr: address(_helper), selectors: selectors}));
        targetSender(alice);

        initialW = pool.w();
    }

    function invariant_allRevenueVariablesAddUp() public view {
        uint revenueClaimed = _helper.totalRevenueClaimed(); // tracker of revenue claimed (excempted liquidity withdrawals)
        uint revenueAvailableHelper = getHelperAvailableRev(); // wjHelper*(h - rjHelper)
        uint revenueAvailableDeployer = ALTBCPool(address(pool)).revenueAvailable(2); // wjDeployer*(h - rjDeployer)
        uint totalTheoreticalRevenue = getTotalRevenue();
        uint virtualRevenueClaimed = _helper.virtualRevenueClaimed();

        uint realAvailableRevenue = revenueAvailableHelper + revenueAvailableDeployer;
        uint theoreticalAvailableRevenue = totalTheoreticalRevenue - revenueClaimed - virtualRevenueClaimed;
        // (|t - r| * Td) < (Tn * t); where t is totalTheoreticalRevenue, r is realRevenue, Td is TOLERANCE_DEN, and Tn is TOLERANCE_NUM. Equivalent to ((|t - r|) / t) < (Tn / Td)
        /// @notice the absolute difference is necessary in this case otherwise the test would run into an underflow error. This means that the real revenue can be above theoretical revenue.
        assertLe(
            ((
                theoreticalAvailableRevenue > realAvailableRevenue
                    ? theoreticalAvailableRevenue - realAvailableRevenue
                    : realAvailableRevenue - theoreticalAvailableRevenue
            ) * TOLERANCE_DEN),
            TOLERANCE_NUM * theoreticalAvailableRevenue
        );
    }

    function getHelperAvailableRev() internal view returns (uint revenueAvailable) {
        uint actorsNFTStartsAt = 3;
        uint ghostLPs = 2; // just to check that no mysterious nft position is minted
        for (uint i = actorsNFTStartsAt; i < nActors + actorsNFTStartsAt + ghostLPs; i++) {
            revenueAvailable += ALTBCPool(address(pool)).revenueAvailable(i); // wjHelper*(h - rjHelper)
        }
    }

    function getTotalRevenue() internal view returns (uint) {
        packedFloat h = ALTBCPool(address(pool)).retrieveH();
        (packedFloat wInactive, ) = lpToken.getLPToken(ALTBCPool(address(pool)).inactiveLpId());
        return uint((h.mul(int(ALTBCPool(address(pool)).w()).toPackedFloat(int(-18)).sub(wInactive))).convertpackedFloatToWAD());
    }
}
