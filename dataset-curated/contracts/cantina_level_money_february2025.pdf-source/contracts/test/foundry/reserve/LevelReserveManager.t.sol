// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {Test, console2} from "forge-std/Test.sol";

import {SymbioticReserveManager} from "../../../src/reserve/LevelSymbioticReserveManager.sol";

import "../../../src/interfaces/eigenlayer/IDelegationManager.sol";
import "../../../src/interfaces/eigenlayer/ISignatureUtils.sol";
import "../../../src/reserve/LevelBaseReserveManager.sol";
import "../../../src/yield/BaseYieldManager.sol";
import "../../../src/interfaces/ILevelBaseReserveManager.sol";
import "../../utils/WadRayMath.sol";
import "./ReserveBaseSetup.sol";

contract LevelReserveManagerTest is Test, ReserveBaseSetup {
    SymbioticReserveManager internal symbioticReserveManager;

    address unwhitelistedVaultDepositor;
    uint256 unwhitelistedVaultDepositorPrivateKey;
    address randomUser;
    uint256 randomUserPrivateKey;

    address public constant HOLESKY_SYMBIOTIC_VAULT_CONFIGURATOR =
        0x382e9c6fF81F07A566a8B0A3622dc85c47a891Df;

    address public constant HOLESKY_SYMBIOTIC_VAULT_FACTORY =
        0x18C659a269a7172eF78BBC19Fe47ad2237Be0590;

    uint256 public constant INITIAL_BALANCE = 100e6;
    uint256 public constant ALLOWANCE = 1e27;
    uint256 public constant DEPOSIT_CAP = 1e27;

    function setUp() public override {
        super.setUp();

        (randomUser, randomUserPrivateKey) = makeAddrAndKey("randomUser");

        vm.startPrank(owner);
        symbioticReserveManager = new SymbioticReserveManager(
            IlvlUSD(address(lvlusdToken)),
            stakedlvlUSD,
            address(owner),
            address(owner)
        );
        _setupReserveManager(symbioticReserveManager);

        USDCToken.mint(INITIAL_BALANCE, address(symbioticReserveManager));
        USDTToken.transfer(address(symbioticReserveManager), INITIAL_BALANCE);

        symbioticReserveManager.approveSpender(
            address(USDCToken),
            address(levelMinting),
            ALLOWANCE
        );
        symbioticReserveManager.approveSpender(
            address(USDCToken),
            address(levelMinting),
            ALLOWANCE
        );

        symbioticReserveManager.approveSpender(
            address(lvlusdToken),
            address(stakedlvlUSD),
            ALLOWANCE * 1e18
        );

        stakedlvlUSD.grantRole(
            keccak256("REWARDER_ROLE"),
            address(symbioticReserveManager)
        );
    }

    function testDepositToLevelMinting(uint256 depositAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);

        vm.startPrank(managerAgent);
        symbioticReserveManager.depositToLevelMinting(
            address(USDCToken),
            depositAmount
        );
        assertEq(
            USDCToken.balanceOf(address(levelMinting)),
            depositAmount,
            "Incorrect levelMinting balance."
        );
    }

    function testTransferErc20(uint256 transferAmount) public {
        vm.assume(transferAmount > 0);
        vm.assume(transferAmount <= INITIAL_BALANCE);

        vm.startPrank(owner);

        symbioticReserveManager.setAllowlist(randomUser, true);
        symbioticReserveManager.transferERC20(
            address(USDCToken),
            randomUser,
            transferAmount
        );
        assertEq(
            USDCToken.balanceOf(randomUser),
            transferAmount,
            "Incorrect USDCToken balance."
        );
    }

    function testTransferErc20RevertsIfNotAllowlisted() public {
        vm.startPrank(owner);

        vm.expectRevert();
        symbioticReserveManager.transferERC20(
            address(USDCToken),
            randomUser,
            1
        );
    }

    function testTransferErc20ToFormerlyAllowlisted() public {
        vm.startPrank(owner);

        symbioticReserveManager.setAllowlist(randomUser, true);
        symbioticReserveManager.setAllowlist(randomUser, false);

        vm.expectRevert();
        symbioticReserveManager.transferERC20(
            address(USDCToken),
            randomUser,
            1
        );
    }

    function _depositForYield(
        LevelBaseReserveManager lrm,
        IERC20 token,
        uint amount
    ) public {
        vm.startPrank(managerAgent);
        lrm.depositForYield(address(token), amount);
        vm.stopPrank();
    }

    function _grantRewarderRole(LevelBaseReserveManager lrm) public {
        vm.startPrank(owner);
        stakedlvlUSD.grantRole(keccak256("REWARDER_ROLE"), address(lrm));
        vm.stopPrank();
    }

    function _grantRecovererRole(
        WrappedRebasingERC20 wrapper,
        BaseYieldManager yieldManager
    ) public {
        vm.startPrank(owner);
        wrapper.grantRole(wrapper.RECOVERER_ROLE(), address(yieldManager));
        vm.stopPrank();
    }

    function _grantYieldRecovererRole(
        BaseYieldManager yieldManager,
        LevelBaseReserveManager lrm
    ) public {
        vm.startPrank(owner);
        yieldManager.grantRole(
            yieldManager.YIELD_RECOVERER_ROLE(),
            address(lrm)
        );
        vm.stopPrank();
    }

    function _collectYieldMintlvlUSDAndReward(
        LevelBaseReserveManager lrm,
        MockToken token
    ) public {
        vm.startPrank(managerAgent);
        lrm.rewardStakedlvlUSD(address(token));
        vm.stopPrank();
    }

    function _testCollectYieldAndRewardMultipleTimesReverts(
        LevelBaseReserveManager lrm,
        MockToken token
    ) public {
        vm.expectRevert();
        this._collectYieldAndRewardMultipleTimes(lrm, token);
    }

    function _collectYieldAndRewardMultipleTimes(
        LevelBaseReserveManager lrm,
        MockToken token
    ) external {
        vm.warp(block.timestamp + 9 hours);
        _collectYieldMintlvlUSDAndReward(lrm, token);
        vm.warp(block.timestamp + 9 hours);
        _collectYieldMintlvlUSDAndReward(lrm, token);
    }

    function test__usdc__collectYieldFromYieldManagerMintlvlUSDAndRewardStakedlvlUSD(
        uint depositAmount,
        uint increaseAmountPercent
    ) public {
        vm.assume(100000 < depositAmount);
        vm.assume(depositAmount < 1e15);
        vm.assume(1 < increaseAmountPercent);
        vm.assume(increaseAmountPercent < 100);
        _collectYieldFromYieldManagerMintlvlUSDAndRewardStakedlvlUSD(
            USDCToken,
            aUSDC,
            waUSDC,
            depositAmount,
            increaseAmountPercent
        );
    }

    function test__dai__collectYieldFromYieldManagerMintlvlUSDAndRewardStakedlvlUSD(
        uint depositAmount,
        uint increaseAmountPercent
    ) public {
        vm.assume(100000 < depositAmount);
        vm.assume(depositAmount < 1e27);
        vm.assume(1 < increaseAmountPercent);
        vm.assume(increaseAmountPercent < 100);
        _collectYieldFromYieldManagerMintlvlUSDAndRewardStakedlvlUSD(
            DAIToken,
            aDAI,
            waDAI,
            depositAmount,
            increaseAmountPercent
        );
    }

    function _collectYieldFromYieldManagerMintlvlUSDAndRewardStakedlvlUSD(
        MockToken token,
        MockAToken aToken,
        WrappedRebasingERC20 waToken,
        uint depositAmount,
        uint increaseAmountPercent
    ) public {
        // mint tokens and grant approvals, setting up for test
        vm.startPrank(owner);
        token.mint(DEPOSIT_CAP);
        token.transfer(address(eigenlayerReserveManager), DEPOSIT_CAP);
        aaveYieldManager.approveSpender(
            address(token),
            address(mockAavePool),
            DEPOSIT_CAP
        );
        eigenlayerReserveManager.approveSpender(
            address(token),
            address(aaveYieldManager),
            DEPOSIT_CAP
        );
        vm.stopPrank();

        // deposit collateral into yieldManager to earn yield
        _depositForYield(eigenlayerReserveManager, token, depositAmount);

        // grant roles necessary for collecting and rewarding yield
        _grantRewarderRole(eigenlayerReserveManager);
        _grantRecovererRole(waToken, aaveYieldManager);
        _grantYieldRecovererRole(aaveYieldManager, eigenlayerReserveManager);

        // accrue interest
        aToken.accrueInterest(increaseAmountPercent * 100);

        // deposit amount has increased in value due to interest accrual
        // here, we are basically doing depositAmount * (1e4 + increaseAmountPercent * 100) / 1e4,
        // except we pre-multiply by WadRayMath.RAY to ensure a high level of precision
        // rayMul does a multiplication and divides by 1 RAY to get us back to the expected result
        uint newTotalAmountQuotedInUnderlying = WadRayMath.rayMul(
            (depositAmount *
                WadRayMath.RAY *
                (1e4 + increaseAmountPercent * 100)) / 1e4,
            1
        );

        // Note: aToken balanceOf returns the balance quoted in the underlying asset, and not the aToken
        assertApproxEqRel(
            aToken.balanceOf(address(waToken)),
            newTotalAmountQuotedInUnderlying,
            1e15 // 0.1%
        );

        // collect yield and reward stakedlvlUSD
        uint lvlUSDbalBefore = lvlusdToken.balanceOf(address(stakedlvlUSD));
        _collectYieldMintlvlUSDAndReward(eigenlayerReserveManager, token);
        uint lvlUSDbalAfter = lvlusdToken.balanceOf(address(stakedlvlUSD));

        // check that expected amount of rewards is deposited into stakedlvlUSD
        uint expectedlvlUSDAmount = (newTotalAmountQuotedInUnderlying -
            depositAmount) * 10 ** (18 - ERC20(token).decimals());
        assertEq(lvlUSDbalAfter - lvlUSDbalBefore, expectedlvlUSDAmount);

        // failure case - at this point, further collect yield + reward operations should fail
        _testCollectYieldAndRewardMultipleTimesReverts(
            eigenlayerReserveManager,
            token
        );
    }

    function testLrmTransferAdmin() public {
        vm.startPrank(owner);
        eigenlayerReserveManager.transferAdmin(newOwner);
        assertTrue(eigenlayerReserveManager.hasRole(adminRole, owner));
        assertFalse(eigenlayerReserveManager.hasRole(adminRole, newOwner));

        vm.startPrank(newOwner);
        // expect revert because admin transfer timelock delay has not passed
        // (3 remaining days exist on the timelock)
        vm.expectRevert(
            abi.encodeWithSignature("TimelockNotExpired(uint256)", 3 days)
        );
        eigenlayerReserveManager.acceptAdmin();

        vm.warp(block.timestamp + 3 days);
        eigenlayerReserveManager.acceptAdmin();
        assertFalse(eigenlayerReserveManager.hasRole(adminRole, owner));
        assertTrue(eigenlayerReserveManager.hasRole(adminRole, newOwner));
    }

    function testLrmTransferAdminCancelTransferAndReinitiateTransfer() public {
        vm.startPrank(owner);
        eigenlayerReserveManager.transferAdmin(newOwner);
        assertTrue(eigenlayerReserveManager.hasRole(adminRole, owner));
        assertFalse(eigenlayerReserveManager.hasRole(adminRole, newOwner));

        vm.warp(block.timestamp + 2 days);

        // cancel transfer mid-way
        eigenlayerReserveManager.cancelTransferAdmin();

        vm.warp(block.timestamp + 2 days);

        // expect accept admin transfer to fail
        vm.startPrank(newOwner);
        vm.expectRevert();
        eigenlayerReserveManager.acceptAdmin();

        // re-initiate transfer
        vm.startPrank(owner);
        eigenlayerReserveManager.transferAdmin(newOwner);

        // after delay has passed, new owner accepts transfer
        vm.warp(block.timestamp + 3 days);
        vm.startPrank(newOwner);
        eigenlayerReserveManager.acceptAdmin();
        assertFalse(eigenlayerReserveManager.hasRole(adminRole, owner));
        assertTrue(eigenlayerReserveManager.hasRole(adminRole, newOwner));
    }

    function testLrmTransferAdminWhenNotAdminFails() public {
        vm.startPrank(managerAgent);
        vm.expectRevert();
        eigenlayerReserveManager.transferAdmin(managerAgent);
    }

    function testLrmCannotTransferAdminWhenTransferIsInProgress() public {
        vm.startPrank(owner);
        eigenlayerReserveManager.transferAdmin(newOwner);
        vm.warp(block.timestamp + 1 days);

        // second transfer reverts because first transfer is already in progress
        vm.expectRevert(bytes4(keccak256("TransferAlreadyInProgress()")));
        eigenlayerReserveManager.transferAdmin(newOwner);
    }

    function testLrmCannotCancelNonexistentAdminTransfer() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes4(keccak256("NoActiveTransferRequest()")));
        eigenlayerReserveManager.cancelTransferAdmin();
    }
}
