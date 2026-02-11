// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

interface IKarakBaseVault {
    /* ========== MUTATIVE FUNCTIONS ========== */
    function initialize(
        address _owner,
        address _operator,
        address _depositToken,
        string memory _name,
        string memory _symbol,
        bytes memory _extraData
    ) external;

    function slashAssets(
        uint256 slashPercentageWad,
        address slashingHandler
    ) external returns (uint256 transferAmount);

    function pause(uint256 map) external;

    function unpause(uint256 map) external;

    /* ======================================== */

    /* ============ VIEW FUNCTIONS ============ */
    function totalAssets() external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function asset() external view returns (address);
    /* ======================================== */
}
