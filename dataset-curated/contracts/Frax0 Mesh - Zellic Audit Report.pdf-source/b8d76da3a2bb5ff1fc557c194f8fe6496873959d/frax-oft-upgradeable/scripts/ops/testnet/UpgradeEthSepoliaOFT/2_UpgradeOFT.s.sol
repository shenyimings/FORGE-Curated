pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { Script } from "forge-std/Script.sol";
import { FraxOFTAdapterUpgradeableStorageGap } from "contracts/mocks/FraxOFTAdapterUpgradeableStorageGap.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";

import { ERC1967Utils } from "@openzeppelin-5/contracts/proxy/ERC1967/ERC1967Utils.sol";

// forge script scripts/ops/testnet/UpgradeEthSepoliaOFT/2_UpgradeOFT.s.sol --rpc-url https://eth-sepolia.public.blastapi.io --broadcast --verify --verifier etherscan --etherscan-api-key $SEPOLIA_API_KEY
contract UpgradeOFT is DeployFraxOFTProtocol {

    address oft = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2;
    address frxUsd = 0xcA35C3FE456a87E6CE7827D1D784741613463204;

    function run() public override {

        // validate the configDeployerPK is the admin of the proxy
        bytes32 adminSlot = vm.load(oft, ERC1967Utils.ADMIN_SLOT);
        address admin = address(uint160(uint256(adminSlot)));
        require(admin == vm.addr(configDeployerPK), "Upgrade failed: configDeployerPK is not the admin of the proxy");

        // broadcast the implementation and ownership transfer
        vm.startBroadcast(configDeployerPK);

        // deploy the lockbox implementation
        address implementation = address(new FraxOFTAdapterUpgradeableStorageGap(frxUsd, broadcastConfig.endpoint));

        // upgrade the oft to lockbox
        TransparentUpgradeableProxy(payable(oft)).upgradeTo(implementation);

        // verify the implementation (only callable by the proxy admin)
        require(
            TransparentUpgradeableProxy(payable(oft)).implementation() == implementation,
            "Upgrade failed: Implementation address mismatch"
        );

        // transfer proxy admin rights to 0xb0e so that configDeployerPK can manage the OFT.  Currently,
        // with configDeployPK as the proxy admin, the OFT interface is not accessible, only the proxy interface.
        TransparentUpgradeableProxy(payable(oft)).changeAdmin(vm.addr(senderDeployerPK));

        // no more broadcasting
        vm.stopBroadcast();

        // Now that the OFT interface is exposed, we can ensure the initialize function fails (as it should since
        // the contract is already initialized).
        bytes memory data = abi.encodeCall(
            FraxOFTAdapterUpgradeable.initialize,
            (address(1))
        );
        vm.prank(vm.addr(configDeployerPK));
        (bool success, ) = oft.call(data);
        require(!success, "Upgrade failed: Initialization call succeeded unexpectedly");

       require(
            FraxOFTAdapterUpgradeable(oft).token() == frxUsd,
            "Upgrade failed: token not set"
        );

        // Verify the version
        // (uint256 major, uint256 minor, uint256 patch) = FraxOFTAdapterUpgradeable(oft).version();
        // require(major == 1 && minor == 0 && patch == 1, "Upgrade failed: Version mismatch");

        // as admin() is only callable by the proxy admin, we prank to verify
        vm.prank(vm.addr(senderDeployerPK));
        require(
            TransparentUpgradeableProxy(payable(oft)).admin() == 0xb0E1650A9760e0f383174af042091fc544b8356f,
            "Upgrade failed: Admin address mismatch"
        );
    }
}