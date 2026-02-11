// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { ILiquidityPool } from "src/interfaces/IStaking.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { AtomicSolverV3, AtomicQueue } from "src/atomic-queue/AtomicSolverV3.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

// Mock Keyring contract for testing
contract MockKeyring {
    mapping(address => mapping(uint256 => bool)) public credentials;

    function setCredential(address entity, uint256 policyId, bool status) external {
        credentials[entity][policyId] = status;
    }

    function checkCredential(uint256 policyId, address entity) external view returns (bool) {
        return credentials[entity][policyId];
    }
}

contract TellerWithMultiAssetSupportTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;

    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    TellerWithMultiAssetSupport public teller;
    AccountantWithRateProviders public accountant;
    address public payout_address = vm.addr(7_777_777);
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    RolesAuthority public rolesAuthority;
    AtomicQueue public atomicQueue;
    AtomicSolverV3 public atomicSolverV3;

    address public solver = vm.addr(54);
    uint256 ONE_SHARE;

    MockKeyring public mockKeyring;
    uint256 public constant TEST_POLICY_ID = 7;
    address public kycUser = vm.addr(1111);
    address public nonKycUser = vm.addr(2222);
    address public manualWhitelistUser = vm.addr(3333);
    address public contractAddress = vm.addr(4444); // Mock AMM/protocol

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19_363_419;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        ONE_SHARE = 10 ** boringVault.decimals();

        accountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );

        teller = new TellerWithMultiAssetSupport(address(this), address(boringVault), address(accountant));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        atomicQueue = new AtomicQueue(address(accountant));
        atomicSolverV3 = new AtomicSolverV3(address(this), rolesAuthority);

        boringVault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);
        teller.setDepositCap(type(uint256).max);

        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.addAsset.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.removeAsset.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.bulkDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.refundDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            MINTER_ROLE, address(accountant), AccountantWithRateProviders.checkpoint.selector, true
        );
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV3), AtomicSolverV3.finishSolve.selector, true);
        rolesAuthority.setRoleCapability(
            CAN_SOLVE_ROLE, address(atomicSolverV3), AtomicSolverV3.redeemSolve.selector, true
        );
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(
            address(teller), TellerWithMultiAssetSupport.depositWithPermit.selector, true
        );

        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV3), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(solver, CAN_SOLVE_ROLE, true);

        teller.addAsset(WETH);
        teller.addAsset(ERC20(NATIVE));
        teller.addAsset(EETH);
        teller.addAsset(WEETH);

        accountant.setRateProviderData(EETH, true, address(0));
        accountant.setRateProviderData(WEETH, false, address(WEETH_RATE_PROVIDER));

        // Deploy mock Keyring
        mockKeyring = new MockKeyring();

        // Setup KYC for test users
        mockKeyring.setCredential(kycUser, TEST_POLICY_ID, true);
        mockKeyring.setCredential(address(this), TEST_POLICY_ID, true); // Test contract has KYC
        // nonKycUser has no KYC by default

        // Fund test users
        deal(address(WETH), kycUser, 100e18);
        deal(address(WETH), nonKycUser, 100e18);
        deal(address(WETH), manualWhitelistUser, 100e18);
        deal(address(WETH), contractAddress, 100e18);
    }

    function testDepositReverting(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);
        // Turn on share lock period, and deposit reverting
        boringVault.setBeforeTransferHook(address(teller));

        teller.setShareLockPeriod(1 days);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);
        uint256 shares0 = teller.deposit(WETH, wETH_amount, 0);
        uint256 firstDepositTimestamp = block.timestamp;
        // Skip 1 days to finalize first deposit.
        skip(1 days + 1);
        uint256 shares1 = teller.deposit(EETH, eETH_amount, 0);
        uint256 secondDepositTimestamp = block.timestamp;

        // Even if setShareLockPeriod is set to 2 days, first deposit is still not revertable.
        teller.setShareLockPeriod(2 days);

        // If depositReverter tries to revert the first deposit, call fails.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SharesAreUnLocked.selector)
        );
        teller.refundDeposit(1, address(this), address(WETH), wETH_amount, shares0, firstDepositTimestamp, 1 days);

        // However the second deposit is still revertable.
        teller.refundDeposit(2, address(this), address(EETH), eETH_amount, shares1, secondDepositTimestamp, 1 days);

        // Calling revert deposit again should revert.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__BadDepositHash.selector)
        );
        teller.refundDeposit(2, address(this), address(EETH), eETH_amount, shares1, secondDepositTimestamp, 1 days);
    }

    function testUserDepositPeggedAssets(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);

        teller.deposit(WETH, wETH_amount, 0);
        teller.deposit(EETH, eETH_amount, 0);

        uint256 expected_shares = 2 * amount;

        assertEq(boringVault.balanceOf(address(this)), expected_shares, "Should have received expected shares");
    }

    function testUserDepositNonPeggedAssets(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), address(this), weETH_amount);

        WEETH.safeApprove(address(boringVault), weETH_amount);

        teller.deposit(WEETH, weETH_amount, 0);

        uint256 expected_shares = amount;

        assertApproxEqRel(
            boringVault.balanceOf(address(this)), expected_shares, 0.000001e18, "Should have received expected shares"
        );
    }

    function testUserPermitDeposit(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 userKey = 111;
        address user = vm.addr(userKey);

        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), user, weETH_amount);
        // function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weETH_amount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        vm.startPrank(user);
        teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, v, r, s);
        vm.stopPrank();

        // and if user supplied wrong permit data, deposit will fail.
        digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weETH_amount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (v, r, s) = vm.sign(userKey, digest);

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__PermitFailedAndAllowanceTooLow.selector
            )
        );
        teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, v, r, s);
        vm.stopPrank();
    }

    function testUserPermitDepositWithFrontRunning(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 userKey = 111;
        address user = vm.addr(userKey);

        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), user, weETH_amount);
        // function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weETH_amount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        // Assume attacker seems users TX in the mem pool and tries griefing them by calling `permit` first.
        address attacker = vm.addr(0xDEAD);
        vm.startPrank(attacker);
        WEETH.permit(user, address(boringVault), weETH_amount, block.timestamp, v, r, s);
        vm.stopPrank();

        // Users TX is still successful.
        vm.startPrank(user);
        teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, v, r, s);
        vm.stopPrank();

        assertTrue(boringVault.balanceOf(user) > 0, "Should have received shares");
    }

    function testBulkDeposit(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();
        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), address(this), weETH_amount);

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);
        WEETH.safeApprove(address(boringVault), weETH_amount);

        teller.bulkDeposit(WETH, wETH_amount, 0, address(this));
        teller.bulkDeposit(EETH, eETH_amount, 0, address(this));
        teller.bulkDeposit(WEETH, weETH_amount, 0, address(this));

        uint256 expected_shares = 3 * amount;

        assertApproxEqRel(
            boringVault.balanceOf(address(this)), expected_shares, 0.0001e18, "Should have received expected shares"
        );
    }

    function testBulkWithdraw(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();
        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), address(this), weETH_amount);

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);
        WEETH.safeApprove(address(boringVault), weETH_amount);

        uint256 shares_0 = teller.bulkDeposit(WETH, wETH_amount, 0, address(this));
        uint256 shares_1 = teller.bulkDeposit(EETH, eETH_amount, 0, address(this));
        uint256 shares_2 = teller.bulkDeposit(WEETH, weETH_amount, 0, address(this));

        uint256 assets_out_0 = teller.bulkWithdraw(WETH, shares_0, 0, address(this));
        uint256 assets_out_1 = teller.bulkWithdraw(EETH, shares_1, 0, address(this));
        uint256 assets_out_2 = teller.bulkWithdraw(WEETH, shares_2, 0, address(this));

        assertApproxEqAbs(assets_out_0, wETH_amount, 1, "Should have received expected wETH assets");
        assertApproxEqAbs(assets_out_1, eETH_amount, 1, "Should have received expected eETH assets");
        assertApproxEqAbs(assets_out_2, weETH_amount, 1, "Should have received expected weETH assets");
    }

    function testWithdrawWithAtomicQueue(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        address user = vm.addr(9);
        mockKeyring.setCredential(user, TEST_POLICY_ID, true);
        uint256 wETH_amount = amount;
        deal(address(WETH), user, wETH_amount);

        vm.startPrank(user);
        WETH.safeApprove(address(boringVault), wETH_amount);

        uint256 shares = teller.deposit(WETH, wETH_amount, 0);

        // Share lock period is not set, so user can submit withdraw request immediately.
        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            offerAmount: uint96(shares),
            inSolve: false
        });
        boringVault.approve(address(atomicQueue), shares);
        atomicQueue.updateAtomicRequest(boringVault, WETH, req.deadline, req.offerAmount);
        vm.stopPrank();

        // Solver approves solver contract to spend enough assets to cover withdraw.
        vm.startPrank(solver);
        WETH.safeApprove(address(atomicSolverV3), wETH_amount);
        // Solve withdraw request.
        address[] memory users = new address[](1);
        users[0] = user;
        atomicSolverV3.redeemSolve(atomicQueue, boringVault, WETH, users, 0, type(uint256).max, teller);
        vm.stopPrank();
    }

    function testAssetIsSupported() external {
        assertTrue(teller.isSupported(WETH) == true, "WETH should be supported");

        teller.removeAsset(WETH);

        assertTrue(teller.isSupported(WETH) == false, "WETH should not be supported");

        teller.addAsset(WETH);

        assertTrue(teller.isSupported(WETH) == true, "WETH should be supported");
    }

    function testReverts() external {
        // Test pause logic
        teller.pause();

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector)
        );
        teller.deposit(WETH, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector)
        );
        teller.depositWithPermit(WETH, 0, 0, 0, 0, bytes32(0), bytes32(0));

        teller.unpause();

        teller.removeAsset(WETH);

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__AssetNotSupported.selector)
        );
        teller.deposit(WETH, 0, 0);

        teller.addAsset(WETH);

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ZeroAssets.selector)
        );
        teller.deposit(WETH, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__MinimumMintNotMet.selector)
        );
        teller.deposit(WETH, 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ZeroAssets.selector)
        );
        teller.deposit(NATIVE_ERC20, 0, 0);

        // bulkDeposit reverts
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ZeroAssets.selector)
        );
        teller.bulkDeposit(WETH, 0, 0, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__MinimumMintNotMet.selector)
        );
        teller.bulkDeposit(WETH, 1, type(uint256).max, address(this));

        // bulkWithdraw reverts
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ZeroShares.selector)
        );
        teller.bulkWithdraw(WETH, 0, 0, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__MinimumAssetsNotMet.selector
            )
        );
        teller.bulkWithdraw(WETH, 1, type(uint256).max, address(this));

        // Set share lock reverts
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ShareLockPeriodTooLong.selector
            )
        );
        teller.setShareLockPeriod(3 days + 1);

        teller.setShareLockPeriod(3 days);
        boringVault.setBeforeTransferHook(address(teller));

        // Have user deposit
        address user = vm.addr(333);
        vm.startPrank(user);
        uint256 wETH_amount = 1e18;
        deal(address(WETH), user, wETH_amount);
        WETH.safeApprove(address(boringVault), wETH_amount);

        teller.deposit(WETH, wETH_amount, 0);

        // Trying to transfer shares should revert.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SharesAreLocked.selector)
        );
        boringVault.transfer(address(this), 1);

        vm.stopPrank();
        // Calling transferFrom should also revert.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SharesAreLocked.selector)
        );
        boringVault.transferFrom(user, address(this), 1);

        // But if user waits 3 days.
        skip(3 days + 1);
        // They can now transfer.
        vm.prank(user);
        boringVault.transfer(address(this), 1);
    }

    function testKeyringMode() external {
        // Setup Keyring mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        uint256 depositAmount = 1e18;

        // Test 1: KYC user can deposit
        vm.startPrank(kycUser);
        WETH.approve(address(boringVault), depositAmount);
        uint256 shares = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares, 0, "KYC user should receive shares");
        vm.stopPrank();

        // Test 2: Non-KYC user cannot deposit
        vm.startPrank(nonKycUser);
        WETH.approve(address(boringVault), depositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__KeyringCredentialInvalid.selector
            )
        );
        teller.deposit(WETH, depositAmount, 0);
        vm.stopPrank();

        // Test 3: Contract whitelist works in Keyring mode
        teller.updateContractWhitelist(toArray(contractAddress), true);
        vm.startPrank(contractAddress);
        WETH.approve(address(boringVault), depositAmount);
        shares = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares, 0, "Whitelisted contract should be able to deposit");
        vm.stopPrank();
    }

    function testManualWhitelistMode() external {
        // Setup Manual Whitelist mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.MANUAL_WHITELIST);

        uint256 depositAmount = 1e18;

        // Test 1: Non-whitelisted user cannot deposit
        vm.startPrank(manualWhitelistUser);
        WETH.approve(address(boringVault), depositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__NotWhitelisted.selector)
        );
        teller.deposit(WETH, depositAmount, 0);
        vm.stopPrank();

        // Test 2: Add user to whitelist
        teller.updateManualWhitelist(toArray(manualWhitelistUser), true);

        // Test 3: Whitelisted user can deposit
        vm.startPrank(manualWhitelistUser);
        uint256 shares = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares, 0, "Whitelisted user should receive shares");
        vm.stopPrank();

        // Test 4: Remove from whitelist
        teller.updateManualWhitelist(toArray(manualWhitelistUser), false);

        vm.startPrank(manualWhitelistUser);
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__NotWhitelisted.selector)
        );
        teller.deposit(WETH, depositAmount, 0);
        vm.stopPrank();
    }

    function testDisabledMode() external {
        // Default mode should be DISABLED
        assertEq(uint256(teller.accessControlMode()), 0, "Default should be DISABLED");

        uint256 depositAmount = 1e18;

        // Anyone can deposit in disabled mode
        vm.startPrank(nonKycUser);
        WETH.approve(address(boringVault), depositAmount);
        uint256 shares = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares, 0, "Any user should be able to deposit in DISABLED mode");
        vm.stopPrank();
    }

    function testModeTransitions() external {
        uint256 depositAmount = 1e18;

        // Start in DISABLED mode
        vm.startPrank(kycUser);
        WETH.approve(address(boringVault), depositAmount * 3);

        // Deposit in DISABLED mode
        teller.deposit(WETH, depositAmount, 0);

        // Switch to KEYRING mode
        vm.stopPrank();
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        // KYC user can still deposit
        vm.startPrank(kycUser);
        teller.deposit(WETH, depositAmount, 0);
        vm.stopPrank();

        // Non-KYC user cannot
        vm.startPrank(nonKycUser);
        WETH.approve(address(boringVault), depositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__KeyringCredentialInvalid.selector
            )
        );
        teller.deposit(WETH, depositAmount, 0);
        vm.stopPrank();

        // Switch to MANUAL_WHITELIST mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.MANUAL_WHITELIST);
        teller.updateManualWhitelist(toArray(kycUser), true);

        // KYC user can deposit because they're manually whitelisted
        vm.startPrank(kycUser);
        teller.deposit(WETH, depositAmount, 0);
        vm.stopPrank();
    }

    function testBulkDepositAccessControl() external {
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        uint256 depositAmount = 1e18;

        deal(address(WETH), address(this), depositAmount);

        WETH.approve(address(boringVault), depositAmount);

        // Test bulkDeposit checks the 'to' parameter
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__KeyringCredentialInvalid.selector
            )
        );
        teller.bulkDeposit(WETH, depositAmount, 0, nonKycUser); // 'to' has no KYC

        // Should work for KYC user
        uint256 shares = teller.bulkDeposit(WETH, depositAmount, 0, kycUser);
        assertGt(shares, 0, "Should deposit to KYC user");
    }

    function testBulkWithdrawAccessControl() external {
        // First deposit some shares
        uint256 depositAmount = 10e18;
        deal(address(WETH), address(this), depositAmount);
        WETH.approve(address(boringVault), depositAmount);
        uint256 shares = teller.deposit(WETH, depositAmount, 0);

        // Transfer shares to non-KYC user
        boringVault.transfer(nonKycUser, shares);

        // Enable Keyring mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        // Give solver role to nonKycUser for testing
        rolesAuthority.setUserRole(nonKycUser, SOLVER_ROLE, true);

        // Non-KYC user cannot withdraw
        vm.startPrank(nonKycUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__KeyringCredentialInvalid.selector
            )
        );
        teller.bulkWithdraw(WETH, shares, 0, nonKycUser);
        vm.stopPrank();

        // Give KYC to user and retry
        mockKeyring.setCredential(nonKycUser, TEST_POLICY_ID, true);

        vm.startPrank(nonKycUser);
        uint256 assetsOut = teller.bulkWithdraw(WETH, shares, 0, nonKycUser);
        assertGt(assetsOut, 0, "KYC user should be able to withdraw");
        vm.stopPrank();
    }

    function testAccessControlEvents() external {
        // Test AccessControlModeUpdated event
        vm.expectEmit(true, true, false, true);
        emit TellerWithMultiAssetSupport.AccessControlModeUpdated(
            TellerWithMultiAssetSupport.AccessControlMode.DISABLED,
            TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC
        );
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);

        // Test KeyringConfigUpdated event
        vm.expectEmit(true, true, false, true);
        emit TellerWithMultiAssetSupport.KeyringConfigUpdated(address(mockKeyring), TEST_POLICY_ID);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        // Test ManualWhitelistUpdated event
        vm.expectEmit(true, true, false, true);
        emit TellerWithMultiAssetSupport.ManualWhitelistUpdated(kycUser, true);
        teller.updateManualWhitelist(toArray(kycUser), true);

        // Test ContractWhitelistUpdated event
        vm.expectEmit(true, true, false, true);
        emit TellerWithMultiAssetSupport.ContractWhitelistUpdated(contractAddress, true);
        teller.updateContractWhitelist(toArray(contractAddress), true);
    }

    function testDepositWithPermitAccessControl() external {
        // Setup Keyring mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        uint256 userKey = 9999;
        address user = vm.addr(userKey);

        // Calculate weETH amount based on rate
        uint256 depositAmount = 1e18;
        uint256 weETH_amount = depositAmount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());

        // Give user weETH
        deal(address(WEETH), user, weETH_amount);

        // Create permit signature for weETH
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weETH_amount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        // Non-KYC user cannot deposit with permit
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__KeyringCredentialInvalid.selector
            )
        );
        teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, v, r, s);
        vm.stopPrank();

        // Give user KYC and retry
        mockKeyring.setCredential(user, TEST_POLICY_ID, true);

        vm.startPrank(user);
        uint256 shares = teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, v, r, s);
        assertGt(shares, 0, "KYC user should be able to deposit with permit");
        vm.stopPrank();
    }

    function testContractWhitelistBothModes() external {
        uint256 depositAmount = 1e18;

        // Test in KEYRING mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);
        teller.updateContractWhitelist(toArray(contractAddress), true);

        vm.startPrank(contractAddress);
        WETH.approve(address(boringVault), depositAmount * 2);
        uint256 shares1 = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares1, 0, "Contract should deposit in Keyring mode");
        vm.stopPrank();

        // Switch to MANUAL_WHITELIST mode - contract whitelist should still work
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.MANUAL_WHITELIST);

        vm.startPrank(contractAddress);
        uint256 shares2 = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares2, 0, "Contract should deposit in Manual mode");
        vm.stopPrank();
    }

    function testTransfersUnrestricted() external {
        // Deposit with KYC user in KEYRING mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        vm.startPrank(kycUser);
        WETH.approve(address(boringVault), 1e18);
        uint256 shares = teller.deposit(WETH, 1e18, 0);

        // Transfer to non-KYC user works
        boringVault.transfer(nonKycUser, shares);
        vm.stopPrank();

        // Non-KYC user can transfer
        vm.prank(nonKycUser);
        boringVault.transfer(manualWhitelistUser, shares / 2);

        assertEq(boringVault.balanceOf(manualWhitelistUser), shares / 2);
    }

    function testTransfersUnrestrictedWithAccessControl() external {
        // Deposit with KYC user
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        vm.startPrank(kycUser);
        WETH.approve(address(boringVault), 1e18);
        uint256 shares = teller.deposit(WETH, 1e18, 0);

        // Transfer to non-KYC user should work
        boringVault.transfer(nonKycUser, shares);
        assertEq(boringVault.balanceOf(nonKycUser), shares, "Transfer should work");
        vm.stopPrank();

        // Non-KYC user can transfer to anyone
        vm.startPrank(nonKycUser);
        boringVault.transfer(manualWhitelistUser, shares / 2);
        assertEq(boringVault.balanceOf(manualWhitelistUser), shares / 2, "Transfer should work");
        vm.stopPrank();
    }

    function testManualWhitelistModeComplete() external {
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.MANUAL_WHITELIST);

        // Test depositWithPermit
        address user = vm.addr(8888);
        uint256 weethAmount = 968_199_670_816_024_612; // Fixed amount to avoid repeated calculations
        deal(address(WEETH), user, weethAmount);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weethAmount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(8888, digest);

        // Should fail without whitelist
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__NotWhitelisted.selector)
        );
        teller.depositWithPermit(WEETH, weethAmount, 0, block.timestamp, v, r, s);
        vm.stopPrank();

        // Add to whitelist and retry
        teller.updateManualWhitelist(toArray(user), true);

        vm.prank(user);
        assertGt(teller.depositWithPermit(WEETH, weethAmount, 0, block.timestamp, v, r, s), 0);

        // Test bulkDeposit
        address freshUser = vm.addr(7777);
        teller.updateManualWhitelist(toArray(address(this)), true);
        deal(address(WETH), address(this), 1e18);
        WETH.approve(address(boringVault), 1e18);

        // Should fail for non-whitelisted recipient
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__NotWhitelisted.selector)
        );
        teller.bulkDeposit(WETH, 1e18, 0, freshUser);

        // Whitelist recipient and deposit
        teller.updateManualWhitelist(toArray(freshUser), true);
        uint256 shares = teller.bulkDeposit(WETH, 1e18, 0, freshUser);

        // Test bulkWithdraw
        vm.prank(freshUser);
        boringVault.transfer(address(this), shares);

        rolesAuthority.setUserRole(address(this), SOLVER_ROLE, true);
        assertGt(teller.bulkWithdraw(WETH, shares, 0, address(this)), 0);
    }

    function testContractWhitelistAcrossModes() external {
        uint256 depositAmount = 1e18;
        address protocol = vm.addr(5555);
        deal(address(WETH), protocol, depositAmount * 3);

        // Add to contract whitelist
        teller.updateContractWhitelist(toArray(protocol), true);

        // Test in KEYRING mode (protocol has no KYC)
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        vm.startPrank(protocol);
        WETH.approve(address(boringVault), depositAmount * 3);
        uint256 shares1 = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares1, 0, "Contract whitelist should work in Keyring mode");
        vm.stopPrank();

        // Test in MANUAL_WHITELIST mode (protocol not in manual whitelist)
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.MANUAL_WHITELIST);

        vm.startPrank(protocol);
        uint256 shares2 = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares2, 0, "Contract whitelist should work in Manual mode");
        vm.stopPrank();

        // Test in DISABLED mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.DISABLED);

        vm.startPrank(protocol);
        uint256 shares3 = teller.deposit(WETH, depositAmount, 0);
        assertGt(shares3, 0, "Should work in Disabled mode");
        vm.stopPrank();
    }

    function testTransfersUnrestrictedAllModes() external {
        uint256 depositAmount = 1e18;

        // Deposit with KYC user in KEYRING mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.KEYRING_KYC);
        teller.setKeyringConfig(address(mockKeyring), TEST_POLICY_ID);

        vm.startPrank(kycUser);
        WETH.approve(address(boringVault), depositAmount);
        uint256 shares = teller.deposit(WETH, depositAmount, 0);

        // Transfer to non-KYC user
        boringVault.transfer(nonKycUser, shares);
        assertEq(boringVault.balanceOf(nonKycUser), shares, "Transfer should work");
        vm.stopPrank();

        // Non-KYC user transfers to non-whitelisted user
        address randomUser = vm.addr(9876);
        vm.prank(nonKycUser);
        boringVault.transfer(randomUser, shares / 2);
        assertEq(boringVault.balanceOf(randomUser), shares / 2, "Transfer should work");

        // Switch to MANUAL_WHITELIST mode
        teller.setAccessControlMode(TellerWithMultiAssetSupport.AccessControlMode.MANUAL_WHITELIST);

        // Random user (not whitelisted) can still transfer
        vm.prank(randomUser);
        boringVault.transfer(kycUser, shares / 4);
        assertEq(boringVault.balanceOf(kycUser), shares / 4, "Transfer should work");
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

    function toArray(address addr) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }
}
