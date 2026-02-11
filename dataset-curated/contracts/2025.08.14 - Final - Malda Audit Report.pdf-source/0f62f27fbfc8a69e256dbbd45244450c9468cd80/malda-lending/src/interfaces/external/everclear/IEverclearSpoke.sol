
// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

interface IEverclearSpoke {
    //TODO: need to fill this when available
    struct Intent {
        uint256 val;
    }

    /**
     * @notice Creates a new intent
     * @param _destinations The possible destination chains of the intent
     * @param _receiver The destinantion address of the intent
     * @param _inputAsset The asset address on origin
     * @param _outputAsset The asset address on destination
     * @param _amount The amount of the asset
     * @param _maxFee The maximum fee that can be taken by solvers
     * @param _ttl The time to live of the intent
     * @param _data The data of the intent
     * @return _intentId The ID of the intent
     * @return _intent The intent object
     */
    function newIntent(
        uint32[] memory _destinations,
        address _receiver,
        address _inputAsset,
        address _outputAsset,
        uint256 _amount,
        uint24 _maxFee,
        uint48 _ttl,
        bytes calldata _data
    ) external returns (bytes32 _intentId, Intent memory _intent);
}
