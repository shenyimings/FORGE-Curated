// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

import {FrxUSDOFTUpgradeable} from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";
import {SFrxUSDOFTUpgradeable} from "contracts/frxUsd/SFrxUSDOFTUpgradeable.sol";


/// @dev craft tx to upgrade the FRAX / sFRAX OFT with the new name & symbol
// TODO: add etherscan / verifier links
/// @dev forge script scripts/ops/UpgradeFrxUsd/5a_DeployUpgradedImplementations.s.sol --rpc-url https://xlayerrpc.okx.com --broadcast --legacy
/// @dev forge script scripts/ops/UpgradeFrxUsd/5a_DeployUpgradedImplementations.s.sol --rpc-url https://mainnet.mode.network --broadcast --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan' --etherscan-api-key "verifyContract" --verify
/// @dev forge script scripts/ops/UpgradeFrxUsd/5a_DeployUpgradedImplementations.s.sol --rpc-url https://twilight-crimson-grass.sei-pacific.quiknode.pro/1fe7cb5c6950df0f3ebceead37f8eefdf41ddbe9 --legacy --broadcast
contract DeployUpgradedImplementations is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    address public frxUsdImplementation;
    address public sfrxUsdImplementation;

    function run() public override {
        deployImplementations();
    }

    /// @dev same creation code as in DeployFraxOFTProtocol.deployFraxOFTUpgradeableAndProxy
    function deployImplementations() public broadcastAs(configDeployerPK) {
        // Deploy frxUSD
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FrxUSDOFTUpgradeable).creationCode),
            abi.encode(broadcastConfig.endpoint)
        );
        address implementation;
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        frxUsdImplementation = implementation;
        console.log("frxUSD Imp. @ ", frxUsdImplementation);

        // deploy sfrxUSD
        bytecode = bytes.concat(
            abi.encodePacked(type(SFrxUSDOFTUpgradeable).creationCode),
            abi.encode(broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        sfrxUsdImplementation = implementation;
        console.log("sfrxUSD Imp. @ ", sfrxUsdImplementation);
    }


}