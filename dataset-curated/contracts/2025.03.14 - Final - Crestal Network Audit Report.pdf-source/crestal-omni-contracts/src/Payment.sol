// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

contract Payment {
    function checkNFTOwnership(address nftTokenAddress, uint256 nftId, address userAddress)
        public
        view
        returns (bool)
    {
        require(nftTokenAddress != address(0), "Invalid NFT token address");
        require(userAddress != address(0), "Invalid user address");

        IERC721 nftToken = IERC721(nftTokenAddress);
        return nftToken.ownerOf(nftId) == userAddress;
    }

    // This is to support gasless flow: normally, the caller must always be the msg.sender
    // slither-disable-next-line arbitrary-send-erc20
    function payWithERC20(address erc20TokenAddress, uint256 amount, address fromAddress, address toAddress) internal {
        // check from and to address
        require(fromAddress != toAddress, "Cannot transfer to self address");
        require(toAddress != address(0), "Invalid to address");
        require(amount > 0, "Amount must be greater than 0");
        IERC20 token = IERC20(erc20TokenAddress);
        token.safeTransferFrom(fromAddress, toAddress, amount);
    }

    function payWithNativeToken(address payable toAddress, uint256 amount) internal {
        require(toAddress != address(0), "Invalid to address");
        require(amount > 0, "Amount must be greater than 0");

        (bool success,) = toAddress.call{value: amount}("");
        require(success, "Native token transfer failed");
    }
}
