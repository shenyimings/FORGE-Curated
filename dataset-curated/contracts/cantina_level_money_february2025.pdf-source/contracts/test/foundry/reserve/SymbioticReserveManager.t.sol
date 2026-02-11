// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {Test, console2} from "forge-std/Test.sol";

import {SymbioticReserveManager} from "../../../src/reserve/LevelSymbioticReserveManager.sol";

import {INetworkRestakeDelegator} from "../../interfaces/symbiotic/INetworkRestakeDelegator.sol";
import {IBaseDelegator} from "../../interfaces/symbiotic/IBaseDelegator.sol";
import {IVaultConfigurator} from "../../interfaces/symbiotic/IVaultConfigurator.sol";
import {IVault} from "../../interfaces/symbiotic/IVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MintingBaseSetup} from "../minting/MintingBaseSetup.sol";
import {IlvlUSD} from "../../../src/interfaces/IlvlUSD.sol";

import "./ReserveBaseSetup.sol";

contract SymbioticReserveManagerTest is Test, ReserveBaseSetup {
    using Math for uint256;

    SymbioticReserveManager internal symbioticReserveManager;

    address unwhitelistedVaultDepositor;
    uint256 unwhitelistedVaultDepositorPrivateKey;
    address vaultOwner;
    uint256 vaultOwnerPrivateKey;

    IVault usdcVault;
    IVault usdtVault;

    IVaultConfigurator vaultConfigurator;

    address public constant HOLESKY_SYMBIOTIC_VAULT_CONFIGURATOR =
        0x382e9c6fF81F07A566a8B0A3622dc85c47a891Df;

    address public constant HOLESKY_SYMBIOTIC_VAULT_FACTORY =
        0x18C659a269a7172eF78BBC19Fe47ad2237Be0590;

    uint256 public constant INITIAL_BALANCE = 100e6;
    uint256 public constant ALLOWANCE = 100000e6;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        symbioticReserveManager = new SymbioticReserveManager(
            IlvlUSD(address(lvlusdToken)),
            stakedlvlUSD,
            address(owner),
            address(owner)
        );
        _setupReserveManager(symbioticReserveManager);

        // Setup forked environment.
        string memory rpcKey = "HOLESKY_RPC_URL";
        uint256 blockNumber = 2560594;

        utils.startFork(rpcKey, blockNumber);

        (
            unwhitelistedVaultDepositor,
            unwhitelistedVaultDepositorPrivateKey
        ) = makeAddrAndKey("unwhitelistedVaultDepositor");
        (vaultOwner, vaultOwnerPrivateKey) = makeAddrAndKey("vaultOwner");

        vaultConfigurator = IVaultConfigurator(
            HOLESKY_SYMBIOTIC_VAULT_CONFIGURATOR
        );

        (address _usdcVaultAddress, , ) = _createVault(
            address(USDCToken),
            vaultOwner,
            false,
            0
        );

        usdcVault = IVault(_usdcVaultAddress);

        (address _usdtVaultAddress, , ) = _createVault(
            address(USDTToken),
            vaultOwner,
            false,
            0
        );

        usdtVault = IVault(_usdtVaultAddress);

        vm.startPrank(owner);

        USDCToken.mint(INITIAL_BALANCE, address(symbioticReserveManager));
        USDTToken.transfer(address(symbioticReserveManager), INITIAL_BALANCE);
    }

    // Vaults parameters include:
    //  - 1 week epochDuration
    //  - depositWhitelist: true
    function _createVault(
        address collateral,
        address vaultOwner,
        bool isDepositLimit,
        uint256 depositLimit
    ) public returns (address vault, address delegator, address slasher) {
        vm.startPrank(vaultOwner);
        address[] memory networkLimitSetRoleHolders = new address[](1);
        networkLimitSetRoleHolders[0] = vaultOwner;
        address[] memory operatorNetworkSharesSetRoleHolders = new address[](1);
        operatorNetworkSharesSetRoleHolders[0] = vaultOwner;
        (vault, delegator, slasher) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: vaultOwner,
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: collateral,
                        burner: address(0),
                        epochDuration: 1 weeks,
                        depositWhitelist: true,
                        isDepositLimit: isDepositLimit,
                        depositLimit: depositLimit,
                        defaultAdminRoleHolder: vaultOwner,
                        depositWhitelistSetRoleHolder: vaultOwner,
                        depositorWhitelistRoleHolder: vaultOwner,
                        isDepositLimitSetRoleHolder: vaultOwner,
                        depositLimitSetRoleHolder: vaultOwner
                    })
                ),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: vaultOwner,
                            hook: address(0),
                            hookSetRoleHolder: vaultOwner
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        IVault vault_ = IVault(vault);
        vault_.setDepositorWhitelistStatus(
            address(symbioticReserveManager),
            true
        );
    }

    function test__usdc__depositSuccess(uint256 depositAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        _test__depositSucess(usdcVault, address(USDCToken), depositAmount);
    }

    function test__usdc__withdrawSuccess(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        vm.assume(depositAmount > 0);
        vm.assume(withdrawAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        vm.assume(depositAmount > withdrawAmount);
        _test__withdrawSuccess(
            usdcVault,
            address(USDCToken),
            depositAmount,
            withdrawAmount
        );
    }

    function test__usdc__withdrawFailsWhenClaimingBeforeEpoch(
        uint256 depositAmount
    ) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        _test__withdrawFailsWhenClaimingBeforeEpoch(
            usdcVault,
            address(USDCToken),
            depositAmount
        );
    }

    function test__usdt__depositSuccess(uint256 depositAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        _test__depositSucess(usdtVault, address(USDTToken), depositAmount);
    }

    function test__usdt__withdrawSuccess(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        vm.assume(depositAmount > 0);
        vm.assume(withdrawAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        vm.assume(depositAmount > withdrawAmount);
        _test__withdrawSuccess(
            usdtVault,
            address(USDTToken),
            depositAmount,
            withdrawAmount
        );
    }

    function test__usdt__withdrawFailsWhenClaimingBeforeEpoch(
        uint256 depositAmount
    ) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        _test__withdrawFailsWhenClaimingBeforeEpoch(
            usdtVault,
            address(USDTToken),
            depositAmount
        );
    }

    function test__usdc__depositFailsWhenNotWhitelisted(
        uint256 depositAmount
    ) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);

        IVault vault = usdcVault;

        uint256 now_ = block.timestamp;
        vm.warp(now_);

        vm.startPrank(unwhitelistedVaultDepositor);

        vm.expectRevert();
        symbioticReserveManager.depositToSymbiotic(
            address(vault),
            depositAmount
        );
    }

    function test__failsWhenPaused() public {
        IVault vault = usdcVault;

        uint256 now_ = block.timestamp;
        vm.warp(now_);

        vm.startPrank(pauser);
        symbioticReserveManager.setPaused(true);

        vm.startPrank(managerAgent);
        vm.expectRevert();
        symbioticReserveManager.depositToSymbiotic(address(vault), 1);

        vm.expectRevert();
        symbioticReserveManager.withdrawFromSymbiotic(address(vault), 1);

        vm.expectRevert();
        symbioticReserveManager.claimFromSymbiotic(address(vault), 1);
    }

    function test__failsWhenNotManagerAgent() public {
        IVault vault = usdcVault;

        uint256 now_ = block.timestamp;
        vm.warp(now_);

        vm.startPrank(unwhitelistedVaultDepositor);
        vm.expectRevert();
        symbioticReserveManager.depositToSymbiotic(address(vault), 1);

        vm.expectRevert();
        symbioticReserveManager.withdrawFromSymbiotic(address(vault), 1);

        vm.expectRevert();
        symbioticReserveManager.claimFromSymbiotic(address(vault), 1);
    }

    function _test__depositSucess(
        IVault vault,
        address curCollateral,
        uint256 depositAmount
    ) private {
        uint256 now_ = block.timestamp;
        vm.warp(now_);

        vm.startPrank(managerAgent);

        (, uint256 mintedShares) = symbioticReserveManager.depositToSymbiotic(
            address(vault),
            depositAmount
        );

        assertEq(
            utils.checkBalance(curCollateral, address(symbioticReserveManager)),
            INITIAL_BALANCE - depositAmount
        );
        assertEq(
            vault.activeBalanceOf(address(symbioticReserveManager)),
            mintedShares
        );
    }

    function _test__withdrawSuccess(
        IVault vault,
        address curCollateral,
        uint256 depositAmount,
        uint256 withdrawAmount
    ) private {
        uint256 now_ = block.timestamp;
        vm.warp(now_);

        vm.startPrank(managerAgent);
        symbioticReserveManager.depositToSymbiotic(
            address(vault),
            depositAmount
        );

        uint256 e = vault.currentEpoch();

        symbioticReserveManager.withdrawFromSymbiotic(
            address(vault),
            withdrawAmount
        );

        // Warp to the end of the next epoch to ensure the withdrawal is processed
        vm.warp(now_ + 2 * vault.epochDuration() + 1);

        assertEq(
            utils.checkBalance(curCollateral, address(symbioticReserveManager)),
            INITIAL_BALANCE - depositAmount
        );

        symbioticReserveManager.claimFromSymbiotic(address(vault), e + 1);

        assertEq(
            utils.checkBalance(curCollateral, address(symbioticReserveManager)),
            INITIAL_BALANCE - (depositAmount - withdrawAmount)
        );
    }

    function _test__withdrawFailsWhenClaimingBeforeEpoch(
        IVault vault,
        address curCollateral,
        uint256 depositAmount
    ) private {
        uint256 now_ = block.timestamp;
        vm.warp(now_);

        vm.startPrank(managerAgent);
        symbioticReserveManager.depositToSymbiotic(
            address(vault),
            depositAmount
        );

        uint256 e = vault.currentEpoch();

        symbioticReserveManager.withdrawFromSymbiotic(
            address(vault),
            depositAmount
        );

        // Test that we cannot claim too early
        vm.expectRevert();
        symbioticReserveManager.claimFromSymbiotic(address(vault), e + 1);
    }
}
