// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import "../src/DcapAttestationRouter.sol";
import "../src/TEEVerifierProxy.sol";
import "../src/TEECacheVerifier.sol";
import "./utils/DaimoP256Verifier.sol";

import "dcap-attestation/AutomataDcapAttestationFee.sol";
import "dcap-attestation/verifiers/V3QuoteVerifier.sol";
import "dcap-attestation/verifiers/V4QuoteVerifier.sol";
import "dcap-attestation/verifiers/V5QuoteVerifier.sol";

import {AutomataDaoStorage} from "on-chain-pccs/automata_pccs/shared/AutomataDaoStorage.sol";
import {AutomataFmspcTcbDao} from "on-chain-pccs/automata_pccs/AutomataFmspcTcbDao.sol";
import {AutomataEnclaveIdentityDao} from "on-chain-pccs/automata_pccs/AutomataEnclaveIdentityDao.sol";
import {AutomataPcsDao} from "on-chain-pccs/automata_pccs/AutomataPcsDao.sol";
import {AutomataPckDao} from "on-chain-pccs/automata_pccs/AutomataPckDao.sol";

import {EnclaveIdentityHelper} from "on-chain-pccs/helpers/EnclaveIdentityHelper.sol";
import {FmspcTcbHelper} from "on-chain-pccs/helpers/FmspcTcbHelper.sol";
import {PCKHelper} from "on-chain-pccs/helpers/PCKHelper.sol";
import {X509CRLHelper} from "on-chain-pccs/helpers/X509CRLHelper.sol";

import {PCCSRouter} from "dcap-attestation/PCCSRouter.sol";

contract DeployAll is Script {
    uint256 deployerKey = uint256(vm.envBytes32("PRIVATE_KEY"));
    address adminAccount = vm.envAddress("ADMIN_ADDRESS");

    string priority_gas_price = vm.envString("PRIORITY_GAS_PRICE");
    string max_gas_price = vm.envString("MAX_GAS_PRICE");
    string gas_limit = vm.envString("GAS_LIMIT");

    address x509CrlAddress = vm.envAddress("X509_CRL_HELPER");
    address x509Address = vm.envAddress("X509_HELPER");
    address enclaveIdentityHelperAddress = vm.envAddress("ENCLAVE_IDENTITY_HELPER");
    address fmspcTcbHelperAddress = vm.envAddress("FMSPC_TCB_HELPER");

    address pccsStorageAddr = vm.envAddress("PCCS_STORAGE");
    address pcsDaoAddr = vm.envAddress("PCS_DAO");
    address pckDaoAddr = vm.envAddress("PCK_DAO");
    address fmspcTcbDaoAddr = vm.envAddress("FMSPC_TCB_DAO");
    address enclaveIdDaoAddr = vm.envAddress("ENCLAVE_ID_DAO");

    address pccsRouterAddr = vm.envAddress("PCCS_ROUTER");
    address p256verifierAddr = vm.envAddress("P256_VERIFIER");

    address attestationAddr = vm.envAddress("DCAP_ATTESTATION");

    address verifierAddr = vm.envAddress("V3_VERIFIER");
    address verifier4Addr = vm.envAddress("V4_VERIFIER");
    address verifier5Addr = vm.envAddress("V5_VERIFIER");
    address routerAddr = vm.envAddress("DCAP_ATTESTATION_ROUTER");

    address mrAddr = vm.envAddress("MEASUREMENT_DAO");
    address proxyAddr = vm.envAddress("TEE_PROXY");
    address cacheVerifierAddr = vm.envAddress("CACHE_VERIFIER");

    modifier broadcastKey(uint256 key) {
        vm.startBroadcast(key);
        _;
        vm.stopBroadcast();

        _saveAddr2Env();
    }

    function deployAll() public {
        if (vm.envBool("TEST")) {
            console.log("[LOG] this is a test use specific timstamp");
            // vm.warp(1736748481);
        }

        // deploy helpers
        _deployEnclaveIdentityHelper();
        _deployFmspcTcbHelper();
        _deployPckHelper();
        _deployX509CrlHelper();

        // deploy p256 verifier
        _deployP256Verifier();

        // deploy dao
        _deployStorage();
        _deployPcs();
        _deployPck();
        _deployEnclaveIdDao();
        _deployFmspcTcbDao();

        // update pccs
        _updatePccsDao();

        // deploy dcap
        _deployPccsRouter();
        _deployVerifier();
        _deployCacheVerifier();
        _deployEntrypoint();
        _configVerifier();
        _deployDcapRouter();

        // set pccsRouter as pccsStorage authorized caller
        _setAuthorizedCaller();

        _configDcap();

        console.log("[LOG] EnclaveIdentityHelper: ", enclaveIdentityHelperAddress);
        console.log("[LOG] FmspcTcbHelper: ", fmspcTcbHelperAddress);
        console.log("[LOG] PCKHelper/X509Helper: ", x509Address);
        console.log("[LOG] X509CRLHelper: ", x509CrlAddress);

        console.log("[LOG] P256Verifier: ", p256verifierAddr);

        console.log("[LOG] AutomataDaoStorage: ", pccsStorageAddr);
        console.log("[LOG] AutomataEnclaveIdDao: ", enclaveIdDaoAddr);
        console.log("[LOG] AutomataFmspcTcbDao: ", fmspcTcbDaoAddr);
        console.log("[LOG] AutomataPckDao: ", pckDaoAddr);
        console.log("[LOG] AutomataPcsDao: ", pcsDaoAddr);

        console.log("[LOG] PCCSRouter: ", pccsRouterAddr);
        console.log("[LOG] VerifierV3: ", verifierAddr);
        console.log("[LOG] DcapEntryPoint: ", attestationAddr);
        console.log("[LOG] DcapRouter: ", routerAddr);

        _saveAddr2Env();
    }

    function configAll() public {
        // set pccsRouter as pccsStorage authorized caller
        pccsStorageAddr = vm.envAddress("PCCS_STORAGE");
        pccsRouterAddr = vm.envAddress("PCCS_ROUTER");
        // _setAuthorizedCaller();

        pcsDaoAddr = vm.envAddress("PCS_DAO");
        pckDaoAddr = vm.envAddress("PCK_DAO");
        fmspcTcbDaoAddr = vm.envAddress("FMSPC_TCB_DAO");
        enclaveIdDaoAddr = vm.envAddress("ENCLAVE_ID_DAO");

        _updatePccsDao();
    }

    function _saveAddr2Env() public {
        string memory content_1 = string.concat(
            "TEST=false",
            "\n",
            "RPC_URL=",
            vm.envString("RPC_URL"),
            "\n",
            "PRIVATE_KEY=",
            vm.envString("PRIVATE_KEY"),
            "\n",
            "ADMIN_ADDRESS=",
            vm.envString("ADMIN_ADDRESS"),
            "\n",
            "\n",
            "GAS_LIMIT=",
            vm.envString("GAS_LIMIT"),
            "\n",
            "PRIORITY_GAS_PRICE=",
            vm.envString("PRIORITY_GAS_PRICE"),
            "\n",
            "MAX_GAS_PRICE=",
            vm.envString("MAX_GAS_PRICE"),
            "\n"
        );

        string memory content_2 = string.concat(
            "\n",
            "ENCLAVE_IDENTITY_HELPER=",
            vm.toString(enclaveIdentityHelperAddress),
            "\n",
            "FMSPC_TCB_HELPER=",
            vm.toString(fmspcTcbHelperAddress),
            "\n",
            "X509_HELPER=",
            vm.toString(x509Address),
            "\n",
            "X509_CRL_HELPER=",
            vm.toString(x509CrlAddress),
            "\n",
            "P256_VERIFIER=",
            vm.toString(p256verifierAddr),
            "\n",
            "\n",
            "PCCS_STORAGE=",
            vm.toString(pccsStorageAddr),
            "\n",
            "ENCLAVE_ID_DAO=",
            vm.toString(enclaveIdDaoAddr),
            "\n",
            "FMSPC_TCB_DAO=",
            vm.toString(fmspcTcbDaoAddr),
            "\n",
            "PCK_DAO=",
            vm.toString(pckDaoAddr),
            "\n",
            "PCS_DAO=",
            vm.toString(pcsDaoAddr),
            "\n",
            "\n",
            "PCCS_ROUTER=",
            vm.toString(pccsRouterAddr),
            "\n",
            "DCAP_ATTESTATION=",
            vm.toString(attestationAddr),
            "\n",
            "V3_VERIFIER=",
            vm.toString(verifierAddr),
            "\n",
            "DCAP_ATTESTATION_ROUTER=",
            vm.toString(routerAddr),
            "\n"
        );

        string memory content_3 = string.concat(
            "MEASUREMENT_DAO=",
            vm.toString(mrAddr),
            "\n",
            "TEE_PROXY=",
            vm.toString(proxyAddr),
            "\n",
            "V4_VERIFIER=",
            vm.toString(verifier4Addr),
            "\n",
            "V5_VERIFIER=",
            vm.toString(verifier5Addr),
            "\n",
            "CACHE_VERIFIER=",
            vm.toString(cacheVerifierAddr),
            "\n"
        );

        string memory content = string.concat(content_1, content_2, content_3);

        // write addr to env
        vm.writeFile(".env", content);
    }

    function _setAuthorizedCaller() public broadcastKey(deployerKey) {
        AutomataDaoStorage(pccsStorageAddr).setCallerAuthorization(pccsRouterAddr, true);
    }

    function _deployEnclaveIdentityHelper() public broadcastKey(deployerKey) {
        EnclaveIdentityHelper enclaveIdentityHelper = new EnclaveIdentityHelper();
        // console.log("[LOG] EnclaveIdentityHelper: ", address(enclaveIdentityHelper));
        enclaveIdentityHelperAddress = address(enclaveIdentityHelper);
    }

    function _deployFmspcTcbHelper() public broadcastKey(deployerKey) {
        FmspcTcbHelper fmspcTcbHelper = new FmspcTcbHelper();
        // console.log("[LOG] FmspcTcbHelper: ", address(fmspcTcbHelper));
        fmspcTcbHelperAddress = address(fmspcTcbHelper);
    }

    function _deployPckHelper() public broadcastKey(deployerKey) {
        PCKHelper pckHelper = new PCKHelper();
        // console.log("[LOG] PCKHelper/X509Helper: ", address(pckHelper));
        x509Address = address(pckHelper);
    }

    function _deployX509CrlHelper() public broadcastKey(deployerKey) {
        X509CRLHelper x509Helper = new X509CRLHelper();
        // console.log("[LOG] X509CRLHelper: ", address(x509Helper));
        x509CrlAddress = address(x509Helper);
    }

    function _updatePccsDao() public broadcastKey(deployerKey) {
        AutomataDaoStorage pccsStorage = AutomataDaoStorage(pccsStorageAddr);
        pccsStorage.grantDao(pcsDaoAddr);
        pccsStorage.grantDao(pckDaoAddr);
        pccsStorage.grantDao(fmspcTcbDaoAddr);
        pccsStorage.grantDao(enclaveIdDaoAddr);
    }

    function _deployStorage() public broadcastKey(deployerKey) {
        AutomataDaoStorage pccsStorage = new AutomataDaoStorage(adminAccount);

        // console.log("AutomataDaoStorage deployed at ", address(pccsStorage));
        pccsStorageAddr = address(pccsStorage);
    }

    function _deployPcs() public broadcastKey(deployerKey) {
        AutomataPcsDao pcsDao = new AutomataPcsDao(pccsStorageAddr, p256verifierAddr, x509Address, x509CrlAddress);

        // console.log("AutomataPcsDao deployed at: ", address(pcsDao));
        pcsDaoAddr = address(pcsDao);
    }

    function _deployPck() public broadcastKey(deployerKey) {
        AutomataPckDao pckDao =
            new AutomataPckDao(pccsStorageAddr, p256verifierAddr, pcsDaoAddr, x509Address, x509CrlAddress);

        // console.log("AutomataPckDao deployed at: ", address(pckDao));
        pckDaoAddr = address(pckDao);
    }

    function _deployEnclaveIdDao() public broadcastKey(deployerKey) {
        AutomataEnclaveIdentityDao enclaveIdDao = new AutomataEnclaveIdentityDao(
            pccsStorageAddr, p256verifierAddr, pcsDaoAddr, enclaveIdentityHelperAddress, x509Address, x509CrlAddress
        );

        // console.log("AutomataEnclaveIdDao deployed at: ", address(enclaveIdDao));
        enclaveIdDaoAddr = address(enclaveIdDao);
    }

    function _deployFmspcTcbDao() public broadcastKey(deployerKey) {
        AutomataFmspcTcbDao fmspcTcbDao = new AutomataFmspcTcbDao(
            pccsStorageAddr, p256verifierAddr, pcsDaoAddr, fmspcTcbHelperAddress, x509Address, x509CrlAddress
        );

        // console.log("AutomataFmspcTcbDao deployed at: ", address(fmspcTcbDao));
        fmspcTcbDaoAddr = address(fmspcTcbDao);
    }

    function _deployP256Verifier() public broadcastKey(deployerKey) {
        DaimoP256Verifier p256verifier = new DaimoP256Verifier();
        // console.log("[LOG] P256Verifier: ", address(p256verifier));
        p256verifierAddr = address(p256verifier);
    }

    function _deployPccsRouter() public broadcastKey(deployerKey) {
        PCCSRouter router = new PCCSRouter(
            adminAccount,
            enclaveIdDaoAddr,
            fmspcTcbDaoAddr,
            pcsDaoAddr,
            pckDaoAddr,
            x509Address,
            x509CrlAddress,
            fmspcTcbHelperAddress
        );

        pccsRouterAddr = address(router);
    }

    function _deployVerifier() public broadcastKey(deployerKey) {
        V3QuoteVerifier verifier = new V3QuoteVerifier(p256verifierAddr, pccsRouterAddr);
        verifierAddr = address(verifier);
    }

    function _deployVerifierV4() public broadcastKey(deployerKey) {
        V4QuoteVerifier verifier = new V4QuoteVerifier(p256verifierAddr, pccsRouterAddr);
        verifier4Addr = address(verifier);
    }

    function _deployVerifierV5() public broadcastKey(deployerKey) {
        V5QuoteVerifier verifier = new V5QuoteVerifier(p256verifierAddr, pccsRouterAddr);
        verifier5Addr = address(verifier);
    }

    function _deployEntrypoint() public broadcastKey(deployerKey) {
        AutomataDcapAttestationFee attestation = new AutomataDcapAttestationFee(adminAccount);
        attestationAddr = address(attestation);
    }

    function _deployCacheVerifier() public broadcastKey(deployerKey) {
        TEECacheVerifier attestation = new TEECacheVerifier(p256verifierAddr);
        cacheVerifierAddr = address(attestation);
    }

    function _configVerifier() public broadcastKey(deployerKey) {
        AutomataDcapAttestationFee(attestationAddr).setQuoteVerifier(verifierAddr);
    }

    function _configVerifierV4() public broadcastKey(deployerKey) {
        AutomataDcapAttestationFee(attestationAddr).setQuoteVerifier(verifier4Addr);
    }

    function _configVerifierV5() public broadcastKey(deployerKey) {
        AutomataDcapAttestationFee(attestationAddr).setQuoteVerifier(verifier5Addr);
    }

    function _deployDcapRouter() public broadcastKey(deployerKey) {
        DcapAttestationRouter router = new DcapAttestationRouter(attestationAddr, mrAddr, cacheVerifierAddr);
        routerAddr = address(router);
    }

    function _configDcap() public broadcastKey(deployerKey) {
        DcapAttestationRouter(routerAddr).setConfig(attestationAddr, mrAddr, false, cacheVerifierAddr, true);
    }

    function _deployMrDao() public broadcastKey(deployerKey) {
        MeasurementDao mrDao = new MeasurementDao();
        mrAddr = address(mrDao);
    }

    function _deployProxy() public broadcastKey(deployerKey) {
        TEEVerifierProxy proxy = new TEEVerifierProxy(routerAddr);
        proxyAddr = address(proxy);
    }

    function _setDcapAuth() public broadcastKey(deployerKey) {
        DcapAttestationRouter(routerAddr).setAuthorized(proxyAddr, true);
    }

    function _configProxy() public broadcastKey(deployerKey) {
        TEEVerifierProxy(proxyAddr).setConfig(routerAddr);
    }

    function _configCacheVerifierAuth() public broadcastKey(deployerKey) {
        TEECacheVerifier attestation = TEECacheVerifier(cacheVerifierAddr);
        attestation.enableCallerRestriction();
        attestation.setAuthorized(routerAddr, true);
    }

    function _configRouterAuth() public broadcastKey(deployerKey) {
        DcapAttestationRouter router = DcapAttestationRouter(routerAddr);
        router.enableCallerRestriction();
        router.setAuthorized(proxyAddr, true);
    }

    function _configProxyAuth(address rollupAddr) public broadcastKey(deployerKey) {
        TEEVerifierProxy proxy = TEEVerifierProxy(proxyAddr);
        proxy.enableCallerRestriction();
        proxy.setAuthorized(rollupAddr, true);
    }
}
