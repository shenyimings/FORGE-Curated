// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/PCCSSetupBase.sol";

import {AutomataDcapAttestationFee} from "dcap-attestation/AutomataDcapAttestationFee.sol";
import {V3QuoteVerifier} from "dcap-attestation/verifiers/V3QuoteVerifier.sol";
import {V5QuoteVerifier} from "dcap-attestation/verifiers/V5QuoteVerifier.sol";

import {BytesUtils} from "dcap-attestation/utils/BytesUtils.sol";
import "../src/DcapAttestationRouter.sol";
import "../src/TEEVerifierProxy.sol";
import "../src/TEECacheVerifier.sol";
import "../script/utils/DaimoP256Verifier.sol";

contract TEEVerifyTest is PCCSSetupBase {
    using BytesUtils for bytes;

    uint256 constant EXPECTED_GAS = 5_000_000;
    uint256 constant GAS_PRICE_WEI = 1_000_000_000; // 1 Gwei
    uint16 constant CONFIGURED_BP = 1_000; // 10 %
    uint16 constant MAX_BP = 10_000;

    // TODO: fill for test
    bytes public sampleQuote5_1 =
        hex"";
    bytes public sampleQuote5_2 =
        hex"";
    bytes public sampleQuote5_3 =
        hex"";
    bytes public sampleQuote3_1 =
        hex"";
    bytes public sampleQuote3_2 =
        hex"";
    bytes public sampleQuote3_3 =
        hex"";

    AutomataDcapAttestationFee attestation;
    PCCSRouter pccsRouter;
    DcapAttestationRouter router;
    MeasurementDao mrDao;
    TEEVerifierProxy proxy;
    DaimoP256Verifier p256verifier;
    TEECacheVerifier cacheVerifier;

    address user = address(69);

    function setUp() public override {
        super.setUp();

        vm.deal(user, 1 ether);
        vm.txGasPrice(GAS_PRICE_WEI);

        vm.startPrank(admin);

        // PCCS Setup
        pccsRouter = setupPccsRouter(admin);
        pcsDaoUpserts();

        // DCAP Contract Deployment
        attestation = new AutomataDcapAttestationFee(admin);

        mrDao = new MeasurementDao();

        //TEECacheVerifier Deployment
        p256verifier = new DaimoP256Verifier();
        cacheVerifier = new TEECacheVerifier(address(p256verifier));

        router = new DcapAttestationRouter(address(attestation), address(mrDao), address(cacheVerifier));
        router.setConfig(address(attestation), address(mrDao), false, address(cacheVerifier), true);

        proxy = new TEEVerifierProxy(address(router));
        router.setAuthorized(address(proxy), true);

        cacheVerifier.setAuthorized(address(router), true);

        vm.stopPrank();

        V5QuoteVerifier quoteVerifier;
        vm.startPrank(admin);

        // collateral upserts
        string memory tcbInfoPath = "/script/assets/20250514/tcbinfo_v4.json";
        string memory qeIdPath = "/script/assets/20250514/qeid_v4.json";
        qeIdDaoUpsert(5, qeIdPath);
        fmspcTcbDaoUpsert(tcbInfoPath);

        // deploy and configure QuoteV3Verifier on the Attestation contract
        quoteVerifier = new V5QuoteVerifier(P256_VERIFIER, address(pccsRouter));
        attestation.setQuoteVerifier(address(quoteVerifier));
        pccsRouter.setAuthorized(address(quoteVerifier), true);

        vm.stopPrank();
    }

    bytes constant platformCrlDer =
        hex""; // TODO: fill for test

    /**
     * TEEVerifierProxy Auth
     */
    function testProxyEnableCallerRestrictionAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        proxy.enableCallerRestriction();
    }

    function testProxydisableCallerRestrictionAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        proxy.disableCallerRestriction();
    }

    function testProxySetConfigAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        proxy.setConfig(address(router));
    }

    function testProxySetAuthorizedAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        proxy.setAuthorized(address(router), true);
    }

    function testProxyVerifyAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.startPrank(admin);
        proxy.enableCallerRestriction();
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TEEVerifierProxy.Forbidden.selector));
        (uint32 success,) = proxy.verifyProof(sampleQuote5_3);
    }

    function testProxyVerifyAuthWithRevert_user_unauthorized() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.startPrank(admin);
        proxy.enableCallerRestriction();

        proxy.setAuthorized(user, false);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TEEVerifierProxy.Forbidden.selector));
        (uint32 success,) = proxy.verifyProof(sampleQuote5_3);
    }

    function testProxyVerifyAuth() public {
        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.startPrank(admin);
        proxy.enableCallerRestriction();

        proxy.setAuthorized(user, true);
        cacheVerifier.setAuthorized(address(router), true);
        vm.stopPrank();

        vm.prank(user);
        (uint32 success,) = proxy.verifyProof(sampleQuote5_3);
        assertEq(success, 0);
    }

    /**
     * DcapAttestationRouter Auth
     */
    function testRouterEnableCallerRestrictionAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        router.enableCallerRestriction();
    }

    function testRouterdisableCallerRestrictionAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        router.disableCallerRestriction();
    }

    function testRouterSetConfigAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        // 111 is mock address
        router.setConfig(address(111), address(111), true, address(111), true);
    }

    function testRouterSetAuthorizedAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        router.setAuthorized(address(proxy), true);
    }

    function testRouterVerifyAuthWithRevert_user_unauthorized() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.startPrank(admin);
        proxy.enableCallerRestriction();

        proxy.setAuthorized(address(proxy), false);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(DcapAttestationRouter.Forbidden.selector));
        (uint32 success,) = proxy.verifyProof(sampleQuote5_3);
    }

    function testRouterVerifyAuth() public {
        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.startPrank(admin);
        proxy.enableCallerRestriction();

        proxy.setAuthorized(user, true);
        vm.stopPrank();

        vm.prank(user);
        (uint32 success,) = proxy.verifyProof(sampleQuote5_3);
        assertEq(success, 0);
    }

    /**
     * MeasurementDao Auth
     */
    function testAddRTMRAuthwithRevert() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        bytes memory rtmr3_1 =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        mrDao.add_rtMr(rtmr3_1);
    }

    function testAddMrEnclaveAuthWithRevert() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        mrDao.add_mr_enclave(bytes32(0), bytes32(0));
        vm.stopPrank();
    }

    function testDeleteMrEnclaveAuthWithRevert() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        mrDao.delete_mr_enclave(bytes32(0));
        vm.stopPrank();
    }

    function testGetMrEnclaveAuthWithRevert() public {
        vm.startPrank(user);
        // vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        mrDao.get_mr_enclave();
        vm.stopPrank();
    }

    function testClearUpMrEnclaveAuthWithRevert() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        mrDao.clearup_mr_enclave();
        vm.stopPrank();
    }

    function testAddRtmrAuthWithRevert() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        bytes memory rtmr =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        mrDao.add_rtMr(rtmr);
        vm.stopPrank();
    }

    function testDeleteRtmrAuthWithRevert() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        bytes memory rtmr =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        mrDao.delete_rtMr(rtmr);
        vm.stopPrank();
    }

    function testGetRtmrAuthWithRevert() public {
        vm.startPrank(user);
        // vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        mrDao.get_rtMr();
        vm.stopPrank();
    }

    function testClearUpRtmrAuthWithRevert() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        mrDao.clearup_rtMr();
        vm.stopPrank();
    }

    /**
     * TeeCacheVerifier Auth Test
     */
    function testCacheEnableCallerRestrictionAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        cacheVerifier.enableCallerRestriction();
    }

    function testCachedisableCallerRestrictionAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        cacheVerifier.disableCallerRestriction();
    }

    function testCacheSetAuthorizedAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        cacheVerifier.setAuthorized(address(router), true);
    }

    function testCacheDeleteKeyAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        bytes memory rtmr =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        cacheVerifier.deleteKey(rtmr);
    }

    function testCacheClearupKeyAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        cacheVerifier.clearupAllKey();
    }

    function testCacheGetAllKeyAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);

        // vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        cacheVerifier.getAllKey();
    }

    function testVerifyAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TEECacheVerifier.Forbidden.selector));

        bytes memory tmp =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        cacheVerifier.verifyAndAttestOnChain(tmp, tmp, tmp, 5);
    }

    function testInitCacheAuthWithRevert() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TEECacheVerifier.Forbidden.selector));

        bytes memory cache =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        cacheVerifier.initializeCache(cache);
    }

    function testVerifyAuthWithRevert_user_unauthorized() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.startPrank(admin);
        proxy.enableCallerRestriction();

        proxy.setAuthorized(address(user), false);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TEECacheVerifier.Forbidden.selector));
        bytes memory tmp =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        cacheVerifier.verifyAndAttestOnChain(tmp, tmp, tmp, 5);
    }

    function testInitCacheAuthWithRevert_user_unauthorized() public {
        // pinned June 15th,2024 Midnight UTC
        // bypassing expiry errors
        vm.warp(1749112940);

        vm.startPrank(admin);
        proxy.enableCallerRestriction();

        proxy.setAuthorized(address(user), false);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TEECacheVerifier.Forbidden.selector));

        bytes memory cache =
            hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        cacheVerifier.initializeCache(cache);
    }
}
