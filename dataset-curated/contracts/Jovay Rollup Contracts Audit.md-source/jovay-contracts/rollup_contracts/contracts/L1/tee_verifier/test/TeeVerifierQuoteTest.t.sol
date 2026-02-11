// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/PCCSSetupBase.sol";
import "./utils/Constants.sol";
import {AutomataDcapAttestationFee} from "dcap-attestation/AutomataDcapAttestationFee.sol";
import {V3QuoteVerifier} from "dcap-attestation/verifiers/V3QuoteVerifier.sol";
import {V5QuoteVerifier} from "dcap-attestation/verifiers/V5QuoteVerifier.sol";
import {BytesUtils} from "dcap-attestation/utils/BytesUtils.sol";
import "../src/DcapAttestationRouter.sol";
import "../src/TEEVerifierProxy.sol";
import "../src/TEECacheVerifier.sol";
import "../script/utils/DaimoP256Verifier.sol";

contract TEEQuoteVerifyTest is PCCSSetupBase {
    using BytesUtils for bytes;

    AutomataDcapAttestationFee attestation;
    PCCSRouter pccsRouter;
    DcapAttestationRouter router;
    MeasurementDao mrDao;
    TEECacheVerifier cacheVerifier;
    TEEVerifierProxy proxy;

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
        DaimoP256Verifier p256verifier = new DaimoP256Verifier();
        cacheVerifier = new TEECacheVerifier(address(p256verifier));

        vm.stopPrank();
    }

    function testSGXQuoteV3NoCache() public {
        vm.warp(1749112940);

        V3QuoteVerifier quoteVerifier;

        vm.startPrank(admin);

        router = new DcapAttestationRouter(address(attestation), address(mrDao), address(cacheVerifier));
        router.setConfig(address(attestation), address(mrDao), false, address(cacheVerifier), false);

        cacheVerifier.setAuthorized(address(router), true);

        proxy = new TEEVerifierProxy(address(router));
        router.setAuthorized(address(proxy), true);

        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        // collateral upserts
        qeIdDaoUpsert(3, qeIdPathV3);
        fmspcTcbDaoUpsert(tcbInfoPathV3);

        quoteVerifier = new V3QuoteVerifier(P256_VERIFIER, address(pccsRouter));
        attestation.setQuoteVerifier(address(quoteVerifier));
        pccsRouter.setAuthorized(address(quoteVerifier), true);

        vm.stopPrank();

        vm.prank(admin);
        (uint32 success,) = proxy.verifyProof(sampleQuoteV3);

        assertEq(success, 0);
    }

    function testTDXQuoteV5NoCache() public {
        vm.warp(1749112940);

        V5QuoteVerifier quoteVerifier;

        vm.startPrank(admin);

        router = new DcapAttestationRouter(address(attestation), address(mrDao), address(cacheVerifier));
        router.setConfig(address(attestation), address(mrDao), false, address(cacheVerifier), false);

        cacheVerifier.setAuthorized(address(router), true);

        proxy = new TEEVerifierProxy(address(router));
        router.setAuthorized(address(proxy), true);

        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        qeIdDaoUpsert(5, qeIdPathV5);
        fmspcTcbDaoUpsert(tcbInfoPathV5);

        quoteVerifier = new V5QuoteVerifier(P256_VERIFIER, address(pccsRouter));
        attestation.setQuoteVerifier(address(quoteVerifier));
        pccsRouter.setAuthorized(address(quoteVerifier), true);

        vm.stopPrank();

        vm.prank(admin);
        (uint32 success,) = proxy.verifyProof(sampleQuoteV5);

        assertEq(success, 0);
    }

    function testSGXQuoteV3WithCache() public {
        vm.warp(1749112940);

        V3QuoteVerifier quoteVerifier;

        vm.startPrank(admin);
        router = new DcapAttestationRouter(address(attestation), address(mrDao), address(cacheVerifier));
        router.setConfig(address(attestation), address(mrDao), false, address(cacheVerifier), true);

        cacheVerifier.setAuthorized(address(router), true);

        proxy = new TEEVerifierProxy(address(router));
        router.setAuthorized(address(proxy), true);

        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        qeIdDaoUpsert(3, qeIdPathV3);
        fmspcTcbDaoUpsert(tcbInfoPathV3);

        quoteVerifier = new V3QuoteVerifier(P256_VERIFIER, address(pccsRouter));
        attestation.setQuoteVerifier(address(quoteVerifier));
        pccsRouter.setAuthorized(address(quoteVerifier), true);

        vm.stopPrank();

        vm.startPrank(admin);
        (uint32 success,) = proxy.verifyProof(sampleQuoteV3);

        assertEq(success, 0);

        assert(cacheVerifier.isInitialized(v3QuoteKey));
        (success,) = proxy.verifyProof(sampleQuoteV3);

        assertEq(success, 0);
        vm.stopPrank();
    }

    function testSGXQuoteV5WithCache() public {
        vm.warp(1749112940);

        V5QuoteVerifier quoteVerifier;

        vm.startPrank(admin);

        router = new DcapAttestationRouter(address(attestation), address(mrDao), address(cacheVerifier));
        router.setConfig(address(attestation), address(mrDao), false, address(cacheVerifier), true);

        cacheVerifier.setAuthorized(address(router), true);

        proxy = new TEEVerifierProxy(address(router));
        router.setAuthorized(address(proxy), true);

        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        qeIdDaoUpsert(5, qeIdPathV5);
        fmspcTcbDaoUpsert(tcbInfoPathV5);

        quoteVerifier = new V5QuoteVerifier(P256_VERIFIER, address(pccsRouter));
        attestation.setQuoteVerifier(address(quoteVerifier));
        pccsRouter.setAuthorized(address(quoteVerifier), true);

        vm.stopPrank();

        vm.startPrank(admin);
        (uint32 success,) = proxy.verifyProof(sampleQuoteV5);

        assertEq(success, 0);

        assert(cacheVerifier.isInitialized(v5QuoteKey));
        (success,) = proxy.verifyProof(sampleQuoteV5);
        vm.stopPrank();

        assertEq(success, 0);
    }

    function testDeleteCache() public {
        vm.warp(1749112940);

        V3QuoteVerifier quoteVerifier;

        vm.startPrank(admin);
        router = new DcapAttestationRouter(address(attestation), address(mrDao), address(cacheVerifier));
        router.setConfig(address(attestation), address(mrDao), false, address(cacheVerifier), true);

        cacheVerifier.setAuthorized(address(router), true);

        proxy = new TEEVerifierProxy(address(router));
        router.setAuthorized(address(proxy), true);

        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        qeIdDaoUpsert(3, qeIdPathV3);
        fmspcTcbDaoUpsert(tcbInfoPathV3);

        quoteVerifier = new V3QuoteVerifier(P256_VERIFIER, address(pccsRouter));
        attestation.setQuoteVerifier(address(quoteVerifier));
        pccsRouter.setAuthorized(address(quoteVerifier), true);

        (uint32 success,) = proxy.verifyProof(sampleQuoteV3);
        assertEq(success, 0);

        assert(cacheVerifier.isInitialized(v3QuoteKey));
        cacheVerifier.deleteKey(v3QuoteKey);
        assert(!cacheVerifier.isInitialized(v3QuoteKey));

        vm.stopPrank();
    }

    function testClearupAllCache() public {
        // Test admin can clear all cache
        vm.startPrank(admin);
        cacheVerifier.clearupAllKey();
        vm.stopPrank();
    }

    function testMRTDtoVerifyV5() public {
        vm.warp(1749112940);

        V5QuoteVerifier quoteVerifier;

        vm.startPrank(admin);

        mrDao.clearup_rtMr();
        mrDao.clearup_mrtd();
        mrDao.add_rtMr(rtmr3_1);
        mrDao.add_mrtd(mrtd_1);

        router = new DcapAttestationRouter(address(attestation), address(mrDao), address(cacheVerifier));
        router.setConfig(address(attestation), address(mrDao), true, address(cacheVerifier), false);

        router.enableVerifyMRTD();

        cacheVerifier.setAuthorized(address(router), true);

        proxy = new TEEVerifierProxy(address(router));
        router.setAuthorized(address(proxy), true);

        pcsDao.upsertPckCrl(CA.PLATFORM, platformCrlDer);

        qeIdDaoUpsert(5, qeIdPathV5);
        fmspcTcbDaoUpsert(tcbInfoPathV5);

        quoteVerifier = new V5QuoteVerifier(P256_VERIFIER, address(pccsRouter));
        attestation.setQuoteVerifier(address(quoteVerifier));
        pccsRouter.setAuthorized(address(quoteVerifier), true);

        vm.stopPrank();

        vm.prank(admin);
        (uint32 success,) = proxy.verifyProof(sampleQuote5_1);

        assertEq(success, 0);
    }
}
