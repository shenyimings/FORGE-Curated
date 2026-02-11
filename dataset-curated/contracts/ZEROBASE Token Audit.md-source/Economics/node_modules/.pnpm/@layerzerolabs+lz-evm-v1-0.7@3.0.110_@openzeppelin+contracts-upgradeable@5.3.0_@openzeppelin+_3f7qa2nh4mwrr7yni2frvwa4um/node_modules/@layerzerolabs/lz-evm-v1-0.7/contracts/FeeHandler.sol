// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FeeHandler is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public feeToken;
    mapping(address => bool) public approved;

    constructor() {}

    function setFeeToken(address _feeToken) external onlyOwner {
        require(address(feeToken) == address(0x0), "FeeHandler: feeToken already set");
        feeToken = IERC20(_feeToken);
    }

    function approve(address _uln) external onlyOwner {
        approved[_uln] = true;
    }

    function creditFee(address[] calldata _receivers, uint[] calldata _amounts, address _refundAddress) external {
        require(_receivers.length == _amounts.length, "FeeHandler: invalid parameters");
        require(approved[msg.sender], "FeeHandler: not approved");

        for (uint i = 0; i < _receivers.length; i++) {
            feeToken.safeTransfer(_receivers[i], _amounts[i]);
        }
        uint remaining = feeToken.balanceOf(address(this));
        if (remaining > 0) {
            feeToken.safeTransfer(_refundAddress, remaining);
        }
    }
}
