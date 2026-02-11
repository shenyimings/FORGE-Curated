// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {FactoryBase} from "src/factory/FactoryBase.sol";
import {AllowList} from "src/allowList/AllowList.sol";
import {GenericERC20} from "src/example/ERC20/GenericERC20.sol";
import {GenericERC20FixedSupply} from "src/example/ERC20/GenericERC20FixedSupply.sol";
import {TwentyTwoDecimalERC20} from "src/example/ERC20/TwentyTwoDecimalERC20.sol";
import {SixDecimalERC20} from "src/example/ERC20/SixDecimalERC20.sol";
import {FeeOnTransferERC20} from "src/example/ERC20/FeeOnTransferERC20.sol";
import {TwentyTwoDecimalERC20} from "src/example/ERC20/TwentyTwoDecimalERC20.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {TestCommonSetupAbs, TBCInputOption} from "test/util/TestCommonSetupAbs.sol";
import {LPToken} from "src/common/LPToken.sol";
import "forge-std/console2.sol";

/**
 * @title Test Common Foundry
 * @dev This contract is an abstract template to be reused by all the Foundry tests. NOTE: function prefixes and their usages are as follows:
 * setup = set to proper user, deploy contracts, set global variables, reset user
 * create = set to proper user, deploy contracts, reset user, return the contract
 * _create = deploy contract, return the contract
 */
abstract contract TestCommonSetup is TestCommonSetupAbs {
    function _setupCollateralToken() internal {
        _yToken = IERC20(pool.yToken());
        fullToken = address(_yToken) == address(stableCoin) ? STABLECOIN_DEC : ERC20_DECIMALS;
    }
    function _setUpTokens(uint256 _xTokenSupply) internal startAsAdmin endWithStopPrank {
        xToken = new GenericERC20FixedSupply("x token", "GAME", _xTokenSupply * 3);
        yToken = new GenericERC20("collateral token", "COLL");
        stableCoin = new SixDecimalERC20("stable coin", "USDX");
        highDecimalCoin = new TwentyTwoDecimalERC20("high deciaml coin", "HDEX");
        fotCoin = new FeeOnTransferERC20("FOT Token", "FOT", transferFee);
    }

    function _loadAdminAndAlice() internal startAsAdmin endWithStopPrank {
        GenericERC20(address(yToken)).mint(admin, 1e12 * ERC20_DECIMALS);
        GenericERC20(address(yToken)).mint(alice, 1e12 * ERC20_DECIMALS);
        stableCoin.mint(alice, 1e12 * STABLECOIN_DEC);
        stableCoin.mint(admin, 1e12 * STABLECOIN_DEC);
        fotCoin.mint(admin, 1e20 * ERC20_DECIMALS);
    }

    function _deployAllowLists() internal startAsAdmin endWithStopPrank {
        yTokenAllowList = new AllowList();
        deployerAllowList = new AllowList();
    }

    function _deployAndSetLPToken() internal startAsAdmin endWithStopPrank {
        lpToken = new LPToken("LPToken", "LPT");
    }

    function _deployLPToken() internal returns (LPToken LPTokenAddress) {
        vm.startPrank(admin);
        LPTokenAddress = new LPToken("LPToken", "LPT");
    }

    function _setupAllowLists() internal startAsAdmin endWithStopPrank {
        yTokenAllowList.addToAllowList(address(yToken));
        yTokenAllowList.addToAllowList(address(stableCoin));
        yTokenAllowList.addToAllowList(address(highDecimalCoin));
        deployerAllowList.addToAllowList(address(admin));
    }

    function _setupFactory(address factory) internal startAsAdmin endWithStopPrank {
        FactoryBase(factory).setDeployerAllowList(address(deployerAllowList));
        FactoryBase(factory).setYTokenAllowList(address(yTokenAllowList));
        FactoryBase(factory).proposeProtocolFeeCollector(address(0xb0b));
        vm.startPrank(address(0xb0b));
        FactoryBase(factory).confirmProtocolFeeCollector();
    }

    function _approvePool(PoolBase poolRet, bool usdt) internal startAsAdmin endWithStopPrank {
        IERC20 _xToken = IERC20(poolRet.xToken());
        IERC20 _yToken = IERC20(poolRet.yToken());
        _xToken.approve(address(poolRet), X_TOKEN_MAX_SUPPLY);
        _xToken.approve(_getFactoryAddress(), X_TOKEN_MAX_SUPPLY); // approve factory
        if (!usdt) {
            _yToken.approve(address(poolRet), _yToken.balanceOf(admin));
        }
        vm.startPrank(alice);
        _xToken.approve(address(poolRet), X_TOKEN_MAX_SUPPLY);
        if (!usdt) {
            _yToken.approve(address(poolRet), _yToken.balanceOf(alice));
        }
    }

    function _approveFactory(address _xToken) internal startAsAdmin endWithStopPrank {
        IERC20(_xToken).approve(_getFactoryAddress(), X_TOKEN_MAX_SUPPLY); // approve factory
    }

    function _addInitialLiquidity(PoolBase poolRet, uint _amount) internal startAsAdmin endWithStopPrank {
        PoolBase(address(poolRet)).addXSupply(_amount);
    }

    function _setUpTokensAndFactories(uint _tokenSupply) internal {
        _setUpTokens(_tokenSupply);
        _loadAdminAndAlice();
        _deployFactory();
        _deployAllowLists();
        _setupFactory(_getFactoryAddress());
        _setupAllowLists();
    }

    function _setupPool(bool withStableCoin) internal endWithStopPrank returns (PoolBase poolRet) {
        _setUpTokensAndFactories(X_TOKEN_MAX_SUPPLY);
        _approveFactory(address(xToken));
        address yTokenAddress = withStableCoin ? address(stableCoin) : address(yToken);
        poolRet = _deployPool(address(xToken), yTokenAddress, 30, X_TOKEN_MAX_SUPPLY, TBCInputOption.BASE);
        _approvePool(poolRet, false);
        amountMinBound = 2;
        pool = poolRet;
        _setupCollateralToken();
    }

    function _setupPoolWithFee(bool withStableCoin, uint16 fee) internal endWithStopPrank returns (PoolBase poolRet) {
        poolRet = _setupPoolWithFee(withStableCoin, address(xToken), fee);
    }

    function _setupPoolWithFee(
        bool withStableCoin,
        address _xTokenAddress,
        uint16 fee
    ) internal endWithStopPrank returns (PoolBase poolRet) {
        address yTokenAddress = withStableCoin ? address(stableCoin) : address(yToken);
        poolRet = _deployPool(_xTokenAddress, yTokenAddress, fee, X_TOKEN_MAX_SUPPLY, TBCInputOption.BASE);
        _approvePool(poolRet, false);
    }

    function _setupPoolForkTest(
        address owner,
        address _yTokenAddress,
        uint16 fee,
        bool usdt
    ) internal endWithStopPrank returns (PoolBase poolRet) {
        _deployFactory();
        _deployAllowLists();
        _setupFactory(_getFactoryAddress());
        _setupAllowLists();

        GenericERC20FixedSupply xTokenWithFee = new GenericERC20FixedSupply("Fee token", "FEE", 10e3 * ERC20_DECIMALS);
        _approveFactory(address(xTokenWithFee));
        poolRet = PoolBase(_deployPool(address(xTokenWithFee), _yTokenAddress, 0, 10e3 * ERC20_DECIMALS, TBCInputOption.FORK));
        _deployAndSetLPToken();
        _approvePool(poolRet, usdt);
        // _addInitialLiquidity(poolRet, 10e3 * ERC20_DECIMALS);

        (owner, fee);
    }

    function _setupStressTestPool(bool withStableCoin) internal endWithStopPrank returns (PoolBase poolRet) {
        // the token supply is the same value used in the stress test simulation and must match
        uint256 maxX = 10e3 * ERC20_DECIMALS;
        _setUpTokensAndFactories(maxX);
        _approveFactory(address(xToken));
        address yTokenAddress = withStableCoin ? address(stableCoin) : address(yToken);
        // the pool config values are the same config values used in the stress test simulation and must match
        /// fee: 0.0%, supply: 10K tokens, y-intersect: 10, minPrice: 1, maxPrice: 100
        poolRet = _deployPool(address(xToken), yTokenAddress, 0, maxX, TBCInputOption.FORK);
        _approvePool(poolRet, false);
        // _addInitialLiquidity(poolRet, 10e3 * ERC20_DECIMALS);
    }

    function _setupPrecisionPools(
        uint256 maxSupply,
        uint16 fee
    ) internal endWithStopPrank returns (PoolBase wadPool, PoolBase sixDecimalPool) {
        _setUpTokensAndFactories(maxSupply);
        _approveFactory(address(xToken));
        wadPool = _deployPool(address(xToken), address(yToken), fee, maxSupply, TBCInputOption.PRECISION);
        _approvePool(wadPool, false);

        _setUpTokens(maxSupply);
        _approveFactory(address(xToken));
        vm.startPrank(admin);
        yTokenAllowList.addToAllowList(address(stableCoin));

        sixDecimalPool = _deployPool(address(xToken), address(stableCoin), fee, maxSupply, TBCInputOption.PRECISION);
        _approveFactory(address(xToken));
        _loadAdminAndAlice();
        _approvePool(sixDecimalPool, false);
    }

    function _setupPoolPartialFunding(bool withStableCoin) internal endWithStopPrank returns (PoolBase poolRet) {
        _setUpTokensAndFactories(X_TOKEN_MAX_SUPPLY);
        _approveFactory(address(xToken));
        address yTokenAddress = withStableCoin ? address(stableCoin) : address(yToken);
        poolRet = _deployPool(address(xToken), yTokenAddress, 30, X_TOKEN_MAX_SUPPLY, TBCInputOption.BASE);
        vm.startPrank(admin);
        _approvePool(poolRet, false);
        // _addInitialLiquidity(poolRet, X_TOKEN_MAX_SUPPLY / 2);
    }

    function _setupFOTPool(bool withStableCoin) internal endWithStopPrank returns (PoolBase poolRet) {
        _setUpTokensAndFactories(X_TOKEN_MAX_SUPPLY);
        _approveFactory(address(fotCoin));
        address yTokenAddress = withStableCoin ? address(stableCoin) : address(yToken);
        poolRet = _deployPool(address(fotCoin), yTokenAddress, 30, X_TOKEN_MAX_SUPPLY, TBCInputOption.BASE);
        _approvePool(poolRet, false);
        pool = poolRet;
        _setupCollateralToken();
    }

    function _setupParallelTokensAndPoolsForFees()
        internal
        startAsAdmin
        returns (GenericERC20FixedSupply xTokenWithFee, GenericERC20FixedSupply xTokenWoutFee, PoolBase poolWFee, PoolBase poolWOutFee)
    {
        bool withStableCoin = pool.yToken() == address(stableCoin);
        xTokenWithFee = new GenericERC20FixedSupply("Fee token", "FEE", X_TOKEN_MAX_SUPPLY);
        xTokenWoutFee = new GenericERC20FixedSupply("No Fee token", "NOFEE", X_TOKEN_MAX_SUPPLY);
        vm.stopPrank();
        _approveFactory(address(xTokenWithFee));
        _approveFactory(address(xTokenWoutFee));
        poolWFee = _setupPoolWithFee(withStableCoin, address(xTokenWithFee), 30);
        poolWOutFee = _setupPoolWithFee(withStableCoin, address(xTokenWoutFee), 0);
    }

    function getAmountPlusFee(uint256 amount) internal view returns (uint256) {
        return amount / ((totalBasisPoints - transferFee) / transferFee) + amount;
    }

    function getAmountSubFee(uint256 amount) internal view returns (uint256) {
        if (transferFee > 0) return amount - ((amount * transferFee) / totalBasisPoints);
        else return amount;
    }

    /**
     * @dev Convenience function to start prank and set protocol fee on a pool
     * @param _pool pool to set fee on
     */
    function _activateProtocolFeesInPool(PoolBase _pool) internal endWithStopPrank {
        vm.startPrank(bob);
        _pool.setProtocolFee(5);
    }
}
