// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DeployHelpers } from "../../lib/evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";

import { Options } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Options.sol";

import { Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MUSD } from "../../src/MUSD.sol";

abstract contract DeployMUSDBase is DeployHelpers {
    /// @dev Same address across all supported mainnet and testnets networks.
    address public constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;

    /// @dev Same address across all supported mainnet and testnets networks.
    address public constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;

    Options public deployOptions;

    function _deployMUSD(
        address deployer,
        address mToken,
        address swapFacility,
        address yieldRecipient,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser,
        address forcedTransferManager
    ) internal returns (address implementation, address proxy, address proxyAdmin) {
        deployOptions.constructorData = abi.encode(address(mToken), address(swapFacility));

        implementation = Upgrades.deployImplementation("MUSD.sol:MUSD", deployOptions);

        bytes32 salt = _computeSalt(deployer, "MUSD");

        proxy = _deployCreate3TransparentProxy(
            implementation,
            admin,
            abi.encodeWithSelector(
                MUSD.initialize.selector,
                yieldRecipient,
                admin,
                freezeManager,
                yieldRecipientManager,
                pauser,
                forcedTransferManager
            ),
            salt
        );

        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }
}
