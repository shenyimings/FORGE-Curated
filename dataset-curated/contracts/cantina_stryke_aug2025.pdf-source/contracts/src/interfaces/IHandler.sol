// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

interface IHandler {
    struct HookPermInfo {
        bool onMint;
        bool onBurn;
        bool onUse;
        bool onUnuse;
        bool onDonate;
        bool allowSplit;
    }

    function registerHook(address _hook, HookPermInfo memory _info) external;

    function getHandlerIdentifier(bytes calldata _data) external view returns (uint256 handlerIdentifierId);

    function tokensToPullForMint(bytes calldata _mintPositionData)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);

    function mintPositionHandler(address context, bytes calldata _mintPositionData)
        external
        returns (uint256 sharesMinted);

    function burnPositionHandler(address context, bytes calldata _burnPositionData)
        external
        returns (uint256 sharesBurned);

    function usePositionHandler(bytes calldata _usePositionData)
        external
        returns (address[] memory tokens, uint256[] memory amounts, uint256 liquidityUsed);

    function wildcardHandler(address context, bytes calldata _wildcardData)
        external
        returns (bytes memory wildcardRetData);

    function tokensToPullForUnUse(bytes calldata _unusePositionData)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);

    function unusePositionHandler(bytes calldata _unusePositionData)
        external
        returns (uint256[] memory amounts, uint256 liquidity);

    function donateToPosition(bytes calldata _donatePosition)
        external
        returns (uint256[] memory amounts, uint256 liquidity);

    function tokensToPullForDonate(bytes calldata _donatePosition)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);

    function tokensToPullForWildcard(bytes calldata _wildcardData)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);
}
