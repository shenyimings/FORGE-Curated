// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// External imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract GetAccruedManagementFeeTest is FeeManagerTest {
    function test_getAccruedManagementFee() public {
        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee

        uint256 totalSupply = 1000;
        leverageToken.mint(address(this), totalSupply);

        feeManager.chargeManagementFee(leverageToken);
        skip(SECONDS_ONE_YEAR / 2);

        uint256 sharesFee = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply);

        assertEq(sharesFee, 50); // half of 10% of 1000 total supply

        feeManager.chargeManagementFee(leverageToken);
        skip(SECONDS_ONE_YEAR / 2);

        sharesFee = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply + sharesFee);
        assertEq(sharesFee, 53); // half of 10% of 1000 + 50, rounded up
    }

    function testFuzz_getAccruedManagementFee_RoundsUp(uint128 totalSupply, uint256 managementFee) public {
        managementFee = bound(managementFee, 1, MAX_MANAGEMENT_FEE);

        _setManagementFee(feeManagerRole, leverageToken, managementFee);

        leverageToken.mint(address(this), totalSupply);

        feeManager.chargeManagementFee(leverageToken);
        skip(SECONDS_ONE_YEAR);

        uint256 sharesFee = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply);

        assertEq(sharesFee, Math.mulDiv(totalSupply, managementFee, MAX_BPS, Math.Rounding.Ceil));
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_getAccruedManagementFee_ZeroDuration(uint128 totalSupply, uint256 managementFee) public {
        managementFee = bound(managementFee, 1, MAX_MANAGEMENT_FEE);

        leverageToken.mint(address(this), totalSupply);

        feeManager.chargeManagementFee(leverageToken);

        _setManagementFee(feeManagerRole, leverageToken, managementFee);

        uint256 shares = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply);

        assertEq(shares, 0);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_getAccruedManagementFee_ZeroManagementFee(uint256 totalSupply, uint120 deltaT) public {
        _setManagementFee(feeManagerRole, leverageToken, 0);

        leverageToken.mint(address(this), totalSupply);

        feeManager.chargeManagementFee(leverageToken);
        skip(deltaT);

        uint256 shares = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply);
        assertEq(shares, 0);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_getAccruedManagementFee_ZeroTotalSupply(uint256 managementFee, uint120 deltaT) public {
        managementFee = bound(managementFee, 1, MAX_MANAGEMENT_FEE);
        deltaT = uint120(bound(deltaT, 1, type(uint120).max));

        feeManager.chargeManagementFee(leverageToken);
        skip(deltaT);

        _setManagementFee(feeManagerRole, leverageToken, managementFee);

        uint256 shares = feeManager.exposed_getAccruedManagementFee(leverageToken, 0);

        assertEq(shares, 0);
    }
}
