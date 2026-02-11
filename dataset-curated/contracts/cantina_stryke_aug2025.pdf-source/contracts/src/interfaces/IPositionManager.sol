// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IHandler} from "./IHandler.sol";

interface IPositionManager {
    function mintPosition(IHandler _handler, bytes calldata _mintPositionData)
        external
        returns (uint256 sharesMinted);

    function burnPosition(IHandler _handler, bytes calldata _burnPositionData)
        external
        returns (uint256 sharesBurned);

    function usePosition(IHandler _handler, bytes calldata _usePositionData)
        external
        returns (address[] memory tokens, uint256[] memory amounts, uint256 liquidityUsed);

    function unusePosition(IHandler _handler, bytes calldata _unusePositionData)
        external
        returns (uint256[] memory amounts, uint256 liquidity);

    function donateToPosition(IHandler _handler, bytes calldata _donatePosition)
        external
        returns (uint256[] memory amounts, uint256 liquidity);

    function wildcard(IHandler _handler, bytes calldata _wildcardData)
        external
        returns (bytes memory wildcardRetData);

    function sweepTokens(address _token, uint256 _amount) external;

    function updateWhitelistHandlerWithApp(address _handler, address _app, bool _status) external;

    function updateWhitelistHandler(address _handler, bool _status) external;

    function whitelistedHandlersWithApp(bytes32) external view returns (bool);

    function whitelistedHandlers(address) external view returns (bool);
}
