// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Receiver} from "../src/contracts/Receiver.sol";
import {IReceiver} from "../src/contracts/interfaces/IReceiver.sol";
import {IBlockHashProver} from "../src/contracts/interfaces/IBlockHashProver.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {IBlockHashProverPointer} from "../src/contracts/interfaces/IBlockHashProverPointer.sol";
import {BLOCK_HASH_PROVER_POINTER_SLOT} from "../src/contracts/BlockHashProverPointer.sol";
import {BlockHeaders} from "./utils/BlockHeaders.sol";
import {IBuffer} from "block-hash-pusher/contracts/interfaces/IBuffer.sol";

import {ChildToParentProver as ArbChildToParentProver} from "../src/contracts/provers/arbitrum/ChildToParentProver.sol";
import {ParentToChildProver as ArbParentToChildProver} from "../src/contracts/provers/arbitrum/ParentToChildProver.sol";
import {BlockHashProverPointer} from "../src/contracts/BlockHashProverPointer.sol";
import {RLP} from "@openzeppelin/contracts/utils/RLP.sol";

contract ReceiverTest is Test {
    Receiver public receiver;

    uint256 public ethereumForkId;
    uint256 public arbitrumForkId;

    IOutbox public outbox;

    address owner = makeAddr("owner");

    function setUp() public {
        ethereumForkId = vm.createFork(vm.envString("ETHEREUM_RPC_URL"));
        arbitrumForkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"));

        vm.selectFork(arbitrumForkId);
        outbox = IOutbox(0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F);
    }

    function test_verifyBroadcastMessage_from_Ethereum_into_Arbitrum() public {
        vm.selectFork(arbitrumForkId);

        receiver = new Receiver();
        ArbChildToParentProver childToParentProver = new ArbChildToParentProver(block.chainid);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(childToParentProver));

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

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(blockNumber);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        assertEq(
            broadcasterId,
            keccak256(
                abi.encode(
                    keccak256(
                        abi.encode(
                            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                            address(blockHashProverPointer)
                        )
                    ),
                    knownAccount
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(timestamp, uint256(expectedValue), "wrong timestamp");
    }

    function test_verifyBroadcastMessage_from_Arbitrum_into_Ethereum() public {
        vm.selectFork(ethereumForkId);

        receiver = new Receiver();
        ArbParentToChildProver parentToChildProver = new ArbParentToChildProver(address(outbox), 3);

        BlockHashProverPointer blockHashProverPointer = new BlockHashProverPointer(owner);

        vm.prank(owner);
        blockHashProverPointer.setImplementationAddress(address(parentToChildProver));

        bytes32 message = 0x0000000000000000000000000000000000000000000000000000000074657374; // "test"
        address publisher = 0x9a56fFd72F4B526c523C733F1F74197A51c495E1;

        uint256 expectedSlot = uint256(keccak256(abi.encode(message, publisher)));

        bytes32 expectedValue = 0x0000000000000000000000000000000000000000000000000000000068f9ca7f;

        address knownAccount = 0x40F58Bd4616a6E76021F1481154DB829953BF01B;

        uint256 blockNumber = 208802827; // block number on parent chain

        BlockHeaders.ArbitrumBlockHeader memory blockHeader = BlockHeaders.ArbitrumBlockHeader({
            parentHash: 0xfd7e900043bd4cbcd26a0b0645320afef46a9cd7762644cc399d0ddfdff4627b,
            sha3Uncles: 0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347,
            miner: 0xA4b000000000000000000073657175656e636572,
            stateRoot: 0x5c713ccb2467bdc1570ed9908c935540da985be107c4ac41026457b4bea266ef,
            transactionsRoot: 0x505b5fe0ffd7b5076915197325723373d249acf2e88a6e2f0724848e939c7e81,
            receiptsRoot: 0x15d355ec5aabfa77ebcb566bbf5c46c026cd3c56a4776804a6ee07e67e138b75,
            logsBloom: hex"02000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000040000000000000000000000000000000000001000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000000000400000000000000",
            difficulty: 1,
            number: 208802827,
            gasLimit: 1125899906842624,
            gasUsed: 458046,
            timestamp: 1761519298,
            extraData: hex"1e23f2746bb6360c8abfbd7bad53fe27e5b5aeeb277f60e71964e3e513bb2171",
            mixHash: 0x000000000001b502000000000090eb6500000000000000280000000000000000,
            nonce: 0x00000000001c82fa,
            baseFeePerGas: 100000000,
            withdrawalsRoot: 0x0000000000000000000000000000000000000000000000000000000000000000,
            blobGasUsed: 0,
            excessBlobGas: 0,
            parentBeaconBlockRoot: 0x0000000000000000000000000000000000000000000000000000000000000000,
            requestsHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            totalDifficulty: 0,
            l1BlockNumber: 9497445,
            sendCount: 111874,
            sendRoot: 0x1E23F2746BB6360C8ABFBD7BAD53FE27E5B5AEEB277F60E71964E3E513BB2171,
            arbOsVersion: 1
        });

        bytes memory rlpBlockHeader = BlockHeaders.encode(blockHeader);

        bytes32 blockHash = keccak256(rlpBlockHeader);

        bytes32 expectedBlockHash = 0x798767bf4bff59e625e0421bb871d693f9747b00930b6af8ac4576879b9b69e3;

        bytes[] memory accountProofList = new bytes[](8);
        accountProofList[0] = RLP.encode(
            hex"f90211a00b9129986fb255d29b2d7e2f4a461e481688e9500a8afbb14101022f88cb0c61a019b17164b2d46e89362a62a8d0904f6376c64ba78e88307b0cdcc4732f4d0ec1a0d97b6e1661a65c12d0f5239ae0ece57781a43daa1684a65c635b2187d81b70a5a0bad864fb0f93de180913789bbfad92596fe3e99d0934a793b395c9cb9a63218ca065b8ca0d9985c597b180098649a77a4c2721c9d9ae17beb13843037861f4f9a4a0fc9e9d59f14644096672d092a50ab3e2ae03dca6655c38a1e2b380ae22ee67c1a01aa2379ec8d494bc1c902c4f17c2302ac577bd55a0c4aa47683f50aa2b2f8140a0993a599aaf0951a5a7631919063af4402c3d641f6f9ab8725fef749d830a011ea0ca71e91fb7f11e07db9caabe5a4adc57b802de5e5dad9847d3785d463c0e84f8a0573cb59b3a8dc384e197683907d1f205d726f633bc5d93a3e79a45e4d0f7e664a0c1dc3b6d13f946a209dcc99e062ec96e12cb5e8760ae7bec8f2f9f632027f744a09facd6b3138fb5040c73d4be931178d8e94ba4038479e891e590ab8643ee9429a0899d7ab3d6437c76800613f146d5846826f8ea91fdad8b0897d9a681255d607ea09978b201587e2cf7b123786149da416db0405aa8d6195072bf78b3bab3bab685a078583fab9f202a132a240eedcaea67e7e1d6c304c2c4410a60ef7adce1158d35a0cd8732d23ba7d5c12d5077a09d5ab10e555b73605a56787b23a2d95ada8ee52a80"
        );
        accountProofList[1] = RLP.encode(
            hex"f90211a0a45ceb81cf627f01ebd877d7a1e7501f03819f06c594bd272f168a8dffede404a004d419c71859c6b9f239bc1b81feee1289201ee415ee99def2379464ed1d49c9a01e376b55e215b034f20a8d5bbc512a1aba51d8ab0b69aa719f8643762bf9627ea036bb858270464ffaff9dded0a5fda855c216799ff81bf787be379276da5434cda0fd9272fb7068deda4ecca6b38d437b7fefe6b74c2ecb05e7e3bfaca85bcc13c3a0d59e1d93e1f08724629360b1eb9750ab1a8b3a82cc2b2f795b4431ae16531bc4a009fa49c8dfb3bcbcf51bb5bb58b0a8ed5aaaf9f656a049da357cbb1008fa8984a04c65c885cc8675e63598dd35b6bf7314b86ed0e38210b4cb7dce241e66b267fca01ab557558d2788d77b0d2e19e9d18f5b229eb1e2846ddab034e1e9f100a7e515a050130f3449dcffe8c63eabbbdb373e5ac1d8334a8499925f7aa18d96403db099a08e954e2b445aa35baec29bc4c925a2df324f9faa6f082b47a72bfe67aa015295a05940c5d56de4dc3376aa52080a2a3a760c727b09cdace6680a906beef1321a14a08e7168c0dd3e44cd3e073c937ffb5a278aca63ba87cc4dedd33333ec07a2e2b9a0a725ab95003081d7ce8af7497f494a70cbb1bc60fee10bf3b3d14476eab72c23a035a7905b2a510340bc7d06965273c3afb954b525dd04c1eb876574d99f282549a0670a4b9c060c1a67c12c50df03d324edcd14212cfd1dcc0415082f49f6fe9ab580"
        );
        accountProofList[2] = RLP.encode(
            hex"f90211a08d53e6b3fafd0580b09667db7dc9b2c167662d19fcb90df7cbcb0b4bc7aac6bca0dd833cf8dc7d283077ca0f7781b44f92aab7d270010e0ef01c9c6208f23342eca0bd8cb8a8c7bd05d2f661336aed18f45c578423635c256598e76596ec53b6e530a02a35427d60862456d2d475bcee472c2142ba61dfc12268fb0f1aec160eaf0173a0944c63177d6714bfa945a6effd81cc70d0cba37191113c5e8c77ceaff9a31a83a04dc7c2c10e42358f2a6fdf0a17960cb5e76e1026272a27463ce2c51f29a0aadca041fd278d66635ba77de6978bec08102a5926c5f7ba955af18fdeb129d935f44ca05c42817184da93c34835959e256b678d703667649ce8db04ac808033d7583c25a0a04ed4cfb93738e7293be89545d673b688cd64ed3199c7ba3306b98df447699aa0719e315c6538c67afa032a40b60adf9dde9b28dbcd09322b37e3f9dded0523e1a0b1e55e484f5ffd3f56b7128889522810e00777164c8d2a407a449d58b50d5879a0669d96b619e1736ae0ce5217c9c0e13bd574807ef5b57bce2b71037c795e435aa0931b9b51ab4be5e9ef2b750b8af1311e2e9474a5ca3fce74c92c649fec496a1fa09335ca0bcd6b8250eaa98a0cb657d83ee555ce9874939b77d36d2b7cba1568c1a06fae7888799cfd79640448d26921f2c3fb1abf4d810e7591c23ea9305b2a3d47a094f654fe2a8c80e24b4521c806c07ff72077a7f90d695e0da2f93393bffbd2ce80"
        );
        accountProofList[3] = RLP.encode(
            hex"f90211a008dc273d129836dbb27a15c36d96c6fa523bd09fecd175e5f58049fa755b5e77a0c5e73650e50d9146cabc0b5eec08265a7ae75b9d2bd14a8108e0db98da5aa4b6a0813d6ab6e46744847a9c76b9015393952b7bbd7ea14157881b11bf8d226be3d8a028a3888061770c183f4ca0586006814c3644f2f9172f1a79bd0e903c358a2c8da08fd2d7f5864aee54b4ac8e3864a77928fa555e1655e558638daf16738358b5d2a0f146340af3750d21e479c29b2f29f92649834b9544ef185bb543f67f6565f739a070907ccdbbac697174478df6acf24ba701117ac1f789b3afd72b002ea0b0d455a08786b8148ab9ac7c6e60d0fd3c371c0262cc2b4738da282797a450d84f1db21aa08ad85c815ebaf5fada93b85b1ce25dd2fbc69859c12c3a8d39768641c19c0606a0a1f18891e85935c58dff069a4266d6627c40fe7e99614f71a8942eb5d3c03e6aa0d61135542c4d13f2a611cb1957bb61b57cad5650ab9a5e2ed666ac320007dbafa0787c6f8ee17ba5a824e89cee1b8f6839139700e4cbf62f62625005a07f494079a023976343f17629f2ff40512eac1a10c254db4b7b26fcfe653bcc0092f2682b4fa0760d5f582ef0e17f5e2a344bff888a95f392d5d220a828304df7745b456050f2a0189509e85a1bcd72f4fe8e16bce32e0a61c42b7f12f3275aaaad88602e9e7fc1a052e392a011c128ac0a5603a5e77e89116f23abc8297ad55295f1601996affde880"
        );
        accountProofList[4] = RLP.encode(
            hex"f90211a09cbd69967953472248f33bc7b65dbc11e51a331f31c5a5b1863f701ea7f136dfa0b8d11e00b317ccd8df52195de70410ff9b35b47c701c13b6e89c242ee4004cf2a05c596a0006f15316a1b763c297b57c66511e8cd3d552336c7b89ab04bd743ee8a0e535f7b306552ea06eb435d824c4b9e58fa6609d660df7e63595ea3e77426c4ea00e0221ccf429371d655686bcccbf582ada081a835c405eedb15c63c251040b29a012934cf1e4a01094581e3807f046c883b3fc8be7182227fb4d5f271d1745772ea0d16a6490fad1250761d787577614e8d915ea318d73ba4b7eb5f437d90c8bc042a03086df460b9506f938d2e552b6733c8ce61541f8bd1101532cedaf4df3eae2f5a001edbcfe3c65d7b7de957dd654d41f8457caf1586d425cdd0acdf3ac3bcaaafaa0e3e9b52dd3ac2b4b58c807a7b09c99bca44f9e8331ceea2e4b50097122cf43f7a0ff05a213975640dab564ee97a48e2139b56b905aa9f8e1f2ccf46787c9ddbe07a02639992585fe80ab0aa3c1c9a0509a1e3450f78d2a39b17ff6782dc4b2cc9c57a0c8c052b18b1fcb7da093118caa6fbbdd55d30ceb9eeef71b6c2f01ee51ed4d32a0adce55a5efbd2f07154a502bcbe38921319bf30cbcbe8fe0b34e5ee353a53010a006bfb31bd1c9fdf0db840190f8f6ff696671729f3e78379ec55d77fd8fee6343a037c889398e7e44c91c454a77c69f3689b294157958e90bbf1848df30a7670d7480"
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

        bytes memory accountProof = RLP.encode(accountProofList);

        bytes32 stateRoot = keccak256(
            hex"f90211a00b9129986fb255d29b2d7e2f4a461e481688e9500a8afbb14101022f88cb0c61a019b17164b2d46e89362a62a8d0904f6376c64ba78e88307b0cdcc4732f4d0ec1a0d97b6e1661a65c12d0f5239ae0ece57781a43daa1684a65c635b2187d81b70a5a0bad864fb0f93de180913789bbfad92596fe3e99d0934a793b395c9cb9a63218ca065b8ca0d9985c597b180098649a77a4c2721c9d9ae17beb13843037861f4f9a4a0fc9e9d59f14644096672d092a50ab3e2ae03dca6655c38a1e2b380ae22ee67c1a01aa2379ec8d494bc1c902c4f17c2302ac577bd55a0c4aa47683f50aa2b2f8140a0993a599aaf0951a5a7631919063af4402c3d641f6f9ab8725fef749d830a011ea0ca71e91fb7f11e07db9caabe5a4adc57b802de5e5dad9847d3785d463c0e84f8a0573cb59b3a8dc384e197683907d1f205d726f633bc5d93a3e79a45e4d0f7e664a0c1dc3b6d13f946a209dcc99e062ec96e12cb5e8760ae7bec8f2f9f632027f744a09facd6b3138fb5040c73d4be931178d8e94ba4038479e891e590ab8643ee9429a0899d7ab3d6437c76800613f146d5846826f8ea91fdad8b0897d9a681255d607ea09978b201587e2cf7b123786149da416db0405aa8d6195072bf78b3bab3bab685a078583fab9f202a132a240eedcaea67e7e1d6c304c2c4410a60ef7adce1158d35a0cd8732d23ba7d5c12d5077a09d5ab10e555b73605a56787b23a2d95ada8ee52a80"
        );

        assertEq(stateRoot, blockHeader.stateRoot);

        bytes[] memory storageProofList = new bytes[](1);
        storageProofList[0] =
            RLP.encode(hex"e8a120e9c5cc9c750ef3a170b3a02cf938ffded668959e8c4d274ee43f58103248e67e858468f9ca7f");

        bytes memory storageProof = RLP.encode(storageProofList);

        bytes memory input = abi.encode(rlpBlockHeader, knownAccount, expectedSlot, accountProof, storageProof);

        address rollup = 0x042B2E6C5E99d4c521bd49beeD5E99651D9B0Cf4;

        vm.prank(rollup);
        outbox.updateSendRoot(blockHeader.sendRoot, blockHash);

        address[] memory route = new address[](1);
        route[0] = address(blockHashProverPointer);

        bytes[] memory bhpInputs = new bytes[](1);
        bhpInputs[0] = abi.encode(blockHeader.sendRoot);

        bytes memory storageProofToLastProver = input;

        IReceiver.RemoteReadArgs memory remoteReadArgs =
            IReceiver.RemoteReadArgs({route: route, bhpInputs: bhpInputs, storageProof: storageProofToLastProver});

        (bytes32 broadcasterId, uint256 timestamp) = receiver.verifyBroadcastMessage(remoteReadArgs, message, publisher);

        assertEq(
            broadcasterId,
            keccak256(
                abi.encode(
                    keccak256(
                        abi.encode(
                            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
                            address(blockHashProverPointer)
                        )
                    ),
                    knownAccount
                )
            ),
            "wrong broadcasterId"
        );
        assertEq(timestamp, uint256(expectedValue), "wrong timestamp");
    }
}

