// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console, Test} from "forge-std/Test.sol";
import {Broadcaster} from "../../../src/contracts/Broadcaster.sol";
import {IBroadcaster} from "../../../src/contracts/interfaces/IBroadcaster.sol";
import {ParentToChildProver} from "../../../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ChildToParentProver} from "../../../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IBuffer} from "block-hash-pusher/contracts/interfaces/IBuffer.sol";

import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";
import {BlockHeaders} from "../../utils/BlockHeaders.sol";

contract BroadcasterTest is Test {
    using RLP for RLP.Encoder;
    using Bytes for bytes;

    uint256 public parentForkId;
    uint256 public childForkId;

    IOutbox public outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);

    uint256 public rootSlot = 3;

    ChildToParentProver public childToParentProver; // Home is Child, Target is Parent

    uint256 childChainId;

    function setUp() public {
        parentForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));
        childForkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(childForkId);
        childChainId = block.chainid;
        childToParentProver = new ChildToParentProver(childChainId);
    }

    function _getAccountProofBroadcast() internal pure returns (bytes memory) {
        // Nodes sourced from test/proofs/arbitrum/proof_broadcast.json (accountProof)
        bytes[] memory accountProofList = new bytes[](8);
        accountProofList[0] = RLP.encode(
            hex"f90211a068495e12a1ce50376d2d8a89f1b628c36270cb4d6674ce028eb0abfbd9a86d5ba0dd317914d747cdcfdc457d6275b011db4dbb72e2970bacfa03a8f63afdb95a6ba0e22db85789d8c1109174c3ab18c4e75564c9897ce7f740a72ce43e76e222fc8ba023adf0a3c0cd33e5e7c3d60231b5a33083867fb8ddbf58583884055cd37a3f66a04a4359e679c5074fd062e48d843196c31f2cd57dbf256c76ff85aeeda080c7fba0d2952adeacf9c50306e3972b46853fca57bcc9b5e2de6f01291df67142340d7da0f93b7549b46f79e78abee70b7c799ce8a63533b360b895b4d884af0e81b623bba0c4ca4fb6f4b96eba8063599d26d99aec5e97a3748b4322ecdc211e0e49cd0ec0a0b62bb8d52d875db984da8f91df931690356458c33d45b1971c569a2a96788105a01e4d8b3234845557ab14596975ff4a7f1ac4a7ea924fe5525cbe1fd58eb88172a013e3a6e41cfd3a87e8afaf61d49c3e8693f9eb0928627b8dce38e3a6331bc91aa0759faf37fc3c53567ed6611702984e90b11e97f3260d9a09dd84f2cef8fa5bb9a03d7e08b6f5ebbfb0c8f6e4473907d00891fae1c789768cc9ad416ea349b155cba02f49d77a68807f13596e116de4c153d9fc8ff8598765474af9ee805eded21797a00c4a2bf78904e075efacf92be4c83ba8ae47aee6bf55a28739c92c7535c78c34a03a8d1eeb23fcca04b152d4fe181a38ae94e0959da2438690c526a0d3b9af92f080"
        );
        accountProofList[1] = RLP.encode(
            hex"f90211a013ba5cf4109987ddcd54c27e499cc826a5243bb7aca7ab903c175522aa8d6ed3a000b67a90047f2b8c9f130f3d5c3e0c9f216cf142551364b55630ce6e4f4e6938a0daf3269dcc36a96de79482e066ba539e6df3cf6991686e304ede0e63daa40703a0d4390373b872e576fd1462045b66cd0b9707416bdae9316cf68cf542697d12e9a03cb921d65167c85635fd95986cb02f961992b05d2f9da44995a64ace570f18eda02a780b383890077cda05ac536f68656c8911cd2f1ed2151201ff4e99bb95f314a0f09464ba6eefe927d5cb3ab7c3da4fa7841da1e4e14feed4dfefd3e223f8cd11a06580f23f6555775babd169942479bd4f9a53b84f63236107bc2327902aa2fd35a081b0fc5747fc2916a801113e27bf272b1042d4f1515512e4e60e5be6b5f45cf1a0fa9de81cb423db803a205617df94a59ecc30b46e2b1b000ff280ba9aa2ede7fba0921f589b695004609a322552d02f10d11c8e38c73c7430070827c33bfa7619cba05dd8e78185c78638210a3bce08a3f72db55abdd157964ae17d0d781c82ebd53aa0a90d777bcb45bc01ed5147d461cc879514bb1cb756a25a3815a2f1c09fb88131a08538a7397dd218f50af9ccc60e50e362c6ce2815e2bcd9f13ac4c3e96e620242a0074e847c66f19dba42a32bb700546caac4d641661f1a580a7b76d5ec59890446a0cebdfa4c3d8726c479ca27cfb03ceaad2cf801470249a01d6fa364a5a3b6d57180"
        );
        accountProofList[2] = RLP.encode(
            hex"f90211a0aa7fa2b8a272ef1fa767bb9f1280eb21e0532a1702e78bc39598f40e4f1ed512a0c0aa53b903ae2ed87db2ef82ddc0ab5f8f9f326bd21843cd016e00c03ab1f708a088f4d386420b5dc0c69dd448302b332b36e81aae9cc82768fde8014b8ccc47a8a07d1d769406e1333e9e92a3d92fbd6f5b83dab3299056f5a89ffbab1550fee6d7a0f2df43ab2e783535760cef36a87de399c6dbf9c192bdd5fdb02f7136c9a93893a0311f3f7ada5b7ab5ee59e6c6d84abedc14e336b54461db6a6d275091e05d31aea0a7254108824c3a9e40029e1bec15c8488e5b689029569fdf0ba6dd1f84677ffaa0f73e394af18c408e349d3761c8feaeaeddaa2d4ecc530f9a1c00b344b0c1279ea01e3492673d849acedb43f5b47f5d5d6bc29500398ec59403927146660f4d0605a09db66687d86cc49388277e21ab54a756691cde14d4ea9dd797415e6861f3d684a081f0b42bd39b6b75f63313e6a63c4ab432653b94f2a90efabe98777069b603baa044cb3b8f855eaebd9cf777f1749e05ee768529f2f36fcf0e78d162a312c2ffb6a05d364fad6797f2a171c533e877b5a5565d82736085bec2190eadddb54e4e860aa0e42f8173ead0140e176bd6ffeed00063891d4fc90d22b52cd342b5ee2f87f2a7a0ba00732131622890d5f0c1c9f7aa6fba55bd29c51128c6960253fea01b6a76d2a047a602487abe4f58d433f6324be127f58cdfd50bdf7ac86ef362071b72975cce80"
        );
        accountProofList[3] = RLP.encode(
            hex"f90211a0ac6a821457345770334e09dd8ef630a29a0015692628c4cc18bc4d017926585fa04f8f7c3a2aba215f0cf64a1607b643579175dc5243093b7cfbf8fee52e5cc652a06dc52d24e3c528a58e8c5cc18d7e611e5b8ba6d39561b1ef17707f2138e0f4b7a04f9109a265a0beaad642106742003593f8b0c1db3a2d6366c48a6dacf03ec0d8a02566899094f4564cdb189a0a5e4109eb0550499677bb343a310dd3eeadf04774a0f146340af3750d21e479c29b2f29f92649834b9544ef185bb543f67f6565f739a0bc2782a82075c4776fae40f8a076ef2187a9530a16f14dabc167829b604fd125a08786b8148ab9ac7c6e60d0fd3c371c0262cc2b4738da282797a450d84f1db21aa0fef29cf945ea13a49906d801a83e876af0267c07a536ce7ecf531a41984f33ada012242a3b92cd965f289c7343faa887a933e51ed84a9dcffa4ab785732a3da42ba0d61135542c4d13f2a611cb1957bb61b57cad5650ab9a5e2ed666ac320007dbafa010e12a652adab679df34b3e6bd76db9f114bace57589ac1ae22de83ef40417dea0eb6470ab3489b70cd4acaebaa6fac49896f4fe2987f0e94eff9701847b126cbfa0dedb1ffa019901ab7cbb6ffbb936a03c3a4a5ba84115cad7c55d0aa5167f4ef2a0189509e85a1bcd72f4fe8e16bce32e0a61c42b7f12f3275aaaad88602e9e7fc1a053540eb812a50a34c8c59857894e45bda9c6a7b03a96ddc5f88dc2623ed2c04680"
        );
        accountProofList[4] = RLP.encode(
            hex"f90211a09cbd69967953472248f33bc7b65dbc11e51a331f31c5a5b1863f701ea7f136dfa08da14622e86f9e9ac6e98ba34fc355ed91c487487390ced7d9ce2e6d38d1873ea05c596a0006f15316a1b763c297b57c66511e8cd3d552336c7b89ab04bd743ee8a0e535f7b306552ea06eb435d824c4b9e58fa6609d660df7e63595ea3e77426c4ea00e0221ccf429371d655686bcccbf582ada081a835c405eedb15c63c251040b29a012934cf1e4a01094581e3807f046c883b3fc8be7182227fb4d5f271d1745772ea0d16a6490fad1250761d787577614e8d915ea318d73ba4b7eb5f437d90c8bc042a03086df460b9506f938d2e552b6733c8ce61541f8bd1101532cedaf4df3eae2f5a001edbcfe3c65d7b7de957dd654d41f8457caf1586d425cdd0acdf3ac3bcaaafaa0e3e9b52dd3ac2b4b58c807a7b09c99bca44f9e8331ceea2e4b50097122cf43f7a0ff05a213975640dab564ee97a48e2139b56b905aa9f8e1f2ccf46787c9ddbe07a02639992585fe80ab0aa3c1c9a0509a1e3450f78d2a39b17ff6782dc4b2cc9c57a0c8c052b18b1fcb7da093118caa6fbbdd55d30ceb9eeef71b6c2f01ee51ed4d32a0adce55a5efbd2f07154a502bcbe38921319bf30cbcbe8fe0b34e5ee353a53010a006bfb31bd1c9fdf0db840190f8f6ff696671729f3e78379ec55d77fd8fee6343a037c889398e7e44c91c454a77c69f3689b294157958e90bbf1848df30a7670d7480"
        );
        accountProofList[5] = RLP.encode(
            hex"f90211a092d7d5895494170e8a4b81bdf8798663e30016d3f3232dc5b9b60ba44e1854eca03c646b103610a0d85c5b512f863db1e02c758bf06cdade3ce278cb9ad7c5dd7ea0098340a50f05166e18dc4eaf680d4cca5c3ef3122b252bb25c61eb46113de5eca0bcf6ea20fee054dfa15f3ebb6bc4ff4303ddaa2eb1c559b2715782a43d90d38aa0f6f5db2476cb67984e422ba5ee4d033208701c5cd647eb20fe0fa610f65f999ba06337d18d5714d4429b75a560aa08901ea18e8cd05f02ab3b4cb183659a639a34a005fa8296eb592ce18931966e68763e963e69da388264d69d3ca9d6c1f0565188a08741c5279f29a8b3f4faef7612d7e1164ddaebbc274a3263a25a6be869249b99a06f3ce8da16d989dedcc9311638fe878fcfc210bb58906849e2e1f6337166c4daa0a2a00f1d61a1270107929ea04e7e1452278025ae90e95665e6f78f20fc0bf77da09020440ff072ab6e6f3b10bd9c93be7d3dee74c1c2106de434c687ff5cb6e2d6a00b640358864ac03587fa522fbfa7f42802db08cbaf46149c58e03e192ba6b468a06702242b240695c83bcb62eaeb3e0eb9dd3536c38ae574dfce25fd8c7210341ea0dd93ab820e27cf1469c04a4bfd6a26137e65aa8ba1a135f729a241dac513e192a0155927a6f52025cb53999a049840bd8693461083e276ff586a864781dba35f8ca0b5ec104a87a0773756ad6b0cc44edf6afe89c89db5ce94b3ecbc29b84bb1d85680"
        );
        accountProofList[6] = RLP.encode(
            hex"f90171a0e0d4461d9aec51264a25b47c44d423a8315ac1742752b979d3f27babd82ede39a0e221333bd270f7c2407ca99c34e15e74c120cdf2edf2fdc1523284ac32f89dd1a040196e43c59bba4d30dd08937e1f7536dd2bb76d502d29a9ef520e2df107fb2ba061760a5085194cbfaa61cbc5ecf57ab9a878d150051045770ba0c7e52d48948da0305506affe332344a6e16aa49bd5fc4cbc2d680602fd4a2c1bb130cb56aaefeda0f6bbc85f5eb04edf849889dd15811309c0cc1b0383bc4c92a7c1b4d0bcec5f5380a0bfca7c4787eb9d7e4f4a94d5996577d636056e4f0e8ee18dd43bc49d00ab7c48a06851e6a4a5d7312f645587de4855ec5b319324e981fc01da0e9bc30031428c6fa09e9ba798b699a2b7d92981123cefa304f5538c8f788f745b37a31e6fb75eaddca024eb1e981929ebac2bc6355806b961e91a918a65a3e0156c84b5aa567478a8b8808080a02d23b0058d7096d72982289e05102781c64644d61478aa11e6f8ac04a9771ddb8080"
        );
        accountProofList[7] = RLP.encode(
            hex"f8669d32cc05f6ec97cdd52af5716ff806f93adbe088fcbe6aea1197da14c00bb846f8440180a0bf4af2e8e4472148c44c393bd49fd938d117337c5348177981fb025d21339b76a03debe8ce6033a7570465c1bd57dfe3c0ca9dba458721039d4d47c10d5025252b"
        );
        return RLP.encode(accountProofList);
    }

    function _getStorageProofBroadcast() internal pure returns (bytes memory) {
        // Nodes sourced from test/proofs/arbitrum/proof_broadcast.json (storageProof)
        bytes[] memory storageProofList = new bytes[](1);
        storageProofList[0] =
            RLP.encode(hex"e8a120e9c5cc9c750ef3a170b3a02cf938ffded668959e8c4d274ee43f58103248e67e858468f9ca7f");
        return RLP.encode(storageProofList);
    }

    function _loadPayload(string memory path) internal view returns (bytes memory payload) {
        payload = vm.parseBytes(vm.readFile(string.concat(vm.projectRoot(), "/", path)));
    }

    function test_getTargetBlockHash() public {
        vm.selectFork(childForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_get.hex");

        assertEq(payload.length, 64);

        uint256 input;
        bytes32 targetBlockHash;

        assembly {
            input := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProver.getTargetBlockHash(abi.encode(input));

        assertEq(result, targetBlockHash);
    }

    function test_getTargetBlockHash_broadcast() public {
        vm.selectFork(childForkId);

        bytes32 targetBlockHash = 0x57845b0a97194c2869580ed8857fee67c91f2bb9cdf54368685c0ea5bf25f6c2;
        uint256 blockNumber = 9043658;

        bytes32 result = childToParentProver.getTargetBlockHash(abi.encode(blockNumber));

        assertEq(result, targetBlockHash);
    }

    function test_getTargetBlockHash_broadcaster() public {
        vm.selectFork(childForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/broadcaster_get.hex");

        assertEq(payload.length, 64);

        bytes32 input;
        bytes32 targetBlockHash;

        assembly {
            input := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProver.getTargetBlockHash(abi.encode(input));

        assertEq(result, targetBlockHash);
    }

    function test_reverts_getTargetBlockHash_on_target_chain() public {
        vm.selectFork(parentForkId);
        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_get.hex");

        ChildToParentProver newChildToParentProver = new ChildToParentProver(childChainId);

        assertEq(payload.length, 64);

        bytes32 input;
        bytes32 targetBlockHash;

        assembly {
            input := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        vm.expectRevert(ChildToParentProver.CallNotOnHomeChain.selector);
        newChildToParentProver.getTargetBlockHash(abi.encode(input));
    }

    function test_reverts_getTargetBlockHash_reverts_not_found() public {
        vm.selectFork(childForkId);

        uint256 input = type(uint256).max;

        vm.expectRevert(abi.encodeWithSelector(IBuffer.UnknownParentChainBlockHash.selector, input));
        childToParentProver.getTargetBlockHash(abi.encode(input));
    }

    function test_verifyTargetBlockHash() public {
        vm.selectFork(parentForkId);

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_target.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 homeBlockHash;
        bytes32 targetBlockHash;

        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            homeBlockHash := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        bytes32 result = childToParentProverCopy.verifyTargetBlockHash(homeBlockHash, input);

        assertEq(result, targetBlockHash);
    }

    function test_verifyTargetBlockHash_reverts_on_home_chain() public {
        vm.selectFork(childForkId);

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_target.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 homeBlockHash;
        bytes32 targetBlockHash;

        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            homeBlockHash := mload(add(payload, 0x20))
            targetBlockHash := mload(add(payload, 0x40))
        }

        vm.expectRevert(ChildToParentProver.CallOnHomeChain.selector);
        childToParentProverCopy.verifyTargetBlockHash(homeBlockHash, input);
    }

    function test_verifyStorageSlot() public {
        vm.selectFork(parentForkId);

        address knownAccount = 0x38f918D0E9F1b721EDaA41302E399fa1B79333a9;
        uint256 knownSlot = 10;

        bytes memory payload = _loadPayload("test/payloads/arbitrum/calldata_verify_slot.hex");

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        assertGt(payload.length, 64);

        bytes32 targetBlockHash;
        bytes32 storageSlotValue;
        bytes memory input = Bytes.slice(payload, 64);

        assembly {
            targetBlockHash := mload(add(payload, 0x20))
            storageSlotValue := mload(add(payload, 0x40))
        }

        (address account, uint256 slot, bytes32 value) =
            childToParentProverCopy.verifyStorageSlot(targetBlockHash, input);

        assertEq(account, knownAccount);
        assertEq(slot, knownSlot);
        assertEq(value, storageSlotValue);
    }

    function test_verifyStorageSlot_broadcaster() public {
        vm.selectFork(childForkId);

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        bytes32 expectedValue = 0x0000000000000000000000000000000000000000000000000000000068fa57d8;

        address knownAccount = 0xAb23DF3fd78F45E54466d08926c3A886211aC5A1; // broadcaster

        uint256 blockNumber = 9496454; // block number on parent chain

        BlockHeaders.L1BlockHeader memory blockHeader = BlockHeaders.L1BlockHeader({
            parentHash: 0xee9b4472f4d8c1b58f362c102d3af6e81e620d817f59c4566ee70acc403fa6f8,
            sha3Uncles: 0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347,
            miner: 0x3826539Cbd8d68DCF119e80B994557B4278CeC9f,
            stateRoot: 0xb11937ee06682d2f6469a0a8c219dc024b590d015fcc8601d11dde4c4c30dd86,
            transactionsRoot: 0x99f8df7e21515bb7252be5d7993374ed2cbdcf61803c14aa84d9f04bcbe71abf,
            receiptsRoot: 0x8829245840598393135ccaf3006419980663d7a74036ad92ce543adb20a3c3d6,
            logsBloom: hex"f00000c0122000110801852032900a04080c8108131281806101c107423a58c2e0200400a04030b20038043280300848810100008a80c813c8843821fc20031090080b00450021212002046a24000040042085616022c088a80204512402001502050059220081800104d020800008424200600001804000082186140205412004080600055008832080800046aa208c2154010000aca011a503840185000d8922ac008310201024042050010d00308a1340300010088881828b260020450d0018d801361000040c0020146a000240850613000088800c2010211c1a4e01240b2010300900900141c0421ad02482102a0402024c290448c00240370601644648",
            difficulty: 0,
            number: 9496454,
            gasLimit: 60000000,
            gasUsed: 11416508,
            timestamp: 1761507384,
            extraData: hex"626573752032352e31302d646576656c6f702d31373934643462",
            mixHash: 0xa90c770588f500b303571ab09f2fef9335989b742fe07cb59c86d32967b470a3,
            nonce: 0x0000000000000000,
            baseFeePerGas: 10,
            withdrawalsRoot: 0xd60747bd62c89c322e7c555bc4ce8b86ef47fe46777a4b7975dc64ee93c4a01f,
            blobGasUsed: 1048576,
            excessBlobGas: 0,
            parentBeaconBlockRoot: 0x34ef4702de06ebc214120d2a09df376a65740a5ab27dca82fd5d4c89f38f7c9e,
            requestsHash: 0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        });

        bytes memory rlpBlockHeader = BlockHeaders.encode(blockHeader);

        bytes32 blockHash = keccak256(rlpBlockHeader);

        bytes32 expectedBlockHash = 0x9696097155f4737f3fed52933f8c010a2592decfc88117da9c1442002c1f37ee;

        assertEq(blockHash, expectedBlockHash);

        IBuffer buffer = IBuffer(0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071);

        address aliasedPusher = 0x6B6D4f3d0f0eFAeED2aeC9B59b67Ec62a4667e99;
        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHash;

        vm.prank(aliasedPusher);
        buffer.receiveHashes(blockNumber, blockHashes);

        bytes[] memory accountProofList = new bytes[](8);

        accountProofList[0] = RLP.encode(
            hex"f90211a0b0b95e67e8aa61300a71afe6157bf84b39233462ea64aa0ede48cf35feaabbcfa052a9ca3ff2ca72798469a010a004a29b0ae970ce27f5ef8d998b27a9b0625207a0f3436bfd2ec36d3296cd081062f0a2bab4a4549f97f889ba5a4f9cb36290c447a064e9aceea7480537d7844b2d848b3182feabf30112e385bcb47388dd627521bba00b8fec9858a453b4a8bf04263305f54054bc078221d60332f1aa3343cc194705a0bd67eb93fad2af1a55b444b683b6b2095575453ec3d1dee0f6a7c0e53f827caea0228eb016dd6ae3ad9f848803e74d96eec8ea49929e774b8a38b5fac469ed0e47a032bf38c9e8d75739465fa659cc1d4d61a156054c943654b5b1a6b5462b33fb1ba0a51d7804ccfe088ea82e7601ae5ed1bf9a5449efa8aae9376ac2711ed010e277a0d6ca8b774bcf95ed32f4f346f3e334f6393788e068fe5b9c4bf8587748f67bf0a095bd4aa36b965ac3b87f4f4da74c7733435d3cf79474b8f9246052096bbc3f03a0fe15d293a3e6cfcf766a915498b038a3fb28e6db194b42106831cde5cdad48d9a076d4a753e7b873269515c60291cbdf26f52a218735ca1399fde86dce36f8ade3a0338d465e52fb472f2d12788d03b22d0c9fcdd6224ef73c114d153a2e49cb322ea0484a5e7df4ff5319ca78d07211b89bcf0dc3ccbdeae8563d31aa644e9c2ef22ea0bb1e7d0bbda92fc18e40f54b90aa9b26c7ebd950e07ef2f45bcb744f0304f30480"
        );
        accountProofList[1] = RLP.encode(
            hex"f90211a0d9595c35e1e689fb1561039e08d66b2fb23d11ab966c8f4c3778ea1e6e1a525ca00af85211e3bf3a227e81b849767c7cfcda320457b8d4ade04e0927b8690bfb27a0c8e3444abaa0adff441f3abdd6e68820285616319154a7d4dcea50a58ef670f9a0c44739ea6bcbe5fea9f3daa3dcc80b1598b956a69eb906089e8929c042ddef3ba0b0cd38f1002cf6d9d76aaf2ed94baba6b34209b38662151111d2e67ad874fbfaa0e791e8ca9fbd4af504f484fada447f440d245e647e4b25236535d57bf6a0247ea03cf7749165fa81377d5ae438df0023a76a1cdbaae582f026a1f4a33487f46cb8a075782af998e1c0d0ad3d45e5f7f60bdf094114a1d91ab7aff17c01a249c0d591a0269ca516d1f5bf9633f4c3f088decf98ff0aa6ecf8010bed9282417b9a40514ea0975958f99f7f882a43d145a7004d86cffea1d7bd47e4743ac8591e1370af7c87a0a52be157e3d3735ccd7b70810dd4f5b8dc2bf93c0f8cb1e5b6099de0b408300ea03160c5fb073619be4bbf4c5395ba8088471779297d1920c4f8e6367e51e35e49a02342b7acb077299a819d7d324adc4d141942714fc7a522c73649e239fe010508a08950b87a5b5c626d6914b3b9efe9f14c8b48655362a17c1bb4fc67e6e541d5c3a00515e77dace3066455f8b6fc2267d35e8b2e1bda947d4d0f249e2890c5e3d251a0d591d436c00345c54cd588e196ff0f91835f39cf538a039df94555c7e7294ca880"
        );
        accountProofList[2] = RLP.encode(
            hex"f90211a01a4198c0f5ce8b5d394cb42a6b59b7d0c666bf61bc50bf048670cf0737855fdca0895cccc84959ac6392f0ec1e5e9dbac24c6d1e3fe684fcaa5e9ecdbf0696c144a0a2ed8b41e0a718bb7b800db1612497088bc7839ebe099a762daf9a446c19ac42a0495fde26bf761a71317e017e0351ad61fb09d5ded1cdfd14cc6ab0f9ba1e7cf8a091aade5c90cd00386f964e1f9e468a5fc30e26ba052b28edc95b16307825992ba05c3066c65c561d4b87c043d6ec8ff144c761fde69ad32b2679a976d17dc668cca09f6cc72b8c372908f42a942fbea0efa82e367a3d27eba7a7a8d1b461f24855e6a09408510fcb45f702e9c0b2f189704c8b50cdc86436574f347d5de02179511c1ca01a62e2d29a307572c6df2ea7162a5f2aadbb1028d521f3ec470d94d9d5a8a162a0bce9be38d51d2aa47e8cabfc2637dff161646e6e7f40922b160cbf292eeaf69da073ac4f5f3c162e11349a7e2fbf751859cd829a434e2cc1bd49187715463f494aa089c8aa06113765e7e68697ef16c5a26753a989903d5626edf41cdf21f6860552a01701293ca754ea65ae893d0705226f63d1795b775f671011d23f6e2f661b87f4a09ea77441ed691b51c643befa090c72e7408622e008f5f5df2c1d400811ecd589a01e1e427f5e2964520e4b9e818ee44d7f56678f91fc32f0759ee8b0c0b76f654da0d55d93e68fe5d21766bcf487fb898b2c61781a6763fdff779fc2241417d9db7280"
        );
        accountProofList[3] = RLP.encode(
            hex"f90211a0c5d06e34ca79ed78c18adb7affe8742de2e58201fca0bf436c828d8232f6d0baa0fab5b29e06466da3c3792a890153738a3035f7d20274e6f8b60ecf72fa1e789fa078c4744aee74da56cfd2f1d2fa609a7118b05420253f779c53d96c7145e982b9a042f2ae0ae4e1cbe72b2f295bfe252c4ace3fb83a8e964557616ee9bd228566f3a0fcbd0da6912cc1cf44e4a1553a66aefe6f9642b74963f480058cf7a1cabf4b36a00d5c5c04878ec0c07b56b1374dbc37a6051e94ff55557ee68534666fb0f02895a0b0009ef22aee2091cad38c0fc04126008ebb3c1ec85e0ee015c45afda40d814ba076e3e653cc38062bed7b583bc89addd852efd3777a8c7b6c9767cb17b84fe996a016503e66b0b417bc130207b84b29b2b1a2471047b2d26b97d8318087d8b28a90a09677de7562ade630ae4c2f2aa639af5a71b801b88c54036536beb7ea3f4da20ba0a26fd6ee4ba73135e022a86543f110c8cff8fc196da70476728e29afa53abbd4a0b6b02ed8681c67bbcdbaa4250a9a8b2af9553990ebd9c415e61ba89922d38563a0416f8fa03b7c8e16437a8a0b1c6e73ce375f369cdb620ded8d95504b3ab67a06a0c1342004868ff43da6430fd9dd0d6a1d9ced88b454d5a48c79c41fe4565129eca0e45241b73f4d329f4fe909401f9aa76b7e46162e6fc3dd81be819d1c06acff51a0f71ec474fdd9230f7292c0c4002f2b5603325868486ccd93c14de53f65fb6e6480"
        );
        accountProofList[4] = RLP.encode(
            hex"f90211a0e54f82daf54b26973f584016ca833654dee0a659464428fe1ce53097380bc2d0a097a696b4cd659cb0fe2f87d9a5f8fee87a032ff6ac95489fb985103bf232aca5a001b9af9e74ac1132eb2f9c20ac950178ea066a1bf67898b2bfa908b374881015a0592e35261c24a24435af64b11a177cbc346f4a0c91d4eb9b229ac373e8a9e5eea0a6d5d2e84b5e6a32f5aeaddb2635e7c78de78c8a45c2a609e628364ac88fd1e4a0a1ce8455d7a9a560bef917b5bab4be927586f070ba515c75a1b58d86883679a7a03b1e2c4c3adb9611b891605f206f6feba27c1e8f0dc971785d871f8aa5a6c71ca05af4aa3a2323e521a2ccf5d74bb29c343e89bdfd5a056ba00b117e751adfc4eba0df4cbfa36a4af781876cc0b172fbc3752933f0bed3f4dcb38642b4b5e3b95535a088bed8ddd0b03ad9d519643589e106daf8b0a6ee7510efb3ffc436b6d08c385aa0cfa4a71af2c4ee6856b64199be680df4f04987d28dc707b9b81b1ae2135342aca007f48265cb2cb83f63518a4f813f344836cc4ccf969eff0a0d8bf98bf4570d90a0f189aeb9c6a9c5517d6940b57a5bf3c61fa9a589a35bab963a15176731d3ab76a00e51492b77450e0544151e6b16c9a24e6b1d316a5cc992bd0f52bb846dae23bfa0dfe5989673399538a7dfece6561477b803a0f0cbf3064dbb5b7be8a39deac533a02ca0c5810e279a986c31d251c1d3413cb505a03bc85c172bdce8a6b35e276dfb80"
        );
        accountProofList[5] = RLP.encode(
            hex"f90211a02614da908a4849f529b99e68ca69202ced4848b3bf6d1588d107535056e63eeca00477bfd2aecc7a0914f087efee823ae72a6b723d960a55e6c0c931917410b91ba000b6602e9ad6a574bda8edd73f36dc19bf59e8f07cbef550c6e62ad8d7837275a080181a744c9ce8bfb3ac8ea4f5fde39c5dd5123d768cd672ad8724e70d7d263fa06f4f223a69c0872022884fb78088456e2871fabb67946a5c3aa1c2fc97067f53a0789e4ffbb34e200bb32122488867a04c6af28be25d7ce3627219eeb27da1d1e6a083bcf68bd3418e85c3ffe8721a9e98aa51eb1f8eb96e0b8c8c94084636e8b9fda01d55714ed9e4b5394924f8e7514374cfe5757a4e512a66bc6b61ed6bd99ae3d4a0f253938718dbf4377cd93103862dbb45f1077405a2d3a57738d45a1fac21553da059b843bad4688ecb2ddee56c13a7c990ed84efe655eb0fee8d06cbd4f52886fba017e2ac27459cbf0133cc9f9c2623e029c71137764368f57e2de62070011b74dda0d77d24119a2950d6b4f90eebbd4d5342f592f3c8f9980debed42ebd0004d5ecda0c64c80f579948559cd119490389c1370348b031a1ab72ec84ae18a783dfd49aea04fcff07c044cbc30b26ca0fc41d2ec474506fab38bbbbb582519f09543e2ea13a0ffbb5ce620fc8e2b39ee70b18dab1fd31dabf7a1361232db072b5534d6c45ea3a047aec790619add4898883dd60be479887cd8bb312ffb92c7f253c5162a9d33a180"
        );
        accountProofList[6] = RLP.encode(
            hex"f8b1a0c7491b416a7a20bfc78fe1f7a4518958524b539c331c25ebb60cb7d651e94c4b8080808080808080a07d39eba3b1cab99692c17e368f1506b4c9d1270b6bdbeed83253143a9f51efa38080a082a3f66f1fdba2188333439a63fea1632b0a504d1735fe45dcdbc750c980d74aa0e76eeb8f7a7ff529ca36d01f44bffa3e85b363a8d6a2b2c9d25c2114dac70689a043b641bafe98b738fff861b3875f87245830c1d29a7c0d411d1da3958fa0f3e18080"
        );
        accountProofList[7] = RLP.encode(
            hex"f8669d35ea91a4f74675160ac2ae6e03f04be23fbf7e800eb88db12c6f5904c0b846f8440180a0c672639a72b537f19eaae20d66e47cd1d977ac18ed81e0bba3b200f671e5bcd1a03debe8ce6033a7570465c1bd57dfe3c0ca9dba458721039d4d47c10d5025252b"
        );

        bytes memory accountProof = RLP.encode(accountProofList);

        bytes32 stateRoot = keccak256(
            hex"f90211a0b0b95e67e8aa61300a71afe6157bf84b39233462ea64aa0ede48cf35feaabbcfa052a9ca3ff2ca72798469a010a004a29b0ae970ce27f5ef8d998b27a9b0625207a0f3436bfd2ec36d3296cd081062f0a2bab4a4549f97f889ba5a4f9cb36290c447a064e9aceea7480537d7844b2d848b3182feabf30112e385bcb47388dd627521bba00b8fec9858a453b4a8bf04263305f54054bc078221d60332f1aa3343cc194705a0bd67eb93fad2af1a55b444b683b6b2095575453ec3d1dee0f6a7c0e53f827caea0228eb016dd6ae3ad9f848803e74d96eec8ea49929e774b8a38b5fac469ed0e47a032bf38c9e8d75739465fa659cc1d4d61a156054c943654b5b1a6b5462b33fb1ba0a51d7804ccfe088ea82e7601ae5ed1bf9a5449efa8aae9376ac2711ed010e277a0d6ca8b774bcf95ed32f4f346f3e334f6393788e068fe5b9c4bf8587748f67bf0a095bd4aa36b965ac3b87f4f4da74c7733435d3cf79474b8f9246052096bbc3f03a0fe15d293a3e6cfcf766a915498b038a3fb28e6db194b42106831cde5cdad48d9a076d4a753e7b873269515c60291cbdf26f52a218735ca1399fde86dce36f8ade3a0338d465e52fb472f2d12788d03b22d0c9fcdd6224ef73c114d153a2e49cb322ea0484a5e7df4ff5319ca78d07211b89bcf0dc3ccbdeae8563d31aa644e9c2ef22ea0bb1e7d0bbda92fc18e40f54b90aa9b26c7ebd950e07ef2f45bcb744f0304f30480"
        );

        assertEq(stateRoot, blockHeader.stateRoot);
        bytes[] memory storageProofList = new bytes[](1);

        storageProofList[0] =
            RLP.encode(hex"e8a120e9c5cc9c750ef3a170b3a02cf938ffded668959e8c4d274ee43f58103248e67e858468fa57d8");

        bytes memory storageProof = RLP.encode(storageProofList);

        bytes memory input = abi.encode(rlpBlockHeader, knownAccount, expectedSlot, accountProof, storageProof);

        (address account, uint256 slot, bytes32 value) = childToParentProver.verifyStorageSlot(blockHash, input);

        assertEq(account, knownAccount);
        assertEq(slot, expectedSlot);
        assertEq(value, expectedValue);
    }

    function test_verifyStorageSlot_broadcaster_notHomeChain() public {
        vm.selectFork(parentForkId);

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        bytes32 expectedValue = 0x0000000000000000000000000000000000000000000000000000000068fa57d8;

        address knownAccount = 0xAb23DF3fd78F45E54466d08926c3A886211aC5A1; // broadcaster

        uint256 blockNumber = 9496454; // block number on parent chain

        BlockHeaders.L1BlockHeader memory blockHeader = BlockHeaders.L1BlockHeader({
            parentHash: 0xee9b4472f4d8c1b58f362c102d3af6e81e620d817f59c4566ee70acc403fa6f8,
            sha3Uncles: 0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347,
            miner: 0x3826539Cbd8d68DCF119e80B994557B4278CeC9f,
            stateRoot: 0xb11937ee06682d2f6469a0a8c219dc024b590d015fcc8601d11dde4c4c30dd86,
            transactionsRoot: 0x99f8df7e21515bb7252be5d7993374ed2cbdcf61803c14aa84d9f04bcbe71abf,
            receiptsRoot: 0x8829245840598393135ccaf3006419980663d7a74036ad92ce543adb20a3c3d6,
            logsBloom: hex"f00000c0122000110801852032900a04080c8108131281806101c107423a58c2e0200400a04030b20038043280300848810100008a80c813c8843821fc20031090080b00450021212002046a24000040042085616022c088a80204512402001502050059220081800104d020800008424200600001804000082186140205412004080600055008832080800046aa208c2154010000aca011a503840185000d8922ac008310201024042050010d00308a1340300010088881828b260020450d0018d801361000040c0020146a000240850613000088800c2010211c1a4e01240b2010300900900141c0421ad02482102a0402024c290448c00240370601644648",
            difficulty: 0,
            number: 9496454,
            gasLimit: 60000000,
            gasUsed: 11416508,
            timestamp: 1761507384,
            extraData: hex"626573752032352e31302d646576656c6f702d31373934643462",
            mixHash: 0xa90c770588f500b303571ab09f2fef9335989b742fe07cb59c86d32967b470a3,
            nonce: 0x0000000000000000,
            baseFeePerGas: 10,
            withdrawalsRoot: 0xd60747bd62c89c322e7c555bc4ce8b86ef47fe46777a4b7975dc64ee93c4a01f,
            blobGasUsed: 1048576,
            excessBlobGas: 0,
            parentBeaconBlockRoot: 0x34ef4702de06ebc214120d2a09df376a65740a5ab27dca82fd5d4c89f38f7c9e,
            requestsHash: 0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        });

        bytes memory rlpBlockHeader = BlockHeaders.encode(blockHeader);

        bytes32 blockHash = keccak256(rlpBlockHeader);

        bytes32 expectedBlockHash = 0x9696097155f4737f3fed52933f8c010a2592decfc88117da9c1442002c1f37ee;

        assertEq(blockHash, expectedBlockHash);

        bytes[] memory accountProofList = new bytes[](8);

        accountProofList[0] = RLP.encode(
            hex"f90211a0b0b95e67e8aa61300a71afe6157bf84b39233462ea64aa0ede48cf35feaabbcfa052a9ca3ff2ca72798469a010a004a29b0ae970ce27f5ef8d998b27a9b0625207a0f3436bfd2ec36d3296cd081062f0a2bab4a4549f97f889ba5a4f9cb36290c447a064e9aceea7480537d7844b2d848b3182feabf30112e385bcb47388dd627521bba00b8fec9858a453b4a8bf04263305f54054bc078221d60332f1aa3343cc194705a0bd67eb93fad2af1a55b444b683b6b2095575453ec3d1dee0f6a7c0e53f827caea0228eb016dd6ae3ad9f848803e74d96eec8ea49929e774b8a38b5fac469ed0e47a032bf38c9e8d75739465fa659cc1d4d61a156054c943654b5b1a6b5462b33fb1ba0a51d7804ccfe088ea82e7601ae5ed1bf9a5449efa8aae9376ac2711ed010e277a0d6ca8b774bcf95ed32f4f346f3e334f6393788e068fe5b9c4bf8587748f67bf0a095bd4aa36b965ac3b87f4f4da74c7733435d3cf79474b8f9246052096bbc3f03a0fe15d293a3e6cfcf766a915498b038a3fb28e6db194b42106831cde5cdad48d9a076d4a753e7b873269515c60291cbdf26f52a218735ca1399fde86dce36f8ade3a0338d465e52fb472f2d12788d03b22d0c9fcdd6224ef73c114d153a2e49cb322ea0484a5e7df4ff5319ca78d07211b89bcf0dc3ccbdeae8563d31aa644e9c2ef22ea0bb1e7d0bbda92fc18e40f54b90aa9b26c7ebd950e07ef2f45bcb744f0304f30480"
        );
        accountProofList[1] = RLP.encode(
            hex"f90211a0d9595c35e1e689fb1561039e08d66b2fb23d11ab966c8f4c3778ea1e6e1a525ca00af85211e3bf3a227e81b849767c7cfcda320457b8d4ade04e0927b8690bfb27a0c8e3444abaa0adff441f3abdd6e68820285616319154a7d4dcea50a58ef670f9a0c44739ea6bcbe5fea9f3daa3dcc80b1598b956a69eb906089e8929c042ddef3ba0b0cd38f1002cf6d9d76aaf2ed94baba6b34209b38662151111d2e67ad874fbfaa0e791e8ca9fbd4af504f484fada447f440d245e647e4b25236535d57bf6a0247ea03cf7749165fa81377d5ae438df0023a76a1cdbaae582f026a1f4a33487f46cb8a075782af998e1c0d0ad3d45e5f7f60bdf094114a1d91ab7aff17c01a249c0d591a0269ca516d1f5bf9633f4c3f088decf98ff0aa6ecf8010bed9282417b9a40514ea0975958f99f7f882a43d145a7004d86cffea1d7bd47e4743ac8591e1370af7c87a0a52be157e3d3735ccd7b70810dd4f5b8dc2bf93c0f8cb1e5b6099de0b408300ea03160c5fb073619be4bbf4c5395ba8088471779297d1920c4f8e6367e51e35e49a02342b7acb077299a819d7d324adc4d141942714fc7a522c73649e239fe010508a08950b87a5b5c626d6914b3b9efe9f14c8b48655362a17c1bb4fc67e6e541d5c3a00515e77dace3066455f8b6fc2267d35e8b2e1bda947d4d0f249e2890c5e3d251a0d591d436c00345c54cd588e196ff0f91835f39cf538a039df94555c7e7294ca880"
        );
        accountProofList[2] = RLP.encode(
            hex"f90211a01a4198c0f5ce8b5d394cb42a6b59b7d0c666bf61bc50bf048670cf0737855fdca0895cccc84959ac6392f0ec1e5e9dbac24c6d1e3fe684fcaa5e9ecdbf0696c144a0a2ed8b41e0a718bb7b800db1612497088bc7839ebe099a762daf9a446c19ac42a0495fde26bf761a71317e017e0351ad61fb09d5ded1cdfd14cc6ab0f9ba1e7cf8a091aade5c90cd00386f964e1f9e468a5fc30e26ba052b28edc95b16307825992ba05c3066c65c561d4b87c043d6ec8ff144c761fde69ad32b2679a976d17dc668cca09f6cc72b8c372908f42a942fbea0efa82e367a3d27eba7a7a8d1b461f24855e6a09408510fcb45f702e9c0b2f189704c8b50cdc86436574f347d5de02179511c1ca01a62e2d29a307572c6df2ea7162a5f2aadbb1028d521f3ec470d94d9d5a8a162a0bce9be38d51d2aa47e8cabfc2637dff161646e6e7f40922b160cbf292eeaf69da073ac4f5f3c162e11349a7e2fbf751859cd829a434e2cc1bd49187715463f494aa089c8aa06113765e7e68697ef16c5a26753a989903d5626edf41cdf21f6860552a01701293ca754ea65ae893d0705226f63d1795b775f671011d23f6e2f661b87f4a09ea77441ed691b51c643befa090c72e7408622e008f5f5df2c1d400811ecd589a01e1e427f5e2964520e4b9e818ee44d7f56678f91fc32f0759ee8b0c0b76f654da0d55d93e68fe5d21766bcf487fb898b2c61781a6763fdff779fc2241417d9db7280"
        );
        accountProofList[3] = RLP.encode(
            hex"f90211a0c5d06e34ca79ed78c18adb7affe8742de2e58201fca0bf436c828d8232f6d0baa0fab5b29e06466da3c3792a890153738a3035f7d20274e6f8b60ecf72fa1e789fa078c4744aee74da56cfd2f1d2fa609a7118b05420253f779c53d96c7145e982b9a042f2ae0ae4e1cbe72b2f295bfe252c4ace3fb83a8e964557616ee9bd228566f3a0fcbd0da6912cc1cf44e4a1553a66aefe6f9642b74963f480058cf7a1cabf4b36a00d5c5c04878ec0c07b56b1374dbc37a6051e94ff55557ee68534666fb0f02895a0b0009ef22aee2091cad38c0fc04126008ebb3c1ec85e0ee015c45afda40d814ba076e3e653cc38062bed7b583bc89addd852efd3777a8c7b6c9767cb17b84fe996a016503e66b0b417bc130207b84b29b2b1a2471047b2d26b97d8318087d8b28a90a09677de7562ade630ae4c2f2aa639af5a71b801b88c54036536beb7ea3f4da20ba0a26fd6ee4ba73135e022a86543f110c8cff8fc196da70476728e29afa53abbd4a0b6b02ed8681c67bbcdbaa4250a9a8b2af9553990ebd9c415e61ba89922d38563a0416f8fa03b7c8e16437a8a0b1c6e73ce375f369cdb620ded8d95504b3ab67a06a0c1342004868ff43da6430fd9dd0d6a1d9ced88b454d5a48c79c41fe4565129eca0e45241b73f4d329f4fe909401f9aa76b7e46162e6fc3dd81be819d1c06acff51a0f71ec474fdd9230f7292c0c4002f2b5603325868486ccd93c14de53f65fb6e6480"
        );
        accountProofList[4] = RLP.encode(
            hex"f90211a0e54f82daf54b26973f584016ca833654dee0a659464428fe1ce53097380bc2d0a097a696b4cd659cb0fe2f87d9a5f8fee87a032ff6ac95489fb985103bf232aca5a001b9af9e74ac1132eb2f9c20ac950178ea066a1bf67898b2bfa908b374881015a0592e35261c24a24435af64b11a177cbc346f4a0c91d4eb9b229ac373e8a9e5eea0a6d5d2e84b5e6a32f5aeaddb2635e7c78de78c8a45c2a609e628364ac88fd1e4a0a1ce8455d7a9a560bef917b5bab4be927586f070ba515c75a1b58d86883679a7a03b1e2c4c3adb9611b891605f206f6feba27c1e8f0dc971785d871f8aa5a6c71ca05af4aa3a2323e521a2ccf5d74bb29c343e89bdfd5a056ba00b117e751adfc4eba0df4cbfa36a4af781876cc0b172fbc3752933f0bed3f4dcb38642b4b5e3b95535a088bed8ddd0b03ad9d519643589e106daf8b0a6ee7510efb3ffc436b6d08c385aa0cfa4a71af2c4ee6856b64199be680df4f04987d28dc707b9b81b1ae2135342aca007f48265cb2cb83f63518a4f813f344836cc4ccf969eff0a0d8bf98bf4570d90a0f189aeb9c6a9c5517d6940b57a5bf3c61fa9a589a35bab963a15176731d3ab76a00e51492b77450e0544151e6b16c9a24e6b1d316a5cc992bd0f52bb846dae23bfa0dfe5989673399538a7dfece6561477b803a0f0cbf3064dbb5b7be8a39deac533a02ca0c5810e279a986c31d251c1d3413cb505a03bc85c172bdce8a6b35e276dfb80"
        );
        accountProofList[5] = RLP.encode(
            hex"f90211a02614da908a4849f529b99e68ca69202ced4848b3bf6d1588d107535056e63eeca00477bfd2aecc7a0914f087efee823ae72a6b723d960a55e6c0c931917410b91ba000b6602e9ad6a574bda8edd73f36dc19bf59e8f07cbef550c6e62ad8d7837275a080181a744c9ce8bfb3ac8ea4f5fde39c5dd5123d768cd672ad8724e70d7d263fa06f4f223a69c0872022884fb78088456e2871fabb67946a5c3aa1c2fc97067f53a0789e4ffbb34e200bb32122488867a04c6af28be25d7ce3627219eeb27da1d1e6a083bcf68bd3418e85c3ffe8721a9e98aa51eb1f8eb96e0b8c8c94084636e8b9fda01d55714ed9e4b5394924f8e7514374cfe5757a4e512a66bc6b61ed6bd99ae3d4a0f253938718dbf4377cd93103862dbb45f1077405a2d3a57738d45a1fac21553da059b843bad4688ecb2ddee56c13a7c990ed84efe655eb0fee8d06cbd4f52886fba017e2ac27459cbf0133cc9f9c2623e029c71137764368f57e2de62070011b74dda0d77d24119a2950d6b4f90eebbd4d5342f592f3c8f9980debed42ebd0004d5ecda0c64c80f579948559cd119490389c1370348b031a1ab72ec84ae18a783dfd49aea04fcff07c044cbc30b26ca0fc41d2ec474506fab38bbbbb582519f09543e2ea13a0ffbb5ce620fc8e2b39ee70b18dab1fd31dabf7a1361232db072b5534d6c45ea3a047aec790619add4898883dd60be479887cd8bb312ffb92c7f253c5162a9d33a180"
        );
        accountProofList[6] = RLP.encode(
            hex"f8b1a0c7491b416a7a20bfc78fe1f7a4518958524b539c331c25ebb60cb7d651e94c4b8080808080808080a07d39eba3b1cab99692c17e368f1506b4c9d1270b6bdbeed83253143a9f51efa38080a082a3f66f1fdba2188333439a63fea1632b0a504d1735fe45dcdbc750c980d74aa0e76eeb8f7a7ff529ca36d01f44bffa3e85b363a8d6a2b2c9d25c2114dac70689a043b641bafe98b738fff861b3875f87245830c1d29a7c0d411d1da3958fa0f3e18080"
        );
        accountProofList[7] = RLP.encode(
            hex"f8669d35ea91a4f74675160ac2ae6e03f04be23fbf7e800eb88db12c6f5904c0b846f8440180a0c672639a72b537f19eaae20d66e47cd1d977ac18ed81e0bba3b200f671e5bcd1a03debe8ce6033a7570465c1bd57dfe3c0ca9dba458721039d4d47c10d5025252b"
        );

        bytes memory accountProof = RLP.encode(accountProofList);

        bytes32 stateRoot = keccak256(
            hex"f90211a0b0b95e67e8aa61300a71afe6157bf84b39233462ea64aa0ede48cf35feaabbcfa052a9ca3ff2ca72798469a010a004a29b0ae970ce27f5ef8d998b27a9b0625207a0f3436bfd2ec36d3296cd081062f0a2bab4a4549f97f889ba5a4f9cb36290c447a064e9aceea7480537d7844b2d848b3182feabf30112e385bcb47388dd627521bba00b8fec9858a453b4a8bf04263305f54054bc078221d60332f1aa3343cc194705a0bd67eb93fad2af1a55b444b683b6b2095575453ec3d1dee0f6a7c0e53f827caea0228eb016dd6ae3ad9f848803e74d96eec8ea49929e774b8a38b5fac469ed0e47a032bf38c9e8d75739465fa659cc1d4d61a156054c943654b5b1a6b5462b33fb1ba0a51d7804ccfe088ea82e7601ae5ed1bf9a5449efa8aae9376ac2711ed010e277a0d6ca8b774bcf95ed32f4f346f3e334f6393788e068fe5b9c4bf8587748f67bf0a095bd4aa36b965ac3b87f4f4da74c7733435d3cf79474b8f9246052096bbc3f03a0fe15d293a3e6cfcf766a915498b038a3fb28e6db194b42106831cde5cdad48d9a076d4a753e7b873269515c60291cbdf26f52a218735ca1399fde86dce36f8ade3a0338d465e52fb472f2d12788d03b22d0c9fcdd6224ef73c114d153a2e49cb322ea0484a5e7df4ff5319ca78d07211b89bcf0dc3ccbdeae8563d31aa644e9c2ef22ea0bb1e7d0bbda92fc18e40f54b90aa9b26c7ebd950e07ef2f45bcb744f0304f30480"
        );

        assertEq(stateRoot, blockHeader.stateRoot);
        bytes[] memory storageProofList = new bytes[](1);

        storageProofList[0] =
            RLP.encode(hex"e8a120e9c5cc9c750ef3a170b3a02cf938ffded668959e8c4d274ee43f58103248e67e858468fa57d8");

        bytes memory storageProof = RLP.encode(storageProofList);

        bytes memory input = abi.encode(rlpBlockHeader, knownAccount, expectedSlot, accountProof, storageProof);

        ChildToParentProver childToParentProverCopy = new ChildToParentProver(childChainId);

        (address account, uint256 slot, bytes32 value) = childToParentProverCopy.verifyStorageSlot(blockHash, input);

        assertEq(account, knownAccount);
        assertEq(slot, expectedSlot);
        assertEq(value, expectedValue);
    }
}
