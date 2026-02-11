// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {ALTBCFactory} from "src/factory/ALTBCFactory.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {ALTBCPool, FeeInfo, IERC20} from "src/amm/ALTBCPool.sol";

import {packedFloat, MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {TestCommonSetupAbs} from "liquidity-base/test/amm/common/PoolCommon.t.u.sol";
import {TBCInputOption, PoolBase} from "liquidity-base/test/util/TestCommonSetupAbs.sol";
import {IERC20Metadata} from "lib/liquidity-base/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract ALTBCTestSetup is TestCommonSetupAbs {
    using MathLibs for packedFloat;
    using ALTBCEquations for packedFloat;
    using MathLibs for uint256;
    using MathLibs for int256;
    using ALTBCEquations for ALTBCDef;

    ALTBCInput altbcInput = ALTBCInput(1e18, 1e14, 1e18, 1e24); /// lowerPrice: 1e18, V: 1e14, xMin: 1e18, C: 1e24
    ALTBCInput altbcInputFork = ALTBCInput(1e18, 1e9, 1e18, 1e18);
    ALTBCInput altbcInputPrecision = ALTBCInput(1e17, 1e18, 1e18, 1e18);
    ALTBCInput altbcInputStress =
        ALTBCInput(
            uint(int(1).toPackedFloat(-1).convertpackedFloatToWAD()), // Lower price
            uint(int(2).toPackedFloat(0).convertpackedFloatToWAD()), // V
            uint(int(100).toPackedFloat(0).convertpackedFloatToWAD()), // xMin
            uint(int(120).toPackedFloat(0).convertpackedFloatToWAD()) // C
        );
    uint _wInactive = 1;
    uint deployerActivePosition = 2;

    ALTBCFactory altbcFactory;
    ALTBCDef altbc;
    ALTBCDef curve;

    uint256 wj_input = 1_000; // Arbitrary value for qWn, used to update amount of liquidity of a position
    uint256 rj_input = 100; // Arbitrary value for last_revenue_claim, used to update last_revenue_claim of a position
    uint256 w0 = 1e22; // Arbitrary value for initial liquidity deposit by pool deployer
    uint256 initial_r = 0;
    uint256 fee = 0;
    FeeInfo fees = FeeInfo(10, 5, address(1337));

    function _deployFactory() internal override startAsAdmin endWithStopPrank {
        altbcFactory = new ALTBCFactory(type(ALTBCPool).creationCode);
    }

    function _getFactoryAddress() internal view override returns (address) {
        return address(altbcFactory);
    }

    function _getMaxXTokenSupply() internal view override returns (uint256 maxSupply) {
        packedFloat unconverted;
        (, , , , unconverted, , ) = ALTBCPool(address(pool)).tbc();
        maxSupply = uint(unconverted.convertpackedFloatToWAD());
    }

    function _getInput(TBCInputOption _inputOption) internal view returns (ALTBCInput storage) {
        if (_inputOption == TBCInputOption.BASE) {
            return altbcInput;
        } else if (_inputOption == TBCInputOption.FORK) {
            return altbcInputFork;
        } else if (_inputOption == TBCInputOption.PRECISION) {
            return altbcInputPrecision;
        } else if (_inputOption == TBCInputOption.STRESS) {
            return altbcInputStress;
        } else {
            revert("invalid TBCInputOption");
        }
    }

    function _deployPool(
        address _xTokenAddress,
        address _yTokenAddress,
        uint16 _fee,
        uint _xAdd,
        TBCInputOption _inputOption
    ) internal override returns (PoolBase poolRet) {
        ALTBCInput storage input = _getInput(_inputOption);
        vm.startPrank(admin);
        poolRet = PoolBase(altbcFactory.createPool(_xTokenAddress, _yTokenAddress, _fee, input, _xAdd, 1));
    }

    function _deployStressTestPool(
        address _xTokenAddress,
        address _yTokenAddress,
        uint16 _fee,
        uint _xAdd,
        TBCInputOption _inputOption
    ) internal override returns (PoolBase poolRet) {
        ALTBCInput storage input = _getInput(_inputOption);
        vm.startPrank(admin);
        poolRet = PoolBase(
            altbcFactory.createPool(
                _xTokenAddress,
                _yTokenAddress,
                _fee,
                input,
                _xAdd,
                uint(int(90000000000000000000000000000000000000).toPackedFloat(-35).convertpackedFloatToWAD())
            )
        );
    }

    function _tokenDistributionAndApproveHelper(address _poolAddress, address user, uint256 xAmount, uint256 yAmount) internal {
        vm.startPrank(admin);
        xToken.transfer(address(user), xAmount);
        yToken.transfer(address(user), yAmount);
        vm.stopPrank();
        vm.startPrank(address(user));
        xToken.approve(address(_poolAddress), xAmount);
        yToken.approve(address(_poolAddress), yAmount);
    }

    function _getYTokenLiquidity(address _pool) internal override returns (uint yLiquidity) {
        (curve.b, curve.c, curve.C, curve.xMin, curve.xMax, curve.V, curve.Zn) = ALTBCPool(_pool).tbc();
        packedFloat _x = ALTBCPool(_pool).x();
        yLiquidity = uint((curve.calculateDn(_x).sub(curve.calculateL(_x))).convertpackedFloatToWAD());
        uint yDecimals = IERC20Metadata(ALTBCPool(_pool).yToken()).decimals();
        uint xDecimals = 18;
        if (yDecimals < xDecimals) yLiquidity /= 10 ** (xDecimals - yDecimals);
    }
}
