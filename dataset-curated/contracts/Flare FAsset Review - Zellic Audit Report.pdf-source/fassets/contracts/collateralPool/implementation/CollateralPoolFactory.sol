// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IICollateralPoolFactory} from "../../collateralPool/interfaces/IICollateralPoolFactory.sol";
import {CollateralPool} from "./CollateralPool.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {AgentSettings} from "../../userInterfaces/data/AgentSettings.sol";
import {IICollateralPool} from "../../collateralPool/interfaces/IICollateralPool.sol";

contract CollateralPoolFactory is IICollateralPoolFactory, IERC165 {
    using SafeCast for uint256;

    address public implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function create(
        IIAssetManager _assetManager,
        address _agentVault,
        AgentSettings.Data memory _settings
    )
        external override
        returns (IICollateralPool)
    {
        address fAsset = address(_assetManager.fAsset());
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, new bytes(0));
        CollateralPool pool = CollateralPool(payable(address(proxy)));
        pool.initialize(_agentVault, address(_assetManager), fAsset,
            _settings.poolExitCollateralRatioBIPS.toUint32());
        return pool;
    }

    /**
     * Returns the encoded init call, to be used in ERC1967 upgradeToAndCall.
     */
    function upgradeInitCall(address /* _proxy */) external pure override returns (bytes memory) {
        // This is the simplest upgrade implementation - no init method needed on upgrade.
        // Future versions of the factory might return a non-trivial call.
        return new bytes(0);
    }

    /**
     * Implementation of ERC-165 interface.
     */
    function supportsInterface(bytes4 _interfaceId)
        external pure override
        returns (bool)
    {
        return _interfaceId == type(IERC165).interfaceId
            || _interfaceId == type(IICollateralPoolFactory).interfaceId;
    }
}
