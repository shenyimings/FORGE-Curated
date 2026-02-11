// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Counter} from "./Counter.sol";
import {ECDSASignature} from "./ECDSASignature.sol";
import {Delegation} from "../src/Delegation.sol";
import {Simulation} from "../src/Simulation.sol";
import {PasskeyValidator} from "../src/validators/Passkey.sol";
import {Test} from "forge-std/Test.sol";

contract DelegationTest is ECDSASignature, Test {
    Counter counter;
    Delegation delegation;
    PasskeyValidator passkeyValidator;

    uint256 privateKey = 0xbd332231782779917708cab38f801e41b47a1621b8270226999e8e6ea344b61c;
    address payable eoa = payable(vm.addr(privateKey)); // 0xD1fa593A9cc041e1CB82492B9CE17f2187fEdB72

    function setUp() public {
        counter = new Counter();
        delegation = new Delegation();
        passkeyValidator = new PasskeyValidator();

        // set EIP-7702 delegation
        vm.etch(eoa, abi.encodePacked(hex"ef0100", address(delegation)));

        // etch P256 verifier
        vm.etch(
            0x000000000000D01eA45F9eFD5c54f037Fa57Ea1a,
            hex"3d604052610216565b60008060006ffffffffeffffffffffffffffffffffff60601b19808687098188890982838389096004098384858485093d510985868b8c096003090891508384828308850385848509089650838485858609600809850385868a880385088509089550505050808188880960020991505093509350939050565b81513d83015160408401516ffffffffeffffffffffffffffffffffff60601b19808384098183840982838388096004098384858485093d510985868a8b096003090896508384828308850385898a09089150610102848587890960020985868787880960080987038788878a0387088c0908848b523d8b015260408a0152565b505050505050505050565b81513d830151604084015185513d87015160408801518361013d578287523d870182905260408701819052610102565b80610157578587523d870185905260408701849052610102565b6ffffffffeffffffffffffffffffffffff60601b19808586098183840982818a099850828385830989099750508188830383838809089450818783038384898509870908935050826101be57836101be576101b28a89610082565b50505050505050505050565b808485098181860982828a09985082838a8b0884038483860386898a09080891506102088384868a0988098485848c09860386878789038f088a0908848d523d8d015260408c0152565b505050505050505050505050565b6020357fffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc6325513d6040357f7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a88111156102695782035b60206108005260206108205260206108405280610860526002830361088052826108a0526ffffffffeffffffffffffffffffffffff60601b198060031860205260603560803560203d60c061080060055afa60203d1416837f5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b8585873d5189898a09080908848384091484831085851016888710871510898b108b151016609f3611161616166103195760206080f35b60809182523d820152600160c08190527f6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2966102009081527f4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f53d909101526102405261038992509050610100610082565b610397610200610400610082565b6103a7610100608061018061010d565b6103b7610200608061028061010d565b6103c861020061010061030061010d565b6103d961020061018061038061010d565b6103e9610400608061048061010d565b6103fa61040061010061050061010d565b61040b61040061018061058061010d565b61041c61040061020061060061010d565b61042c610600608061068061010d565b61043d61060061010061070061010d565b61044e61060061018061078061010d565b81815182350982825185098283846ffffffffeffffffffffffffffffffffff60601b193d515b82156105245781858609828485098384838809600409848586848509860986878a8b096003090885868384088703878384090886878887880960080988038889848b03870885090887888a8d096002098882830996508881820995508889888509600409945088898a8889098a098a8b86870960030908935088898687088a038a868709089a5088898284096002099950505050858687868709600809870387888b8a0386088409089850505050505b61018086891b60f71c16610600888a1b60f51c16176040810151801585151715610564578061055357506105fe565b81513d8301519750955093506105fe565b83858609848283098581890986878584098b0991508681880388858851090887838903898a8c88093d8a015109089350836105b957806105b9576105a9898c8c610008565b9a509b50995050505050506105fe565b8781820988818309898285099350898a8586088b038b838d038d8a8b0908089b50898a8287098b038b8c8f8e0388088909089c5050508788868b098209985050505050505b5082156106af5781858609828485098384838809600409848586848509860986878a8b096003090885868384088703878384090886878887880960080988038889848b03870885090887888a8d096002098882830996508881820995508889888509600409945088898a8889098a098a8b86870960030908935088898687088a038a868709089a5088898284096002099950505050858687868709600809870387888b8a0386088409089850505050505b61018086891b60f51c16610600888a1b60f31c161760408101518015851517156106ef57806106de5750610789565b81513d830151975095509350610789565b83858609848283098581890986878584098b0991508681880388858851090887838903898a8c88093d8a01510908935083610744578061074457610734898c8c610008565b9a509b5099505050505050610789565b8781820988818309898285099350898a8586088b038b838d038d8a8b0908089b50898a8287098b038b8c8f8e0388088909089c5050508788868b098209985050505050505b50600488019760fb19016104745750816107a2573d6040f35b81610860526002810361088052806108a0523d3d60c061080060055afa898983843d513d510987090614163d525050505050505050503d3df3fea264697066735822122063ce32ec0e56e7893a1f6101795ce2e38aca14dd12adb703c71fe3bee27da71e64736f6c634300081a0033"
        );
    }

    function testExecute() public {
        bytes32 mode = 0x0100000000000000000000000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        vm.prank(eoa);
        Delegation(eoa).execute(mode, abi.encode(calls));
        assertEq(counter.value(), 1);
    }

    function testExecuteRevert() public {
        bytes32 mode = 0x0100000000000000000000000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        vm.expectRevert(Delegation.Unauthorized.selector);
        Delegation(eoa).execute(mode, abi.encode(calls));
    }

    function testExecuteECDSA() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key = 0;
        uint256 nonce = delegation.getNonce(key);

        bytes memory sig = _generateECDSASig(vm, delegation, privateKey, mode, calls, nonce);
        bytes memory opData = abi.encodePacked(key, sig);

        Delegation(eoa).execute(mode, abi.encode(calls, opData));
        assertEq(counter.value(), 1);
    }

    function testExecuteECDSARevert() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key = 0;
        uint256 nonce = delegation.getNonce(key);

        uint256 invalidPrivateKey =
            vm.deriveKey("test test test test test test test test test test test junk", 0);
        bytes memory sig = _generateECDSASig(vm, delegation, invalidPrivateKey, mode, calls, nonce);
        bytes memory opData = abi.encodePacked(key, sig);

        vm.expectRevert(Delegation.Unauthorized.selector);
        Delegation(eoa).execute(mode, abi.encode(calls, opData));
    }

    function testSimulateExecuteECDSA() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key = 0;
        uint256 nonce = delegation.getNonce(key);

        uint256 invalidPrivateKey =
            vm.deriveKey("test test test test test test test test test test test junk", 0);
        bytes memory sig = _generateECDSASig(vm, delegation, invalidPrivateKey, mode, calls, nonce);
        bytes memory opData = abi.encodePacked(key, sig);

        vm.etch(eoa, vm.getCode("Simulation.sol:Simulation"));
        Simulation(eoa).simulateExecute(mode, abi.encode(calls, opData));
    }

    function testParallelNonceOrders() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key1 = 0;
        uint192 key2 = 11111;

        uint256 nonce1 = Delegation(eoa).getNonce(key1);
        uint256 nonce2 = Delegation(eoa).getNonce(key2);

        bytes memory sig1 = _generateECDSASig(vm, delegation, privateKey, mode, calls, nonce1);
        bytes memory sig2 = _generateECDSASig(vm, delegation, privateKey, mode, calls, nonce2);

        bytes memory opData1 = abi.encodePacked(key1, sig1);
        bytes memory opData2 = abi.encodePacked(key2, sig2);

        uint256 expectedNonce1 = (uint256(key1) << 64) | uint64(1);
        uint256 expectedNonce2 = (uint256(key2) << 64) | uint64(1);

        uint256 state = vm.snapshotState();

        // Test first order
        Delegation(eoa).execute(mode, abi.encode(calls, opData1));
        Delegation(eoa).execute(mode, abi.encode(calls, opData2));

        assertEq(counter.value(), 2);
        assertEq(Delegation(eoa).getNonce(key1), expectedNonce1);
        assertEq(Delegation(eoa).getNonce(key2), expectedNonce2);

        vm.revertToState(state);

        // Test second order
        Delegation(eoa).execute(mode, abi.encode(calls, opData2));
        Delegation(eoa).execute(mode, abi.encode(calls, opData1));

        assertEq(counter.value(), 2);
        assertEq(Delegation(eoa).getNonce(key1), expectedNonce1);
        assertEq(Delegation(eoa).getNonce(key2), expectedNonce2);
    }

    function testExecutePasskeyValidator() public {
        bytes32 keyHash;

        // add passkey validator module
        {
            bytes32 mode = 0x0100000000000000000000000000000000000000000000000000000000000000;

            Delegation.Call[] memory calls = new Delegation.Call[](1);
            calls[0].to = eoa;
            calls[0].data =
                abi.encodeWithSelector(delegation.addValidator.selector, passkeyValidator);

            vm.prank(eoa);
            Delegation(eoa).execute(mode, abi.encode(calls));
        }

        // add passkey signer
        {
            bytes32 mode = 0x0100000000000000000000000000000000000000000000000000000000000000;

            bytes memory pubkey =
                hex"c61b3c129ac2fa5f1c74a454e401878202f569389cd3c11b6e48ed2442237592362db9511fbb32dcff1ad36476a9f2a19fd505c6d937e142443cd5193877d583";

            keyHash = keccak256(pubkey);

            Delegation.Call[] memory calls = new Delegation.Call[](1);
            calls[0].to = address(passkeyValidator);
            calls[0].data = abi.encodeWithSelector(passkeyValidator.addSigner.selector, pubkey);

            vm.prank(eoa);
            Delegation(eoa).execute(mode, abi.encode(calls));
        }

        // execute using passkey validator module
        {
            bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

            bytes memory passkeySignature =
                hex"002549960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631d000000007b2274797065223a22776562617574686e2e676574222c226368616c6c656e6765223a2279626466714e32704553776769597443545353386c6565615568726c314f5053755559655f734572637145222c226f726967696e223a22687474703a2f2f6c6f63616c686f73743a31323334222c2263726f73734f726967696e223a66616c73657d00170001f542e63088696a398fcc9b3670b46375e7b8852163e17ee934c8550facc062c56f618f881ae76b5a37b672ed4c4ded8135a97f1e1873878dad0777b3c53d575e";

            Delegation.Call[] memory calls = new Delegation.Call[](1);
            calls[0].to = address(counter);
            calls[0].data = abi.encodeWithSelector(counter.increment.selector);

            uint192 key = 0;

            bytes memory data = abi.encode(keyHash, passkeySignature);
            bytes memory signature = abi.encodePacked(passkeyValidator, data);
            bytes memory opData = abi.encodePacked(key, signature);

            Delegation(eoa).execute(mode, abi.encode(calls, opData));
            assertEq(counter.value(), 1);
        }
    }

    function testExecutePasskeyValidatorRevert() public {
        bytes32 keyHash;

        // add passkey validator module
        {
            bytes32 mode = 0x0100000000000000000000000000000000000000000000000000000000000000;

            Delegation.Call[] memory calls = new Delegation.Call[](1);
            calls[0].to = eoa;
            calls[0].data =
                abi.encodeWithSelector(delegation.addValidator.selector, passkeyValidator);

            vm.prank(eoa);
            Delegation(eoa).execute(mode, abi.encode(calls));
        }

        // we don't add the passkey signer here so we expect a revert with `Unauthorized`

        // execute using passkey validator module
        {
            bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

            bytes memory passkeySignature =
                hex"002549960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97631d000000007b2274797065223a22776562617574686e2e676574222c226368616c6c656e6765223a2279626466714e32704553776769597443545353386c6565615568726c314f5053755559655f734572637145222c226f726967696e223a22687474703a2f2f6c6f63616c686f73743a31323334222c2263726f73734f726967696e223a66616c73657d00170001f542e63088696a398fcc9b3670b46375e7b8852163e17ee934c8550facc062c56f618f881ae76b5a37b672ed4c4ded8135a97f1e1873878dad0777b3c53d575e";

            Delegation.Call[] memory calls = new Delegation.Call[](1);
            calls[0].to = address(counter);
            calls[0].data = abi.encodeWithSelector(counter.increment.selector);

            uint192 key = 0;

            bytes memory data = abi.encode(keyHash, passkeySignature);
            bytes memory signature = abi.encodePacked(passkeyValidator, data);
            bytes memory opData = abi.encodePacked(key, signature);

            vm.expectRevert(Delegation.Unauthorized.selector);
            Delegation(eoa).execute(mode, abi.encode(calls, opData));
        }
    }
}
