// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";
import {TestCommonSetup} from "lib/liquidity-base/test/util/TestCommonSetup.sol";
import "forge-std/console2.sol";

abstract contract ALTBCPoolDeployment is TestCommonSetup, ALTBCTestSetup {
    ALTBCPool _pool;

    using ALTBCEquations for ALTBCDef;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    uint256 constant MAX_SUPPLY = 1e11 * ERC20_DECIMALS;
    packedFloat wactiveLimit = int(1).toPackedFloat(-2);

    bool useStableCoin;
    address yTokenAddr;

    function _setUp(bool _useStableCoin) internal {
        useStableCoin = _useStableCoin;
        _setUpTokens(1e29);
        _deployFactory();

        _loadAdminAndAlice();
        vm.startPrank(admin);
    }

    function _deployPool(uint _wactive, uint _wInactive) internal {
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        yTokenAddr = useStableCoin ? address(stableCoin) : address(yToken);
        address poolAddr = altbcFactory.createPool(address(xToken), yTokenAddr, 0, altbcInput, _wactive, _wInactive);
        _pool = ALTBCPool(poolAddr);
    }

    function _deployPool(uint _wactive, uint _wInactive, string memory revertMessage) internal {
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        yTokenAddr = useStableCoin ? address(stableCoin) : address(yToken);
        vm.expectRevert(abi.encodeWithSignature(revertMessage));
        address poolAddr = altbcFactory.createPool(address(xToken), yTokenAddr, 0, altbcInput, _wactive, _wInactive);
        _pool = ALTBCPool(poolAddr);
    }

    function _wInactiveWithdrawHelper(uint _initialWj, uint _tokenId, uint withdrawShare) internal {
        vm.startPrank(admin);
        packedFloat wj;
        packedFloat previousWj;
        packedFloat rj;
        (wj, rj) = lpToken.getLPToken(_tokenId);
        assertEq(uint(wj.convertpackedFloatToWAD()), _initialWj);
        uint withdrawAmount = _initialWj / withdrawShare;
        uint remainderAmount = _initialWj % withdrawShare;

        while (withdrawShare > 0 && withdrawAmount > 0) {
            (previousWj, ) = lpToken.getLPToken(_tokenId);
            (uint256 minAx, uint256 minAy, , , , , ) = ALTBCPool(address(_pool)).simulateWithdrawLiquidity(
                _tokenId,
                withdrawAmount,
                packedFloat.wrap(0)
            );
            _pool.withdrawPartialLiquidity(_tokenId, withdrawAmount, msg.sender, minAx, minAy, getValidExpiration());
            (wj, ) = lpToken.getLPToken(_tokenId);
            assertEq(
                uint(previousWj.convertpackedFloatToWAD()),
                withdrawAmount + uint(wj.convertpackedFloatToWAD()),
                "previous wj should equal current wj plus withdraw"
            );
            withdrawShare--;
        }

        if (remainderAmount > 0) {
            (previousWj, ) = lpToken.getLPToken(_tokenId);
            (uint minAx, uint minAy, , , , , ) = ALTBCPool(address(_pool)).simulateWithdrawLiquidity(_tokenId, 0, previousWj);
            // we first test the negative paths
            vm.expectRevert(abi.encodeWithSignature("MaxSlippageReached()"));
            _pool.withdrawAllLiquidity(_tokenId, msg.sender, minAx + 1, minAy, getValidExpiration());
            vm.expectRevert(abi.encodeWithSignature("MaxSlippageReached()"));
            _pool.withdrawAllLiquidity(_tokenId, msg.sender, minAx, minAy + 1, getValidExpiration());
            // we continue to test
            _pool.withdrawAllLiquidity(_tokenId, msg.sender, minAx, minAy, getValidExpiration());
            (wj, ) = lpToken.getLPToken(_tokenId);
            assertEq(
                uint(previousWj.convertpackedFloatToWAD()),
                remainderAmount + uint(wj.convertpackedFloatToWAD()),
                "previous wj == wj + withdrawAmount"
            );
        }
        (wj, ) = lpToken.getLPToken(_tokenId);
        assertEq(uint(wj.convertpackedFloatToWAD()), 0, "wj should be 0 after all withdraws");
    }

    function testLiquidity_Pool_WInactiveZero() public {
        uint wInactive = 0;
        _deployPool(X_TOKEN_MAX_SUPPLY, wInactive);
        _wInactiveWithdrawHelper(0, _pool.inactiveLpId(), 1);
    }

    function testLiquidity_Pool_WithdrawAllLiquidityOneWithdraw() public {
        uint wInactive = 0;
        _deployPool(X_TOKEN_MAX_SUPPLY, wInactive);
        assertTrue(_pool.owner() != address(0));
        _wInactiveWithdrawHelper(X_TOKEN_MAX_SUPPLY, _pool.activeLpId(), 1);
        assertEq(_pool.paused(), true);
        assertEq(_pool.owner(), address(0));
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", admin));
        _pool.enableSwaps(true);
    }

    function testLiquidity_Pool_WithdrawAllLiquidityMultipleWithdraw() public {
        uint wInactive = 0;
        _deployPool(X_TOKEN_MAX_SUPPLY, wInactive);
        assertTrue(_pool.owner() != address(0));
        _wInactiveWithdrawHelper(X_TOKEN_MAX_SUPPLY, _pool.activeLpId(), 7);
        assertEq(_pool.paused(), true);
        assertEq(_pool.owner(), address(0));
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", admin));
        _pool.enableSwaps(true);
    }

    function testLiquidity_Pool_WInactiveHalfMaxOneWithdraw() public {
        uint wInactive = X_TOKEN_MAX_SUPPLY / 2;
        _deployPool(X_TOKEN_MAX_SUPPLY, wInactive);
        _wInactiveWithdrawHelper(wInactive, _pool.inactiveLpId(), 1);
    }

    function testLiquidity_Pool_WInactiveMaxOneWithdraw() public {
        uint wInactive = X_TOKEN_MAX_SUPPLY - X_TOKEN_MAX_SUPPLY / 100; // max - 1%
        _deployPool(X_TOKEN_MAX_SUPPLY, wInactive);
        uint inactiveId = _pool.inactiveLpId();
        _wInactiveWithdrawHelper(wInactive, inactiveId, 1);
    }

    function testLiquidity_Pool_WInactiveHalfMaxMulitpleWithdraw() public {
        uint wInactive = X_TOKEN_MAX_SUPPLY / 2;
        _deployPool(X_TOKEN_MAX_SUPPLY, wInactive);
        uint inactiveId = _pool.inactiveLpId();
        _wInactiveWithdrawHelper(wInactive, inactiveId, 7);
    }

    function testLiquidity_Pool_WInactiveMaxMultipleWithdraw() public {
        uint wInactive = X_TOKEN_MAX_SUPPLY - X_TOKEN_MAX_SUPPLY / 100; // max - 1%
        _deployPool(X_TOKEN_MAX_SUPPLY, wInactive);
        uint inactiveId = _pool.inactiveLpId();
        _wInactiveWithdrawHelper(wInactive, inactiveId, 7);
    }

    function testLiquidity_Pool_MaxMaxXWInactiveAtLimit() public {
        uint maxSupply = MAX_SUPPLY;
        uint wInactive = maxSupply - 1e27;
        _deployPool(maxSupply, wInactive);
    }

    function testLiquidity_Pool_MidMaxXWInactiveAtLimit() public {
        uint maxSupply = 1e24;
        uint wInactive = maxSupply - 1e22;
        _deployPool(maxSupply, wInactive);
    }

    function testLiquidity_Pool_LowMaxXWInactiveAtLimit() public {
        uint maxSupply = 1e21;
        uint wInactive = 1e21 - 1e19; // max - 1%
        _deployPool(maxSupply, wInactive);
    }

    function testLiquidity_Pool_MaxMaxXWInactiveOverLimit() public {
        uint maxSupply = MAX_SUPPLY;
        uint wInactive = maxSupply - 1e27 + 1;
        string memory revertMessage = "InactiveLiquidityExceedsLimit()";
        _deployPool(maxSupply, wInactive, revertMessage);
    }

    function testLiquidity_Pool_MidMaxXWInactiveOverLimit() public {
        console2.log("testLiquidity_Pool_MidMaxXWInactiveOverLimit ");
        uint maxSupply = 1e24;
        uint wInactive = maxSupply - 1e22 + 1; // max - 1%
        string memory revertMessage = "InactiveLiquidityExceedsLimit()";
        _deployPool(maxSupply, wInactive, revertMessage);
    }

    function testLiquidity_Pool_LowMaxXWInactiveOverLimit() public {
        uint maxSupply = 1e21;
        uint wInactive = maxSupply - 1e19 + 1; // max - 1%
        string memory revertMessage = "InactiveLiquidityExceedsLimit()";
        _deployPool(maxSupply, wInactive, revertMessage);
    }

    function checkWithdrawRatio() internal {
        uint inactiveId = _pool.inactiveLpId();
        uint activeId = _pool.activeLpId();

        vm.expectRevert(abi.encodeWithSignature("InactiveLiquidityExceedsLimit()"));
        _pool.withdrawPartialLiquidity(activeId, 1, msg.sender, 0, 0, getValidExpiration());

        _pool.withdrawPartialLiquidity(inactiveId, 1, msg.sender, 0, 0, getValidExpiration());

        vm.expectRevert(abi.encodeWithSignature("InactiveLiquidityExceedsLimit()"));
        _pool.withdrawPartialLiquidity(activeId, 1, msg.sender, 0, 0, getValidExpiration());

        _pool.withdrawPartialLiquidity(inactiveId, 99, msg.sender, 0, 0, getValidExpiration());

        _pool.withdrawPartialLiquidity(activeId, 1, msg.sender, 0, 0, getValidExpiration());
    }

    function testLiquidity_Pool_MaxMaxXCannotWithdrawInactiveBeyondLimit() public {
        uint maxSupply = MAX_SUPPLY;
        uint wInactive = maxSupply - 1e27;
        _deployPool(maxSupply, wInactive);
        checkWithdrawRatio();
    }

    function testLiquidity_Pool_MidMaxXCannotWithdrawInactiveBeyondLimit() public {
        uint maxSupply = 1e24;
        uint wInactive = maxSupply - 1e22;
        _deployPool(maxSupply, wInactive);
        checkWithdrawRatio();
    }

    function testLiquidity_Pool_LowMaxXCannotWithdrawInactiveBeyondLimit() public {
        uint maxSupply = 1e21;
        uint wInactive = 1e21 - 1e19; // max - 1%
        _deployPool(maxSupply, wInactive);
        checkWithdrawRatio();
    }
}

/**
 * @title Test Pool Stable Coin functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolDeploymentStableCoinTest is ALTBCPoolDeployment {
    function setUp() public endWithStopPrank {
        _setupPool(true);
    }
}

/**
 * @title Test Pool WETH functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolDeploymentWETHTest is ALTBCPoolDeployment {
    function setUp() public endWithStopPrank {
        _setupPool(false);
    }
}
