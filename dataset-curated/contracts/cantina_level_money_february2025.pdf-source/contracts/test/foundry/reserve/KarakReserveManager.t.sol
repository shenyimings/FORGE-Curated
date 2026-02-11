// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {KarakReserveManager} from "../../../src/reserve/LevelKarakReserveManager.sol";

import {IlvlUSD} from "../../../src/interfaces/IlvlUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

import "../../interfaces/karak/KarakTestInterfaces.sol";

import "./ReserveBaseSetup.sol";

contract KarakReserveManagerTest is Test, ReserveBaseSetup {
    KarakReserveManager internal karakReserveManager;

    uint256 now_;

    IVault usdcVault;
    IVault daiVault;

    ICore core;

    address unwhitelistedVaultDepositor;
    uint256 unwhitelistedVaultDepositorPrivateKey;
    address vaultOwner;
    uint256 vaultOwnerPrivateKey;
    address constant slashingHandler = address(16);

    address public constant SEPOLIA_KARAK_CORE_PROXY_ADDRESS = 0x661F7a0F337eb3b55e7B3D6CAB32AF90ca10EF7C;

    address public constant SEPOLIA_KARAK_CORE_MANAGER_ADDRESS = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;

    uint256 public constant INITIAL_BALANCE = 100e6;
    uint256 public constant TOKEN_ALLOWANCE = 100000e18;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        karakReserveManager =
            new KarakReserveManager(IlvlUSD(address(lvlusdToken)), stakedlvlUSD, address(owner), address(owner));
        _setupReserveManager(karakReserveManager);

        // Setup forked environment.
        string memory rpcKey = "SEPOLIA_RPC_URL";
        uint256 blockNumber = 6906400;

        utils.startFork(rpcKey, blockNumber);
        now_ = block.timestamp;
        vm.warp(now_);

        (unwhitelistedVaultDepositor, unwhitelistedVaultDepositorPrivateKey) =
            makeAddrAndKey("unwhitelistedVaultDepositor");
        (vaultOwner, vaultOwnerPrivateKey) = makeAddrAndKey("vaultOwner");

        core = ICore(SEPOLIA_KARAK_CORE_PROXY_ADDRESS);

        vm.startPrank(SEPOLIA_KARAK_CORE_MANAGER_ADDRESS);

        address[] memory assets = new address[](2);
        assets[0] = address(USDCToken);
        assets[1] = address(DAIToken);
        // Slashing Handler for the asset
        address[] memory slashingHandlers = new address[](2);
        slashingHandlers[0] = slashingHandler;
        slashingHandlers[1] = slashingHandler;
        core.allowlistAssets(assets, slashingHandlers);

        // Deploy Vaults
        VaultLib.Config[] memory vaultConfigs = new VaultLib.Config[](2);
        vaultConfigs[0] = VaultLib.Config({
            asset: address(USDCToken),
            decimals: 6,
            operator: vaultOwner,
            name: "TestUSDCVault",
            symbol: "TVUSDC",
            extraData: bytes("")
        });
        vaultConfigs[1] = VaultLib.Config({
            asset: address(DAIToken),
            decimals: 18,
            operator: vaultOwner,
            name: "TestDAIVault",
            symbol: "TVDAI",
            extraData: bytes("")
        });

        IKarakBaseVault[] memory vaults = core.deployVaults(vaultConfigs, address(0));

        vm.startPrank(owner);
        usdcVault = IVault(address(vaults[0]));
        daiVault = IVault(address(vaults[1]));

        USDCToken.mint(INITIAL_BALANCE, address(karakReserveManager));
        DAIToken.mint(INITIAL_BALANCE, address(karakReserveManager));

        karakReserveManager.approveSpender(address(USDCToken), address(usdcVault), type(uint256).max);
        karakReserveManager.approveSpender(
            address(usdcVault), // shares token
            address(usdcVault),
            type(uint256).max
        );

        karakReserveManager.approveSpender(address(DAIToken), address(daiVault), type(uint256).max);
        karakReserveManager.approveSpender(
            address(daiVault), // shares token
            address(daiVault),
            type(uint256).max
        );
    }

    function test__usdc__depositSucceeds(uint256 depositAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        _test__depositSucceeds(usdcVault, USDCToken, address(usdcVault), depositAmount);
    }

    function test__usdc__withdrawSucceeds(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(withdrawAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);
        vm.assume(depositAmount > withdrawAmount);

        _test__withdrawSucceeds(usdcVault, USDCToken, address(usdcVault), depositAmount, withdrawAmount);
    }

    function test__usdc__withdrawFailsWhenBeforeUnlock(uint256 depositAmount, uint256 unlockTime) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= INITIAL_BALANCE);

        vm.assume(unlockTime >= 0);
        vm.assume(unlockTime < Constants.MIN_WITHDRAWAL_DELAY);

        _test__withdrawFailsWhenBeforeUnlock(usdcVault, USDCToken, unlockTime, depositAmount);
    }

    function _test__depositSucceeds(IVault vault, IERC20 token, address sharesContract, uint256 depositAmount)
        internal
    {
        vm.startPrank(managerAgent);
        uint256 shares = karakReserveManager.depositToKarak(address(vault), depositAmount);
        assertEq(utils.checkBalance(address(token), address(karakReserveManager)), INITIAL_BALANCE - depositAmount);
        assertEq(utils.checkBalance(address(vault), address(karakReserveManager)), depositAmount);

        uint256 underlying = IERC4626(address(vault)).convertToAssets(shares);
        assertEq(underlying, depositAmount);
    }

    function _test__withdrawSucceeds(
        IVault vault,
        IERC20 token,
        address sharesContract,
        uint256 depositAmount,
        uint256 withdrawAmount
    ) internal {
        vm.startPrank(managerAgent);
        uint256 shares = karakReserveManager.depositToKarak(address(vault), depositAmount);

        bytes32 withdrawalKey = karakReserveManager.startRedeemFromKarak(address(vault), shares);

        skip(10 days);
        karakReserveManager.finishRedeemFromKarak(address(vault), withdrawalKey);
        assertEq(token.balanceOf(address(karakReserveManager)), INITIAL_BALANCE);
    }

    function _test__withdrawFailsWhenBeforeUnlock(IVault vault, IERC20 token, uint256 unlockTime, uint256 depositAmount)
        internal
    {
        vm.startPrank(managerAgent);
        uint256 shares = karakReserveManager.depositToKarak(address(vault), depositAmount);

        bytes32 withdrawalKey = karakReserveManager.startRedeemFromKarak(address(vault), shares);

        skip(unlockTime);

        vm.expectRevert(MinWithdrawDelayNotPassed.selector);
        karakReserveManager.finishRedeemFromKarak(address(vault), withdrawalKey);
    }
}
