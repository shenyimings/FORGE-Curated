// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import "../src/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../src/access/P2pOperator.sol";
import "../src/adapters/resolv/p2pResolvProxyFactory/P2pResolvProxyFactory.sol";
import "../src/p2pYieldProxyFactory/P2pYieldProxyFactory.sol";
import "./mock/IERC20Rebasing.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";


contract USRIntegration is Test {
    using SafeERC20 for IERC20;

    address constant USR = 0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110;
    address constant stUSR = 0x6c8984bc7DBBeDAf4F6b2FD766f16eBB7d10AAb4;
    address constant RESOLV = 0x259338656198eC7A76c729514D3CB45Dfbf768A1;
    address constant stRESOLV = 0xFE4BCE4b3949c35fB17691D8b03c3caDBE2E5E23;
    address constant P2pTreasury = 0xfeef177E6168F9b7fd59e6C5b6c2d87FF398c6FD;
    address constant StakedTokenDistributor = 0xCE9d50db432e0702BcAd5a4A9122F1F8a77aD8f9;

    P2pResolvProxyFactory private factory;

    address private clientAddress;
    uint256 private clientPrivateKey;

    address private p2pSignerAddress;
    uint256 private p2pSignerPrivateKey;

    address private p2pOperatorAddress;
    address private nobody;

    uint256 constant SigDeadline = 1750723200;
    uint96 constant ClientBasisPoints = 8700; // 13% fee
    uint256 constant DepositAmount = 10 ether;

    address proxyAddress;

    uint48 nonce;

    function setUp() public {
        vm.createSelectFork("mainnet", 22730789);

        (clientAddress, clientPrivateKey) = makeAddrAndKey("client");
        (p2pSignerAddress, p2pSignerPrivateKey) = makeAddrAndKey("p2pSigner");
        p2pOperatorAddress = makeAddr("p2pOperator");
        nobody = makeAddr("nobody");

        vm.startPrank(p2pOperatorAddress);
        AllowedCalldataChecker implementation = new AllowedCalldataChecker();
        ProxyAdmin admin = new ProxyAdmin();
        bytes memory initData = abi.encodeWithSelector(AllowedCalldataChecker.initialize.selector);
        TransparentUpgradeableProxy tup = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            initData
        );
        factory = new P2pResolvProxyFactory(
            p2pSignerAddress,
            P2pTreasury,
            stUSR,
            USR,
            stRESOLV,
            RESOLV,
            address(tup),
            StakedTokenDistributor
        );
        vm.stopPrank();

        proxyAddress = factory.predictP2pYieldProxyAddress(clientAddress, ClientBasisPoints);
    }

    function test_Resolv_happyPath_Mainnet() public {
        deal(USR, clientAddress, 10000e18);

        uint256 assetBalanceBefore = IERC20(USR).balanceOf(clientAddress);

        _doDeposit();

        uint256 assetBalanceAfter1 = IERC20(USR).balanceOf(clientAddress);
        assertEq(assetBalanceBefore - assetBalanceAfter1, DepositAmount);

        _doDeposit();

        uint256 assetBalanceAfter2 = IERC20(USR).balanceOf(clientAddress);
        assertEq(assetBalanceAfter1 - assetBalanceAfter2, DepositAmount);

        _doDeposit();
        _doDeposit();

        uint256 assetBalanceAfterAllDeposits = IERC20(USR).balanceOf(clientAddress);

        _doWithdraw(10);

        uint256 assetBalanceAfterWithdraw1 = IERC20(USR).balanceOf(clientAddress);

        assertApproxEqAbs(assetBalanceAfterWithdraw1 - assetBalanceAfterAllDeposits, DepositAmount * 4 / 10, 1);

        _doWithdraw(5);
        _doWithdraw(3);
        _doWithdraw(2);
        _doWithdraw(1);

        uint256 assetBalanceAfterAllWithdrawals = IERC20(USR).balanceOf(clientAddress);

        uint256 profit = 0;
        assertApproxEqAbs(assetBalanceAfterAllWithdrawals, assetBalanceBefore + profit, 1);
    }

    function test_Resolv_profitSplit_Mainnet() public {
        deal(USR, clientAddress, 100e18);

        uint256 clientAssetBalanceBefore = IERC20(USR).balanceOf(clientAddress);
        uint256 p2pAssetBalanceBefore = IERC20(USR).balanceOf(P2pTreasury);

        _doDeposit();

        uint256 shares = IERC20Rebasing(stUSR).sharesOf(proxyAddress);
        uint256 assetsInResolvBefore = IERC20Rebasing(stUSR).convertToUnderlyingToken(shares);

        _forward(10000000);

        uint256 yieldAmount = 5e17;
        deal(USR, stUSR, IERC20(USR).balanceOf(stUSR) + yieldAmount);

        uint256 assetsInResolvAfter = IERC20Rebasing(stUSR).convertToUnderlyingToken(shares);
        uint256 profit = assetsInResolvAfter - assetsInResolvBefore;

        _doWithdraw(1);

        uint256 clientAssetBalanceAfter = IERC20(USR).balanceOf(clientAddress);
        uint256 p2pAssetBalanceAfter = IERC20(USR).balanceOf(P2pTreasury);
        uint256 clientBalanceChange = clientAssetBalanceAfter - clientAssetBalanceBefore;
        uint256 p2pBalanceChange = p2pAssetBalanceAfter - p2pAssetBalanceBefore;
        uint256 sumOfBalanceChanges = clientBalanceChange + p2pBalanceChange;

        assertApproxEqAbs(sumOfBalanceChanges, profit, 1);

        uint256 clientBasisPointsDeFacto = clientBalanceChange * 10_000 / sumOfBalanceChanges;
        uint256 p2pBasisPointsDeFacto = p2pBalanceChange * 10_000 / sumOfBalanceChanges;

        assertApproxEqAbs(ClientBasisPoints, clientBasisPointsDeFacto, 1);
        assertApproxEqAbs(10_000 - ClientBasisPoints, p2pBasisPointsDeFacto, 1);
    }

    function test_withdrawUSRAccruedRewards_byP2pOperator_Mainnet() public {
        // Simulate initial deposit to create some rewards later
        deal(USR, clientAddress, 100e18);
        _doDeposit();

        // Simulate time passing to accrue rewards
        _forward(10000000);

        // Simulate yield by dealing USR directly to the stUSR contract
        // This increases the USR backing of stUSR, making the proxy's stUSR worth more
        uint256 yieldAmount = 5e18;
        deal(USR, stUSR, IERC20(USR).balanceOf(stUSR) + yieldAmount);

        // Verify that accrued rewards are now positive
        int256 accruedRewards = P2pResolvProxy(proxyAddress).calculateAccruedRewardsUSR();
        assertGt(accruedRewards, 0, "No accrued rewards to withdraw");

        // Withdraw accrued rewards as P2pOperator
        vm.startPrank(p2pOperatorAddress);
        uint256 treasuryBalanceBefore = IERC20(USR).balanceOf(P2pTreasury);

        // Expect P2pOperator can call this function, no revert
        P2pResolvProxy(proxyAddress).withdrawUSRAccruedRewards();

        uint256 treasuryBalanceAfter = IERC20(USR).balanceOf(P2pTreasury);
        assertGt(treasuryBalanceAfter, treasuryBalanceBefore, "Treasury did not receive accrued rewards");

        vm.stopPrank();
    }

    function test_DoubleFeeCollectionBug_OperatorThenClientWithdraw_USR() public {
        deal(USR, clientAddress, 100e18);
        _doDeposit();

        _forward(1_000_000);

        uint256 simulatedYield = 5e18;
        deal(USR, stUSR, IERC20(USR).balanceOf(stUSR) + simulatedYield);

        vm.startPrank(p2pOperatorAddress);
        uint256 treasuryBeforeRewards = IERC20(USR).balanceOf(P2pTreasury);
        P2pResolvProxy(proxyAddress).withdrawUSRAccruedRewards();
        vm.stopPrank();

        uint256 clientAfterRewards = IERC20(USR).balanceOf(clientAddress);
        uint256 treasuryAfterRewards = IERC20(USR).balanceOf(P2pTreasury);

        vm.startPrank(clientAddress);
        P2pResolvProxy(proxyAddress).withdrawAllUSR();
        vm.stopPrank();

        uint256 clientPrincipalReceived = IERC20(USR).balanceOf(clientAddress) - clientAfterRewards;
        uint256 treasuryPrincipalGain = IERC20(USR).balanceOf(P2pTreasury) - treasuryAfterRewards;

        assertApproxEqAbs(clientPrincipalReceived, DepositAmount, 1, "client principal received");
        assertLe(treasuryPrincipalGain, 1, "treasury gained extra");

        // Ensure operator withdrawal actually moved some yield
        assertGt(treasuryAfterRewards - treasuryBeforeRewards, 0, "treasury did not collect yield");
    }

    function test_withdrawUSRAccruedRewards_revertsForNonOperator_Mainnet() public {
        // First deploy and initialize the proxy by doing a deposit
        deal(USR, clientAddress, 100e18);
        _doDeposit();

        // Add some simulated yield by dealing USR to stUSR contract
        uint256 yieldAmount = 5e18;
        deal(USR, stUSR, IERC20(USR).balanceOf(stUSR) + yieldAmount);

        // Attempt calling as client - should revert
        vm.startPrank(clientAddress);
        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__NotP2pOperator.selector, clientAddress));
        P2pResolvProxy(proxyAddress).withdrawUSRAccruedRewards();
        vm.stopPrank();

        // Attempt calling as a random address - should revert
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__NotP2pOperator.selector, nobody));
        P2pResolvProxy(proxyAddress).withdrawUSRAccruedRewards();
        vm.stopPrank();
    }

    function test_transferP2pSigner_Mainnet() public {
        vm.startPrank(nobody);
        vm.expectRevert(abi.encodeWithSelector(P2pOperator.P2pOperator__UnauthorizedAccount.selector, nobody));
        factory.transferP2pSigner(nobody);

        address oldSigner = factory.getP2pSigner();
        assertEq(oldSigner, p2pSignerAddress);

        vm.startPrank(p2pOperatorAddress);
        factory.transferP2pSigner(nobody);

        address newSigner = factory.getP2pSigner();
        assertEq(newSigner, nobody);
    }

    function test_clientBasisPointsGreaterThan10000_Mainnet() public {
        uint96 invalidBasisPoints = 10001;

        vm.startPrank(clientAddress);
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            invalidBasisPoints,
            SigDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(P2pYieldProxy__InvalidClientBasisPoints.selector, invalidBasisPoints));
        factory.deposit(
            USR,
            DepositAmount,
            invalidBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
    }

    function test_zeroAddressAsset_Mainnet() public {
        vm.startPrank(clientAddress);

        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(P2pResolvProxy__AssetNotSupported.selector, address(0)));
        factory.deposit(
            address(0),
            0,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
    }

    function test_zeroAssetAmount_Mainnet() public {
        vm.startPrank(clientAddress);

        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.expectRevert(P2pYieldProxy__ZeroAssetAmount.selector);
        factory.deposit(
            USR,
            0,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
    }

    function test_depositDirectlyOnProxy_Mainnet() public {
        vm.startPrank(clientAddress);

        // Add this line to give initial tokens to the client
        deal(USR, clientAddress, DepositAmount);

        // Add this line to approve tokens for proxyAddress
        IERC20(USR).safeApprove(proxyAddress, DepositAmount);

        // Create proxy first via factory
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        factory.deposit(
            USR,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );

        // Now try to call deposit directly on the proxy
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxy__NotFactoryCalled.selector,
                clientAddress,
                address(factory)
            )
        );
        P2pResolvProxy(proxyAddress).deposit(
            USR,
            DepositAmount
        );
    }

    function test_initializeDirectlyOnProxy_Mainnet() public {
        // Create the proxy first since we need a valid proxy address to test with
        proxyAddress = factory.predictP2pYieldProxyAddress(clientAddress, ClientBasisPoints);
        P2pResolvProxy proxy = P2pResolvProxy(proxyAddress);

        vm.startPrank(clientAddress);

        // Add this line to give initial tokens to the client
        deal(USR, clientAddress, DepositAmount);

        // Add this line to approve tokens for Permit2
        IERC20(USR).safeApprove(proxyAddress, DepositAmount);

        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        // This will create the proxy
        factory.deposit(
            USR,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );

        // Now try to initialize it directly
        vm.expectRevert("Initializable: contract is already initialized");
        proxy.initialize(
            clientAddress,
            ClientBasisPoints
        );
        vm.stopPrank();
    }

    function test_withdrawOnProxyOnlyCallableByClient_Mainnet() public {
        // Create proxy and do initial deposit
        deal(USR, clientAddress, DepositAmount);
        vm.startPrank(clientAddress);
        IERC20(USR).safeApprove(proxyAddress, DepositAmount);
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        factory.deposit(
            USR,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();

        // Try to withdraw as non-client
        vm.startPrank(nobody);
        P2pResolvProxy proxy = P2pResolvProxy(proxyAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxy__NotClientCalled.selector,
                nobody,        // _msgSender (the nobody address trying to call)
                clientAddress  // _actualClient (the actual client address)
            )
        );
        proxy.withdrawAllUSR();
        vm.stopPrank();
    }

    function test_getP2pLendingProxyFactory__ZeroP2pSignerAddress_Mainnet() public {
        vm.startPrank(p2pOperatorAddress);
        vm.expectRevert(P2pYieldProxyFactory__ZeroP2pSignerAddress.selector);
        factory.transferP2pSigner(address(0));
        vm.stopPrank();
    }

    function test_getHashForP2pSigner_Mainnet() public view {
        bytes32 expectedHash = keccak256(abi.encode(
            clientAddress,
            ClientBasisPoints,
            SigDeadline,
            address(factory),
            block.chainid
        ));

        bytes32 actualHash = factory.getHashForP2pSigner(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        assertEq(actualHash, expectedHash);
    }

    function test_supportsInterface_Mainnet() public view {
        // Test IP2pLendingProxyFactory interface support
        bool supportsP2pLendingProxyFactory = factory.supportsInterface(type(IP2pYieldProxyFactory).interfaceId);
        assertTrue(supportsP2pLendingProxyFactory);

        // Test IERC165 interface support
        bool supportsERC165 = factory.supportsInterface(type(IERC165).interfaceId);
        assertTrue(supportsERC165);

        // Test non-supported interface
        bytes4 nonSupportedInterfaceId = bytes4(keccak256("nonSupportedInterface()"));
        bool supportsNonSupported = factory.supportsInterface(nonSupportedInterfaceId);
        assertFalse(supportsNonSupported);
    }

    function test_p2pSignerSignatureExpired_Mainnet() public {
        // Add this line to give tokens to the client before attempting deposit
        deal(USR, clientAddress, DepositAmount);

        vm.startPrank(clientAddress);
        IERC20(USR).safeApprove(proxyAddress, DepositAmount);

        // Get p2p signer signature with expired deadline
        uint256 expiredDeadline = block.timestamp - 1;
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            expiredDeadline
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                P2pYieldProxyFactory__P2pSignerSignatureExpired.selector,
                expiredDeadline
            )
        );

        factory.deposit(
            USR,
            DepositAmount,
            ClientBasisPoints,
            expiredDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function test_invalidP2pSignerSignature_Mainnet() public {
        // Add this line to give tokens to the client before attempting deposit
        deal(USR, clientAddress, DepositAmount);

        vm.startPrank(clientAddress);
        IERC20(USR).safeApprove(proxyAddress, DepositAmount);

        // Create an invalid signature by using a different private key
        uint256 wrongPrivateKey = 0x12345; // Some random private key
        bytes32 messageHash = ECDSA.toEthSignedMessageHash(
            factory.getHashForP2pSigner(
                clientAddress,
                ClientBasisPoints,
                SigDeadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, messageHash);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(P2pYieldProxyFactory__InvalidP2pSignerSignature.selector);

        factory.deposit(
            USR,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            invalidSignature
        );
        vm.stopPrank();
    }

    function test_viewFunctions_Mainnet() public {
        // Add this line to give tokens to the client before attempting deposit
        deal(USR, clientAddress, DepositAmount);

        vm.startPrank(clientAddress);

        // Add this line to approve tokens for Permit2
        IERC20(USR).safeApprove(proxyAddress, DepositAmount);

        // Create proxy first via factory
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        factory.deposit(
            USR,
            DepositAmount,
            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );

        P2pResolvProxy proxy = P2pResolvProxy(proxyAddress);
        assertEq(proxy.getFactory(), address(factory));
        assertEq(proxy.getP2pTreasury(), P2pTreasury);
        assertEq(proxy.getClient(), clientAddress);
        assertEq(proxy.getClientBasisPoints(), ClientBasisPoints);
        assertEq(proxy.getTotalDeposited(USR), DepositAmount);
        assertEq(factory.getP2pSigner(), p2pSignerAddress);
        assertEq(factory.predictP2pYieldProxyAddress(clientAddress, ClientBasisPoints), proxyAddress);
    }

    function test_acceptP2pOperator_Mainnet() public {
        // Initial state check
        assertEq(factory.getP2pOperator(), p2pOperatorAddress);

        // Only operator can initiate transfer
        vm.startPrank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pOperator.P2pOperator__UnauthorizedAccount.selector,
                nobody
            )
        );
        factory.transferP2pOperator(nobody);
        vm.stopPrank();

        // Operator initiates transfer
        address newOperator = makeAddr("newOperator");
        vm.startPrank(p2pOperatorAddress);
        factory.transferP2pOperator(newOperator);

        // Check pending operator is set
        assertEq(factory.getPendingP2pOperator(), newOperator);
        // Check current operator hasn't changed yet
        assertEq(factory.getP2pOperator(), p2pOperatorAddress);
        vm.stopPrank();

        // Wrong address cannot accept transfer
        vm.startPrank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pOperator.P2pOperator__UnauthorizedAccount.selector,
                nobody
            )
        );
        factory.acceptP2pOperator();
        vm.stopPrank();

        // New operator accepts transfer
        vm.startPrank(newOperator);
        factory.acceptP2pOperator();

        // Check operator was updated
        assertEq(factory.getP2pOperator(), newOperator);
        // Check pending operator was cleared
        assertEq(factory.getPendingP2pOperator(), address(0));
        vm.stopPrank();

        // Old operator can no longer call operator functions
        vm.startPrank(p2pOperatorAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                P2pOperator.P2pOperator__UnauthorizedAccount.selector,
                p2pOperatorAddress
            )
        );
        factory.transferP2pOperator(p2pOperatorAddress);
        vm.stopPrank();
    }

    function _getP2pSignerSignature(
        address _clientAddress,
        uint96 _clientBasisPoints,
        uint256 _sigDeadline
    ) private view returns(bytes memory) {
        // p2p signer signing
        bytes32 hashForP2pSigner = factory.getHashForP2pSigner(
            _clientAddress,
            _clientBasisPoints,
            _sigDeadline
        );
        bytes32 ethSignedMessageHashForP2pSigner = ECDSA.toEthSignedMessageHash(hashForP2pSigner);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(p2pSignerPrivateKey, ethSignedMessageHashForP2pSigner);
        bytes memory p2pSignerSignature = abi.encodePacked(r2, s2, v2);
        return p2pSignerSignature;
    }

    function _doDeposit() private {
        bytes memory p2pSignerSignature = _getP2pSignerSignature(
            clientAddress,
            ClientBasisPoints,
            SigDeadline
        );

        vm.startPrank(clientAddress);
        if (IERC20(USR).allowance(clientAddress, proxyAddress) == 0) {
            IERC20(USR).safeApprove(proxyAddress, type(uint256).max);
        }
        factory.deposit(
            USR,
            DepositAmount,

            ClientBasisPoints,
            SigDeadline,
            p2pSignerSignature
        );
        vm.stopPrank();
    }

    function _doWithdraw(uint256 denominator) private {
        uint256 sharesBalance = IERC20Rebasing(stUSR).sharesOf(proxyAddress);
        uint256 sharesToWithdraw = sharesBalance / denominator;
        uint256 underlyingToWithdraw = IERC20Rebasing(stUSR).convertToUnderlyingToken(sharesToWithdraw);

        vm.startPrank(clientAddress);
        P2pResolvProxy(proxyAddress).withdrawUSR(underlyingToWithdraw);
        vm.stopPrank();
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * 13);
    }
}
