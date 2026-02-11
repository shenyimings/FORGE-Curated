// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    SendParam,
    OFTReceipt,
    IOFT,
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

import { OFTMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";

import { IBridgeableToken } from "contracts/interfaces/IBridgeableToken.sol";

import { ERC20Mock } from "./ERC20Mock.sol";

contract BridgeableTokenMock is ERC20Mock, IBridgeableToken {
    ERC20Mock public principalToken;

    uint256 maxMintableAmount;

    constructor(address _principalToken, string memory _name, string memory _symbol) ERC20Mock(_name, _symbol, 18) {
        principalToken = ERC20Mock(_principalToken);
    }

    function swapLzTokenToPrincipalToken(address _to, uint256 _amount) external {
        _burn(msg.sender, _amount);
        principalToken.mint(_to, _amount);
    }

    function getMaxCreditableAmount() external view returns (uint256) {
        return maxMintableAmount;
    }

    function setMaxMintableAmount(uint256 _maxMintableAmount) external {
        maxMintableAmount = _maxMintableAmount;
    }

    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata,
        address
    )
        external
        payable
        returns (MessagingReceipt memory, OFTReceipt memory)
    {
        principalToken.transferFrom(msg.sender, address(this), _sendParam.amountLD);
        return (MessagingReceipt(bytes32(""), 0, MessagingFee(0, 0)), OFTReceipt(0, 0));
    }

    function quoteSend(SendParam calldata, bool) external view returns (MessagingFee memory) {
        return MessagingFee(0, 0);
    }
}
