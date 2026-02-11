// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";

/*
forge script scripts/UpgradeFrax/test/4a_DeployAdapterImplementation.s.sol \ 
--rpc-url https://rpc.frax.com --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY
*/
contract DeployAdapterImplementation is DeployFraxOFTProtocol {
    using stdJson for string;
    using Strings for uint256;

    // address public frxUsdImplementation;
    // address public sfrxUsdImplementation;
    // address public frxUsd = 0xFc00000000000000000000000000000000000001;
    // address public sfrxUsd = 0xfc00000000000000000000000000000000000008;
    address public newCac = 0x7131F0ec2aac01a5d30138c2D96C25e4fBbc78CE;
    address public endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    function run() public override {
        deployImplementations();
    }

    function deployImplementations() internal broadcastAs(configDeployerPK) {
        address imp = address(new FraxOFTAdapterUpgradeable(newCac, endpoint));
        console.log("newCac imp @ ", imp);
        // frxUsdImplementation = address(new FraxOFTAdapterUpgradeable(frxUsd, endpoint));
        // console.log("frxUsd implementation @ ", frxUsdImplementation);
        // sfrxUsdImplementation = address(new FraxOFTAdapterUpgradeable(sfrxUsd, endpoint));
        // console.log("sfrxUsd implementation @ ", sfrxUsdImplementation);
    }
}