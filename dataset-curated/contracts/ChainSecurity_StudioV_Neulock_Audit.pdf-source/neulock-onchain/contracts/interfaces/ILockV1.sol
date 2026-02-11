// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

interface INeuDaoLockV1 {
    event AddressChange(address indexed newAddress);
    event Unlock(uint256 indexed neuTokenId);
    event UnlockCancel(uint256 indexed neuTokenId);
    event Withdraw(uint256 amount);

    function neuDaoAddress() external view returns (address);
    function keyTokenIds(uint256 index) external view returns (uint256);
    function setNeuDaoAddress(address newNeoDaoAddress) external;
    function unlock(uint256 neuTokenId) external;
    function cancelUnlock(uint256 neuTokenId) external;
    function withdraw() external;
    receive() external payable;
}