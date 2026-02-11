// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SetRole} from "script/configuration/SetRole.s.sol";
import {mTokenConfiguration} from "src/mToken/mTokenConfiguration.sol";

interface ITransferOwnership {
    function transferOwnership(address _addr) external;
}

contract TransferOwnership is Script {
    bytes32 public constant REBALANCER = keccak256("REBALANCER");
    bytes32 public constant PAUSE_MANAGER = keccak256("PAUSE_MANAGER");
    bytes32 public constant REBALANCER_EOA = keccak256("REBALANCER_EOA");
    bytes32 public constant GUARDIAN_PAUSE = keccak256("GUARDIAN_PAUSE");
    bytes32 public constant CHAINS_MANAGER = keccak256("CHAINS_MANAGER");
    bytes32 public constant PROOF_FORWARDER = keccak256("PROOF_FORWARDER");
    bytes32 public constant PROOF_BATCH_FORWARDER = keccak256("PROOF_BATCH_FORWARDER");
    bytes32 public constant SEQUENCER = keccak256("SEQUENCER");
    bytes32 public constant GUARDIAN_BRIDGE = keccak256("GUARDIAN_BRIDGE");
    bytes32 public constant GUARDIAN_ORACLE = keccak256("GUARDIAN_ORACLE");
    bytes32 public constant GUARDIAN_RESERVE = keccak256("GUARDIAN_RESERVE");
    bytes32 public constant GUARDIAN_BORROW_CAP = keccak256("GUARDIAN_BORROW_CAP");
    bytes32 public constant GUARDIAN_SUPPLY_CAP = keccak256("GUARDIAN_SUPPLY_CAP");

    function run() public virtual {
        uint256 key = vm.envUint("PRIVATE_KEY");

        //initialization
        address hyperNative = 0xF8B6314e66EA3e4b62e229fa5F5F052058618404;
        address oldOwner = 0xB819A871d20913839c37f316Dc914b0570bfc0eE;
        address multisig = 0x91B945CbB063648C44271868a7A0c7BdFf64827D;
        address rolesContract = 0x1211d07F0EBeA8994F23EC26e1e512929FC8Ab08;
        address[] memory markets = new address[](8);
        markets[0] = 0x269C36A173D881720544Fb303E681370158FF1FD;
        markets[1] = 0xC7Bc6bD45Eb84D594f51cED3c5497E6812C7732f;
        markets[2] = 0xDF0635c1eCfdF08146150691a97e2Ff6a8Aa1a90;
        markets[3] = 0x2B588F7f4832561e46924F3Ea54C244569724915;
        markets[4] = 0x1D8e8cEFEb085f3211Ab6a443Ad9051b54D1cd1a;
        markets[5] = 0x0B3c6645F4F2442AD4bbee2e2273A250461cA6f8;
        markets[6] = 0x8BaD0c523516262a439197736fFf982F5E0987cC;
        markets[7] = 0x4DF3DD62DB219C47F6a7CB1bE02C511AFceAdf5E;

        address[] memory interests = new address[](8);
        interests[0] = 0xe4165FA4231c0C41F71B93dB464e1f31937e3302;
        interests[1] = 0x56310b8f82F3709B41aDf971ECC82F7e04E65Eea;
        interests[2] = 0x74eb5ebCB998A227eAe8C2A5AaF594072da2100a;
        interests[3] = 0x9B330aEA1A68BdE41fc81C1ba280098F09C969C3;
        interests[4] = 0xc552Cd2c7A4FE618E63C42438B1108361A568009;
        interests[5] = 0x7574Fa32896Ece5b5127F6b44B087F4387344ef4;
        interests[6] = 0x1f0C88a6FF8daB04307fc9d6203542583Db9F336;
        interests[7] = 0xabEe4794832EaeaE25eE972D47C0ac540d8BBB2f;

        address zkVerifier = 0xE32Fc580E6e3f6f5947BC2d900062DCe019F375f;
        address pauser = 0xDdCca3eDa77622B7Ff5b7f11b340A8F818a87d2C;
        address operator = 0x05bD298c0C3F34B541B42F867BAF6707911BE437;
        address batchSubmitter = 0x04f0cDc5a215dEdf6A1Ed5444E07367e20768041;
        bool isHost = true;
        SetRole setRole = new SetRole();

        // add new roles
        console.log("Adding new roles");
        setRole.run(rolesContract, hyperNative, PAUSE_MANAGER, true);
        setRole.run(rolesContract, multisig, PAUSE_MANAGER, true);
        setRole.run(rolesContract, multisig, GUARDIAN_PAUSE, true);
        setRole.run(rolesContract, multisig, CHAINS_MANAGER, true);
        setRole.run(rolesContract, multisig, PROOF_FORWARDER, true);
        setRole.run(rolesContract, multisig, PROOF_BATCH_FORWARDER, true);
        setRole.run(rolesContract, multisig, GUARDIAN_BRIDGE, true);
        setRole.run(rolesContract, multisig, GUARDIAN_ORACLE, true);
        setRole.run(rolesContract, multisig, GUARDIAN_RESERVE, true);
        setRole.run(rolesContract, multisig, GUARDIAN_BORROW_CAP, true);
        setRole.run(rolesContract, multisig, GUARDIAN_SUPPLY_CAP, true);
        console.log("Roles added");

        // remove old roles
        console.log("Remove old roles");
        setRole.run(rolesContract, oldOwner, PAUSE_MANAGER, false);
        setRole.run(rolesContract, oldOwner, GUARDIAN_PAUSE, false);
        setRole.run(rolesContract, oldOwner, CHAINS_MANAGER, false);
        setRole.run(rolesContract, oldOwner, PROOF_FORWARDER, false);
        setRole.run(rolesContract, oldOwner, PROOF_BATCH_FORWARDER, false);
        setRole.run(rolesContract, oldOwner, GUARDIAN_BRIDGE, false);
        setRole.run(rolesContract, oldOwner, GUARDIAN_ORACLE, false);
        setRole.run(rolesContract, oldOwner, GUARDIAN_RESERVE, false);
        setRole.run(rolesContract, oldOwner, GUARDIAN_BORROW_CAP, false);
        setRole.run(rolesContract, oldOwner, GUARDIAN_SUPPLY_CAP, false);
        console.log("Roles removed");

        vm.startBroadcast(key);
        // transfer ownership

        if (isHost) {
            console.log("Transfer markets admin for host");
            //call setPendingAdmin on all markets
            for (uint256 i; i < markets.length; i++) {
                mTokenConfiguration(markets[i]).setPendingAdmin(payable(multisig));
            }
            console.log("Pending admin set");
        } else {
            console.log("Transfer markets owner for extension");
            for (uint256 i; i < markets.length; i++) {
                if (i != 5) {
                    //ezEth available only on Linea
                    ITransferOwnership(markets[i]).transferOwnership(multisig);
                }
            }
            console.log("Owner set");
        }

        console.log("Transfer ZkVerifier owner");
        ITransferOwnership(zkVerifier).transferOwnership(multisig);
        console.log("Owner set");

        console.log("Transfer Pauser owner");
        ITransferOwnership(pauser).transferOwnership(multisig);
        console.log("Owner set");

        console.log("Transfer Roles owner");
        ITransferOwnership(rolesContract).transferOwnership(multisig);
        console.log("Owner set");

        console.log("Transfer BatchSubmitter owner");
        ITransferOwnership(batchSubmitter).transferOwnership(multisig);
        console.log("Owner set");

        if (isHost) {
            console.log("Transfer Operator owner");
            ITransferOwnership(operator).transferOwnership(multisig);
            console.log("Owner set");

            console.log("Transfer interest models owner");
            for (uint256 i; i < interests.length; i++) {
                ITransferOwnership(interests[i]).transferOwnership(multisig);
            }
            console.log("Owner set");
        }

        vm.stopBroadcast();
    }
}
