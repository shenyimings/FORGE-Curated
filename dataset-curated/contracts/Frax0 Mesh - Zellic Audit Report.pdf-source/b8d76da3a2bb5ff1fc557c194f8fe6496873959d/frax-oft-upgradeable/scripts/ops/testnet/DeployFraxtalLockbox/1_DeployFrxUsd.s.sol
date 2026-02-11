pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { FrxUsdImplementationMock } from "contracts/mocks/FrxUsdImplementationMock.sol";
import { TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol";

// forge script scripts/ops/testnet/DeployFraxtalLockbox/1_DeployFrxUsd.s.sol --rpc-url https://rpc.testnet.frax.com --broadcast --verify --verifier etherscan --etherscan-api-key $FRAXSCAN_API_KEY
contract DeployFrxUsd is Script {

    uint256 deployerPK = vm.envUint("PK_SENDER_DEPLOYER");
    uint256 initialSupply = 1_000_000e18; // 1M frxUSD

    modifier broadcast() {
        vm.startBroadcast(deployerPK);
        _;
        vm.stopBroadcast();
    }

    function run() external broadcast {
        address frxUsdImplementation = address(new FrxUsdImplementationMock());
        new TransparentUpgradeableProxy(
            frxUsdImplementation,
            vm.addr(deployerPK), // Proxy Admin address
            abi.encodeWithSelector(
                FrxUsdImplementationMock.initialize.selector,
                "frxUSD",
                "Frax USD",
                vm.addr(deployerPK), // Initial admin
                initialSupply // Initial supply
            )
        );
    }
}