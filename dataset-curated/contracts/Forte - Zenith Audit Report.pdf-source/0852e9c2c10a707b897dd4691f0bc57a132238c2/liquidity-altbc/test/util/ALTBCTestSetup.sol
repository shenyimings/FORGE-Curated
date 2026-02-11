// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ALTBCFactory} from "src/factory/ALTBCFactory.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {ALTBCPool, FeeInfo, IERC20} from "src/amm/ALTBCPool.sol";

import {packedFloat, MathLibs} from "liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {TestCommonSetupAbs} from "liquidity-base/test/amm/common/PoolCommon.t.u.sol";
import {TBCInputOption, PoolBase} from "liquidity-base/test/util/TestCommonSetupAbs.sol";

contract ALTBCTestSetup is TestCommonSetupAbs {
    using MathLibs for packedFloat;
    using ALTBCEquations for packedFloat;

    ALTBCInput altbcInput = ALTBCInput(1e18, 0, 1e14, 1e18, 1e24); /// lowerPrice: 1e18, V: 1e14, xMin: 1e18, C: 1e24
    ALTBCInput altbcInputFork = ALTBCInput(1e18, 0, 1e9, 1e18, 1e18);
    ALTBCInput altbcInputPrecision = ALTBCInput(1e17, 0, 1e18, 1e18, 1e18);

    ALTBCFactory altbcFactory;
    ALTBCDef altbc;

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
        poolRet = PoolBase(altbcFactory.createPool(_xTokenAddress, _yTokenAddress, _fee, input, _xAdd, "Name", "SYMBOL"));
    }

    // TODO split this off into a helper contract for use here as well as ALTBCPoolWithLPToken
    function _tokenDistributionAndApproveHelper(address _poolAddress, address user, uint256 xAmount, uint256 yAmount) internal {
        vm.startPrank(admin);
        xToken.transfer(address(user), xAmount);
        yToken.transfer(address(user), yAmount);
        vm.stopPrank();
        vm.startPrank(address(user));
        xToken.approve(address(_poolAddress), xAmount);
        yToken.approve(address(_poolAddress), yAmount);
    }
}
