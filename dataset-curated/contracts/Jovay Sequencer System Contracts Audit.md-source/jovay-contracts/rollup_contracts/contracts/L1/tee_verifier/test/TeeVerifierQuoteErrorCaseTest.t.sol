// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/PCCSSetupBase.sol";
import "./utils/Constants.sol";
import {Ownable} from "solady/auth/Ownable.sol";
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

    function testErrorVersionQuoteShouldFail() public {
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
        vm.expectRevert(abi.encodeWithSelector(TEECacheVerifier.UnsupportedQuoteVersion.selector));
        (uint32 success,) = proxy.verifyProof(errorVersionQuote);

        assertEq(success, 0);
    }

    function testV3QuoteWithWrongKeyShouldFail() public {
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
        cacheVerifier.initializeCache(v5QuoteKey);

        vm.stopPrank();

        vm.prank(admin);
        (uint32 success,) = proxy.verifyProof(v3QuoteWithWrongKey);

        assertEq(success, 1);
    }

    function testUserDeleteCacheShouldFail() public {
        // Test user cannot delete key
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        cacheVerifier.deleteKey(v3QuoteKey);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        cacheVerifier.clearupAllKey();
        vm.stopPrank();
    }

    function testDeleteUnexistedCacheShouldFail() public {
        // Test user cannot delete key
        vm.startPrank(admin);
        assert(!cacheVerifier.isInitialized(v3QuoteKey));
        vm.expectRevert(abi.encodeWithSelector(TEECacheVerifier.KeyNotInitialized.selector));
        cacheVerifier.deleteKey(v3QuoteKey);
        vm.stopPrank();
    }
}
