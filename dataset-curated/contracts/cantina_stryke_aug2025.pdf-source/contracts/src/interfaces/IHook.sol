// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

interface IHook {
    function onMintBefore(bytes calldata _data) external;
    function onBurnBefore(bytes calldata _data) external;

    function onPositionUseBefore(bytes calldata _data) external;
    function onPositionUnUseBefore(bytes calldata _data) external;

    function onDonationBefore(bytes calldata _data) external;

    function onWildcardBefore(bytes calldata _data) external;

    function onMintAfter(bytes calldata _data) external;
    function onBurnAfter(bytes calldata _data) external;

    function onPositionUseAfter(bytes calldata _data) external;
    function onPositionUnUseAfter(bytes calldata _data) external;

    function onDonationAfter(bytes calldata _data) external;

    function onWildcardAfter(bytes calldata _data) external;
}
