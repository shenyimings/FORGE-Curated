// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";
import "forge-std/console2.sol";
import {Float128} from "lib/liquidity-base/lib/float128/src/Float128.sol";
import {ALTBCPool, ALTBCEquations, PoolBase} from "src/amm/ALTBCPool.sol";
import {MathLibs, packedFloat} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {TestCommonSetup} from "lib/liquidity-base/test/util/TestCommonSetup.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract ALTBCPoolStressTest is TestCommonSetup, ALTBCTestSetup {
    using MathLibs for packedFloat;
    using MathLibs for int256;
    using ALTBCEquations for ALTBCDef;
    using ALTBCEquations for packedFloat;

    using stdJson for string;

    string constant PATH = "test/amm/stress/tradeData/simTrades";
    int constant MAX_ABSOLUTE_ERROR_MAN = 1;
    int constant MAX_ABSOLUTE_ERROR_EXP = -22;
    int constant C_MAX_ABSOLUTE_ERROR_EXP = -22;
    int constant WJSTABLECOIN_MAX_ABSOLUTE_ERROR_EXP = -6;

    // Holding 32 digits of precision on the 18 decimal Y token pool
    uint256 comparisonWETH = 32;
    // Holding 26 digits of precision on the 6 decimal Y token pool
    uint256 comparisonStableCoin = 24;

    packedFloat maxAbsoluteError = int(1).toPackedFloat(-int(18)); // max error of 1 wei

    bool withStableCoin;

    ALTBCDef solState;
    ALTBCDef pyState;

    bytes data;
    string fileEnd;

    uint256 amountIn;

    int256 solM;
    int256 solE;
    int256 pyM;
    int256 pyE;

    uint256 pyMan;
    int256 pyExp;
    packedFloat pyFloat;
    packedFloat solFloat;

    uint256 pyWad;
    uint256 solWad;
    int256 solMan;
    int256 solExp;

    function _setUp(bool _withStableCoin) internal endWithStopPrank {
        pool = _setupStressTestPool(_withStableCoin);
        _yToken = IERC20(pool.yToken());
        fullToken = address(_yToken) == address(stableCoin) ? STABLECOIN_DEC : ERC20_DECIMALS;
        withStableCoin = _withStableCoin;
        fileEnd = _withStableCoin ? "StableCoin.json" : "WETH.json";
    }

    // Due to memory constraints in the EVM, we need to parse the JSON file in steps
    function _parseInidividualStep(string memory step, string memory filePath) internal returns (bytes memory) {
        string[] memory ffiInput = new string[](4);
        ffiInput[0] = "python3";
        ffiInput[1] = "./script/python/util/parse_stress_test.py";
        ffiInput[2] = filePath;
        ffiInput[3] = step;
        bytes memory result = vm.ffi(ffiInput);
        return result;
    }

    function _logErrors(uint256 _i) internal {
        checkPrecision(solState.b, pyState.b, _i, "bn");
        checkPrecision(solState.c, pyState.c, _i, "cn");
        checkPrecision(solState.C, pyState.C, MAX_ABSOLUTE_ERROR_MAN, C_MAX_ABSOLUTE_ERROR_EXP, _i, "C");
        checkPrecision(solState.xMin, pyState.xMin, _i, "xMin");
        checkPrecision(solState.xMax, pyState.xMax, _i, "xMax");
        checkPrecision(solState.V, pyState.V, _i, "V");
        checkPrecision(solState.Zn, pyState.Zn, _i, "Zn");

        // CHECKING X
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.x.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.x.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        solFloat = PoolBase(address(pool)).x();

        checkPrecision(solFloat, pyFloat, _i, "x");

        // CHECKING W
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.W.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.W.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        pyWad = uint(pyFloat.convertpackedFloatToWAD());
        solWad = pool.w();
        if (!areWithinTolerance(solWad, pyWad, 1, withStableCoin ? comparisonStableCoin : comparisonWETH)) {
            (solMan, solExp) = solFloat.decode();
            console2.log("pyWad", pyWad);
            console2.log("solWad", solWad);

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("W failed after ", vm.toString(_i)));
            console2.log("-------------------------");
            revert();
        }

        // CHECKING W_INACTIVE
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.W_I.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.W_I.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        pyWad = uint(pyFloat.convertpackedFloatToWAD());
        (packedFloat _wIanctive, ) = lpToken.getLPToken(pool.inactiveLpId());
        checkPrecision(_wIanctive, pyFloat, _i, "wInactive");

        // CHECKING H
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.h.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.h.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        solFloat = ALTBCPool(address(pool)).retrieveH();
        checkPrecision(solFloat, pyFloat, _i, "H");

        // CHECKING L
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.L.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.L.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        solFloat = solState.calculateL(PoolBase(address(pool)).x());
        checkPrecision(solFloat, pyFloat, _i, "L");

        // CHECKING PRICE
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.p.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.p.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        solWad = PoolBase(address(pool)).spotPrice();
        pyWad = uint(pyFloat.convertpackedFloatToSpecificDecimals(withStableCoin ? int256(6) : int256(18)));
        if (!areWithinTolerance(solWad, pyWad, 2, 18)) {
            (solMan, solExp) = solFloat.decode();
            console2.log("solWad_P", solWad);
            console2.log("pyWad_P", pyWad);

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("Price failed after ", vm.toString(_i)));
            console2.log("-------------------------");
            revert();
        }

        // CHECKING D
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.D.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.D.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        solFloat = solState.calculateDn(PoolBase(address(pool)).x());
        checkPrecision(solFloat, pyFloat, _i, "D");

        // CHECK PSI CLAIMABLE - PROTOCOL FEE
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.PSI.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.PSI.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        pyWad = withStableCoin
            ? uint(pyFloat.convertpackedFloatToSpecificDecimals(6))
            : uint(pyFloat.convertpackedFloatToSpecificDecimals(18));
        (, , , , solWad) = PoolBase(address(pool)).getFeeInfo();

        if (!areWithinTolerance(solWad, pyWad, 1, withStableCoin ? comparisonStableCoin : comparisonWETH)) {
            console2.log("pyWadPsiClaimable", pyWad);
            console2.log("solWadPsiClaimable", solWad);

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("Psi Claimable failed after ", vm.toString(_i)));
            console2.log("-------------------------");
            revert();
        }
    }

    function _checkState(uint256 _i) internal {
        data = _parseInidividualStep(vm.toString(_i), string.concat(PATH, fileEnd));
        (solState.b, solState.c, solState.C, solState.xMin, solState.xMax, solState.V, solState.Zn) = ALTBCPool(address(pool)).tbc();

        pyState.b = int(vm.parseJsonUint(string(data), ".resultant_state.b.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".resultant_state.b.exponent")
        );
        pyState.c = int(vm.parseJsonUint(string(data), ".resultant_state.c.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".resultant_state.c.exponent")
        );
        pyState.C = int(vm.parseJsonUint(string(data), ".resultant_state.C.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".resultant_state.C.exponent")
        );
        pyState.xMin = int(vm.parseJsonUint(string(data), ".resultant_state.x_min.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".resultant_state.x_min.exponent")
        );
        pyState.xMax = int(vm.parseJsonUint(string(data), ".resultant_state.x_max.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".resultant_state.x_max.exponent")
        );
        pyState.V = int(vm.parseJsonUint(string(data), ".resultant_state.V.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".resultant_state.V.exponent")
        );
        console2.log("Z exponent", vm.parseJsonInt(string(data), ".resultant_state.Z.exponent"));
        pyState.Zn = int(vm.parseJsonUint(string(data), ".resultant_state.Z.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".resultant_state.Z.exponent")
        );
        _logErrors(_i);
    }

    function _checkNFTStateInitial(uint256 _i) internal {
        (packedFloat solWj, packedFloat solRj) = lpToken.getLPToken(1);
        packedFloat pyWj = int(vm.parseJsonUint(string(data), ".output.owner_NFT_inactive.NFT.amount.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".output.owner_NFT_inactive.NFT.amount.exponent")
        );
        packedFloat pyRj = int(vm.parseJsonUint(string(data), ".output.owner_NFT_inactive.NFT.last_revenue_claim.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".output.owner_NFT_inactive.NFT.last_revenue_claim.exponent")
        );

        if (!solWj.eq(pyWj)) {
            (solMan, solExp) = solWj.decode();
            pyMan = vm.parseJsonUint(string(data), ".output.owner_NFT_inactive.NFT.amount.mantissa");
            pyExp = vm.parseJsonInt(string(data), ".output.owner_NFT_inactive.NFT.amount.exponent");
            console2.log("solManWj_inactive", solMan);
            console2.log("solExpWj_inactive", solExp);
            console2.log("pyManWj_inactive", pyMan);
            console2.log("pyExpWj_inactive", pyExp);

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("Wj_inactive failed after ", vm.toString(_i)));
            console2.log("-------------------------");
        }

        if (!solRj.eq(pyRj)) {
            (solMan, solExp) = solRj.decode();
            pyMan = vm.parseJsonUint(string(data), ".output.owner_NFT_inactive.NFT.last_revenue_claim.mantissa");
            pyExp = vm.parseJsonInt(string(data), ".output.owner_NFT_inactive.NFT.last_revenue_claim.exponent");
            console2.log("solManRj_inactive", solMan);
            console2.log("solExpRj_inactive", solExp);
            console2.log("pyManRj_inactive", pyMan);
            console2.log("pyExpRj_inactive", pyExp);

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("Rj_inactive failed after ", vm.toString(_i)));
            console2.log("-------------------------");
        }

        (solWj, solRj) = lpToken.getLPToken(2);
        pyWj = int(vm.parseJsonUint(string(data), ".output.owner_NFT_active.NFT.amount.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".output.owner_NFT_active.NFT.amount.exponent")
        );
        pyRj = int(vm.parseJsonUint(string(data), ".output.owner_NFT_active.NFT.last_revenue_claim.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".output.owner_NFT_active.NFT.last_revenue_claim.exponent")
        );
        if (!solWj.eq(pyWj)) {
            (solMan, solExp) = solWj.decode();
            pyMan = vm.parseJsonUint(string(data), ".output.owner_NFT_active.NFT.amount.mantissa");
            pyExp = vm.parseJsonInt(string(data), ".output.owner_NFT_active.NFT.amount.exponent");
            console2.log("solManWj_active", solMan);
            console2.log("solExpWj_active", solExp);
            console2.log("pyManWj_active", pyMan);
            console2.log("pyExpWj_active", pyExp);
            console2.log("pyFloatWj_active", packedFloat.unwrap(pyFloat));
            console2.log("solFloatWj_active", packedFloat.unwrap(solFloat));

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("Wj_Active failed after ", vm.toString(_i)));
            console2.log("-------------------------");
        }

        if (!solRj.eq(pyRj)) {
            (solMan, solExp) = solRj.decode();
            pyMan = vm.parseJsonUint(string(data), ".output.owner_NFT_active.NFT.last_revenue_claim.mantissa");
            pyExp = vm.parseJsonInt(string(data), ".output.owner_NFT_active.NFT.last_revenue_claim.exponent");
            console2.log("solManRj_active", solMan);
            console2.log("solExpRj_active", solExp);
            console2.log("pyManRj_active", pyMan);
            console2.log("pyExpRj_active", pyExp);
            console2.log("pyFloatRj_active", packedFloat.unwrap(pyFloat));
            console2.log("solFloatRj_active", packedFloat.unwrap(solFloat));

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("Rj_Active failed after ", vm.toString(_i)));
            console2.log("-------------------------");
        }
    }

    function _checkNFTStateIn(uint256 tokenId, uint256 _i) internal view {
        (packedFloat solWj, packedFloat solRj) = lpToken.getLPToken(tokenId);
        packedFloat pyWj = int(vm.parseJsonUint(string(data), ".input.info.NFT_in.NFT.amount.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".input.info.NFT_in.NFT.amount.exponent")
        );
        packedFloat pyRj = int(vm.parseJsonUint(string(data), ".input.info.NFT_in.NFT.last_revenue_claim.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".input.info.NFT_in.NFT.last_revenue_claim.exponent")
        );

        withStableCoin
            ? checkPrecision(solWj, pyWj, MAX_ABSOLUTE_ERROR_MAN, WJSTABLECOIN_MAX_ABSOLUTE_ERROR_EXP, _i, "Wj")
            : checkPrecision(solWj, pyWj, _i, "Wj");
        checkPrecision(solRj, pyRj, _i, "Rj");
    }

    function _checkNFTStateOut(uint256 tokenId, uint256 _i) internal view {
        (packedFloat solWj, packedFloat solRj) = lpToken.getLPToken(tokenId);
        packedFloat pyWj = int(vm.parseJsonUint(string(data), ".output.NFT_out.NFT.amount.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".output.NFT_out.NFT.amount.exponent")
        );
        packedFloat pyRj = int(vm.parseJsonUint(string(data), ".output.NFT_out.NFT.last_revenue_claim.mantissa")).toPackedFloat(
            vm.parseJsonInt(string(data), ".output.NFT_out.NFT.last_revenue_claim.exponent")
        );

        withStableCoin
            ? checkPrecision(solWj, pyWj, MAX_ABSOLUTE_ERROR_MAN, WJSTABLECOIN_MAX_ABSOLUTE_ERROR_EXP, _i, "Wj")
            : checkPrecision(solWj, pyWj, _i, "Wj");
        checkPrecision(solRj, pyRj, _i, "Rj");
    }

    function testInitialState() public {
        data = _parseInidividualStep(vm.toString(uint(0)), string.concat(PATH, fileEnd));

        // Currently the owner has the ability of changing the LPFee and ProtocolFee percentages at any time. Is this fine with the math?
        // Moved this to the initial state test as they are effectively constant for this test
        // CHECK PHI PERCENTAGE - LP FEE
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.phi.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.phi.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        pyWad = uint(pyFloat.convertpackedFloatToSpecificDecimals(3));
        (solWad, , , , ) = PoolBase(address(pool)).getFeeInfo();

        if (solWad != pyWad) {
            console2.log("pyWadPhi", pyWad);
            console2.log("solWadPhi", solWad);

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("phi failed after ", vm.toString(uint(0))));
            console2.log("-------------------------");
        }

        // CHECK PSI PERCENTAGE - PROTOCOL FEE. Should setProtocolFee be moved to the factory?
        pyMan = vm.parseJsonUint(string(data), ".resultant_state.psi.mantissa");
        pyExp = vm.parseJsonInt(string(data), ".resultant_state.psi.exponent");
        pyFloat = int(pyMan).toPackedFloat(pyExp);
        pyWad = uint(pyFloat.convertpackedFloatToSpecificDecimals(3));
        (, solWad, , , ) = PoolBase(address(pool)).getFeeInfo();

        if (solWad != pyWad) {
            console2.log("pyWadPsi", pyWad);
            console2.log("solWadPsi", solWad);

            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat("psi failed after ", vm.toString(uint(0))));
            console2.log("-------------------------");
        }

        // Check the initial state is correct
        data = _parseInidividualStep(vm.toString(uint(0)), string.concat(PATH, fileEnd));
        _checkState(0);
        _checkNFTStateInitial(0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testLiquidity_ALTBCPoolUnit_simGeneratedSwapsV2() public startAsAdmin endWithStopPrank {
        uint count = 1000;

        // Check the initial state is correct
        data = _parseInidividualStep(vm.toString(uint(0)), string.concat(PATH, fileEnd));
        _checkState(0);

        // Start count at 1 to skip the initialization step
        for (uint256 i = 1; i < count; ++i) {
            data = _parseInidividualStep(vm.toString(uint(i)), string.concat(PATH, fileEnd));
            if (vm.parseJsonBool(string(data), ".output.tx_success")) {
                if (keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) == keccak256(abi.encodePacked("swap"))) {
                    if (
                        keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.info.token"))) ==
                        keccak256(abi.encodePacked("Y"))
                    ) {
                        amountIn = vm.parseJsonUint(string(data), ".input.info.amount");
                        (uint expected, , ) = pool.simSwap(address(_yToken), amountIn);
                        pool.swap(address(_yToken), amountIn, expected, address(0), 999999999999999999999999999999);
                    } else {
                        amountIn = vm.parseJsonUint(string(data), ".input.info.amount");
                        (uint expected, , ) = pool.simSwap(address(xToken), amountIn);
                        pool.swap(address(xToken), amountIn, expected, address(0), 999999999999999999999999999999);
                    }
                } else {
                    uint256 tokenId = vm.parseJsonUint(string(data), ".input.info.NFT_in.NFT.Id");
                    _checkNFTStateIn(tokenId, i);
                    if (
                        keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) ==
                        keccak256(abi.encodePacked("liquidity_withdrawal"))
                    ) {
                        packedFloat u = int(vm.parseJsonUint(string(data), ".input.info.u")).toPackedFloat(withStableCoin ? -6 : -18);
                        (uint256 Ax, uint256 Ay, , , , , ) = ALTBCPool(address(pool)).simulateWithdrawLiquidity(
                            tokenId,
                            vm.parseJsonUint(string(data), ".input.info.u"),
                            u
                        );
                        ALTBCPool(address(pool)).withdrawPartialLiquidity(
                            tokenId,
                            vm.parseJsonUint(string(data), ".input.info.u"),
                            address(0),
                            Ax,
                            Ay,
                            999999999999999999999999999999
                        );
                    } else if (
                        keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) ==
                        keccak256(abi.encodePacked("extract_revenue"))
                    ) {
                        ALTBCPool(address(pool)).withdrawRevenue(tokenId, vm.parseJsonUint(string(data), ".input.info.Q"), address(admin));
                    } else if (
                        keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) ==
                        keccak256(abi.encodePacked("liquidity_deposit"))
                    ) {
                        (uint256 Ax, uint256 Ay, , , , ) = ALTBCPool(address(pool)).simulateLiquidityDeposit(
                            vm.parseJsonUint(string(data), ".input.info.A_tilde"),
                            vm.parseJsonUint(string(data), ".input.info.B_tilde")
                        );
                        ALTBCPool(address(pool)).depositLiquidity(
                            tokenId,
                            vm.parseJsonUint(string(data), ".input.info.A_tilde"),
                            vm.parseJsonUint(string(data), ".input.info.B_tilde"),
                            Ax,
                            Ay,
                            999999999999999999999999999999
                        );
                    }
                    _checkNFTStateOut(tokenId == 0 ? lpToken.currentTokenId() : tokenId, i);
                }
            } else if (
                keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) == keccak256(abi.encodePacked("swap"))
            ) {
                if (
                    keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.info.token"))) == keccak256(abi.encodePacked("Y"))
                ) {
                    amountIn = vm.parseJsonUint(string(data), ".input.info.amount");
                    // In the case were buying YToken - not supported
                    if (vm.parseJsonBool(string(data), ".input.info.buy")) {} else {}
                } else {
                    amountIn = vm.parseJsonUint(string(data), ".input.info.amount");
                    // In the case were buying XToken - not supported
                    if (vm.parseJsonBool(string(data), ".input.info.buy")) {} else {}
                }
            } else {
                uint256 tokenId = vm.parseJsonUint(string(data), ".input.info.NFT_in.NFT.Id");
                if (
                    keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) ==
                    keccak256(abi.encodePacked("liquidity_withdrawal"))
                ) {
                    vm.expectRevert();
                    ALTBCPool(address(pool)).withdrawPartialLiquidity(
                        tokenId,
                        vm.parseJsonUint(string(data), ".input.info.u"),
                        address(0),
                        0,
                        0,
                        999999999999999999999999999999
                    );
                } else if (
                    keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) ==
                    keccak256(abi.encodePacked("extract_revenue"))
                ) {
                    vm.expectRevert();
                    ALTBCPool(address(pool)).withdrawRevenue(tokenId, vm.parseJsonUint(string(data), ".input.info.Q"), address(admin));
                } else if (
                    keccak256(abi.encodePacked(vm.parseJsonString(string(data), ".input.action"))) ==
                    keccak256(abi.encodePacked("liquidity_deposit"))
                ) {
                    (uint256 Ax, uint256 Ay, , , , ) = ALTBCPool(address(pool)).simulateLiquidityDeposit(
                        vm.parseJsonUint(string(data), ".input.info.A_tilde"),
                        vm.parseJsonUint(string(data), ".input.info.B_tilde")
                    );
                    vm.expectRevert();
                    ALTBCPool(address(pool)).depositLiquidity(
                        tokenId,
                        vm.parseJsonUint(string(data), ".input.info.A_tilde"),
                        vm.parseJsonUint(string(data), ".input.info.B_tilde"),
                        Ax,
                        Ay,
                        999999999999999999999999999999
                    );
                }
            }
            _checkState(i);
            console2.log(i);
        }
    }

    function checkPrecision(packedFloat solVal, packedFloat pyVal, uint _i, string memory _varName) internal view {
        checkPrecision(solVal, pyVal, MAX_ABSOLUTE_ERROR_MAN, MAX_ABSOLUTE_ERROR_EXP, _i, _varName);
    }

    function checkPrecision(
        packedFloat solVal,
        packedFloat pyVal,
        int absErrorMan,
        int absERrorExp,
        uint _i,
        string memory _varName
    ) internal view {
        if (
            !areWithinTolerance(
                solVal,
                pyVal,
                int(uint(1)).toPackedFloat(-int(uint(withStableCoin ? comparisonStableCoin : comparisonWETH)))
            ) && !checkAbosoluteError(solVal, pyVal, absErrorMan.toPackedFloat(absERrorExp))
        ) {
            console2.log("solidity value", uint(solState.C.convertpackedFloatToWAD()));
            console2.log("python value", uint(pyState.C.convertpackedFloatToWAD()));
            withStableCoin ? console2.log("Stable coin fail") : console2.log("WETH fail");
            console2.log(string.concat(_varName, string.concat(" failed after ", vm.toString(_i))));
            console2.log("-------------------------");
            revert();
        }
    }
}

contract ALTBCStressTestStableCoin is ALTBCPoolStressTest {
    function setUp() public endWithStopPrank {
        _setUp(true);
    }
}

contract ALTBCStressTestWETH is ALTBCPoolStressTest {
    function setUp() public endWithStopPrank {
        _setUp(false);
    }
}
