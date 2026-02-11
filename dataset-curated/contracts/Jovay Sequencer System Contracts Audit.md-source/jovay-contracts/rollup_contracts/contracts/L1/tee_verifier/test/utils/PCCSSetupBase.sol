// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "solady/utils/JSONParserLib.sol";
import "solady/utils/LibString.sol";

import "./Constants.sol";

import {CA} from "on-chain-pccs/Common.sol";

import {
    EnclaveIdentityJsonObj, EnclaveIdentityHelper, IdentityObj
} from "on-chain-pccs/helpers/EnclaveIdentityHelper.sol";
import {TcbInfoJsonObj, FmspcTcbHelper} from "on-chain-pccs/helpers/FmspcTcbHelper.sol";
import {PCKHelper} from "on-chain-pccs/helpers/PCKHelper.sol";
import {X509CRLHelper} from "on-chain-pccs/helpers/X509CRLHelper.sol";

import {AutomataFmspcTcbDao} from "on-chain-pccs/automata_pccs/AutomataFmspcTcbDao.sol";
import {AutomataEnclaveIdentityDao} from "on-chain-pccs/automata_pccs/AutomataEnclaveIdentityDao.sol";
import {AutomataPcsDao} from "on-chain-pccs/automata_pccs/AutomataPcsDao.sol";
import {AutomataPckDao} from "on-chain-pccs/automata_pccs/AutomataPckDao.sol";
import {AutomataDaoStorage} from "on-chain-pccs/automata_pccs/shared/AutomataDaoStorage.sol";

import "dcap-attestation/PCCSRouter.sol";

abstract contract PCCSSetupBase is Test {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;

    EnclaveIdentityHelper public enclaveIdHelper;
    FmspcTcbHelper public tcbHelper;
    PCKHelper public x509;
    X509CRLHelper public x509Crl;

    AutomataPcsDao pcsDao;
    AutomataPckDao pckDao;
    AutomataFmspcTcbDao fmspcTcbDao;
    AutomataEnclaveIdentityDao enclaveIdDao;
    AutomataDaoStorage pccsStorage;
    address P256_VERIFIER;

    address internal constant admin = address(1);

    function setUp() public virtual {
        // pinned June 27th,2024 2pm UTC
        // comment this line out if you are replacing sampleQuote with your own
        // this line is needed to bypass expiry reverts for stale quotes
        vm.warp(1749112940);

        vm.deal(admin, 100 ether);

        vm.startPrank(admin);

        _deployP256();

        enclaveIdHelper = new EnclaveIdentityHelper();
        tcbHelper = new FmspcTcbHelper();
        x509 = new PCKHelper();
        x509Crl = new X509CRLHelper();

        pccsStorage = new AutomataDaoStorage(admin);
        pcsDao = new AutomataPcsDao(address(pccsStorage), P256_VERIFIER, address(x509), address(x509Crl));
        pckDao =
            new AutomataPckDao(address(pccsStorage), P256_VERIFIER, address(pcsDao), address(x509), address(x509Crl));
        enclaveIdDao = new AutomataEnclaveIdentityDao(
            address(pccsStorage),
            P256_VERIFIER,
            address(pcsDao),
            address(enclaveIdHelper),
            address(x509),
            address(x509Crl)
        );
        fmspcTcbDao = new AutomataFmspcTcbDao(
            address(pccsStorage), P256_VERIFIER, address(pcsDao), address(tcbHelper), address(x509), address(x509Crl)
        );

        pccsStorage.grantDao(address(pcsDao));
        pccsStorage.grantDao(address(pckDao));
        pccsStorage.grantDao(address(fmspcTcbDao));
        pccsStorage.grantDao(address(enclaveIdDao));

        vm.stopPrank();
    }

    function setupPccsRouter(address owner) internal returns (PCCSRouter pccsRouter) {
        pccsRouter = new PCCSRouter(
            owner,
            address(enclaveIdDao),
            address(fmspcTcbDao),
            address(pcsDao),
            address(pckDao),
            address(x509),
            address(x509Crl),
            address(tcbHelper)
        );

        // allow PCCS Router to read collaterals from the storage
        pccsStorage.setCallerAuthorization(address(pccsRouter), true);
    }

    function pcsDaoUpserts() internal {
        // upsert rootca
        pcsDao.upsertPcsCertificates(CA.ROOT, rootCaDer);

        // upsert tcb signing ca
        pcsDao.upsertPcsCertificates(CA.SIGNING, tcbDer);

        // upsert Platform intermediate CA
        pcsDao.upsertPcsCertificates(CA.PLATFORM, platformDer);

        // upsert rootca crl
        pcsDao.upsertRootCACrl(rootCrlDer);
    }

    function qeIdDaoUpsert(uint256 quoteVersion, string memory path) internal {
        EnclaveIdentityJsonObj memory identityJson = _readIdentityJson(path);
        (IdentityObj memory identity,) = enclaveIdHelper.parseIdentityString(identityJson.identityStr);
        enclaveIdDao.upsertEnclaveIdentity(uint256(identity.id), quoteVersion, identityJson);
    }

    function fmspcTcbDaoUpsert(string memory path) internal {
        TcbInfoJsonObj memory tcbInfoJson = _readTcbInfoJson(path);
        fmspcTcbDao.upsertFmspcTcb(tcbInfoJson);
    }

    function _readTcbInfoJson(string memory tcbInfoPath) private view returns (TcbInfoJsonObj memory tcbInfoJson) {
        string memory inputFile = string.concat(vm.projectRoot(), tcbInfoPath);
        string memory tcbInfoData = vm.readFile(inputFile);

        // use Solady JSONParserLib to get the stringified JSON object
        // since stdJson.readString() method does not accept JSON-objects as a valid string
        JSONParserLib.Item memory root = JSONParserLib.parse(tcbInfoData);
        JSONParserLib.Item[] memory tcbInfoObj = root.children();
        for (uint256 i = 0; i < root.size(); i++) {
            JSONParserLib.Item memory current = tcbInfoObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            if (decodedKey.eq("tcbInfo")) {
                tcbInfoJson.tcbInfoStr = current.value();
            }
        }

        // Solady JSONParserLib does not provide a method where I can convert a hexstring to bytes
        // i am sad
        tcbInfoJson.signature = stdJson.readBytes(tcbInfoData, ".signature");
    }

    function _readIdentityJson(string memory idPath)
        private
        view
        returns (EnclaveIdentityJsonObj memory identityJson)
    {
        string memory inputFile = string.concat(vm.projectRoot(), idPath);
        string memory idData = vm.readFile(inputFile);

        // use Solady JSONParserLib to get the stringified JSON object
        // since stdJson.readString() method does not accept JSON-objects as a valid string
        JSONParserLib.Item memory root = JSONParserLib.parse(idData);
        JSONParserLib.Item[] memory idObj = root.children();
        for (uint256 i = 0; i < root.size(); i++) {
            JSONParserLib.Item memory current = idObj[i];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            if (decodedKey.eq("enclaveIdentity")) {
                identityJson.identityStr = current.value();
            }
        }

        // Solady JSONParserLib does not provide a method where I can convert a hexstring to bytes
        // i am sad
        identityJson.signature = stdJson.readBytes(idData, ".signature");
    }

    function _deployP256() private {
        // TODO: fill for test
        bytes memory txdata =
            hex"";
        (bool succ,) = address(0x4e59b44847b379578588920cA78FbF26c0B4956C).call(txdata);
        require(succ, "Failed to deploy P256");

        // check code
        P256_VERIFIER = 0xc2b78104907F722DABAc4C69f826a522B2754De4;
        uint256 codesize = P256_VERIFIER.code.length;
        require(codesize > 0, "P256 deployed to the wrong address");
    }
}
