// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error WithdrawEthFailed();
error MismatchedArrayLengths();

contract FraxOFTWalletUpgradeable is Ownable2StepUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function batchBridgeWithEthFeeFromWallet(
        SendParam[] memory _sendParams,
        IOFT[] memory _ofts,
        address[] memory _destinations
    ) external payable onlyOwner {
        uint256 _sendParamLength = _sendParams.length;
        uint256 _oftLength = _ofts.length;
        uint256 _destinationLength = _destinations.length;
        if (_sendParamLength != _oftLength && _oftLength != _destinationLength) {
            revert MismatchedArrayLengths();
        }
        for (uint256 _i; _i < _sendParamLength; _i++) {
            MessagingFee memory fee = _ofts[_i].quoteSend(_sendParams[_i], false);
            _ofts[_i].send{ value: fee.nativeFee }(_sendParams[_i], fee, _destinations[_i]);
        }
    }

    function batchBridgeWithEthFeeFromSender(
        SendParam[] memory _sendParams,
        address[] memory _senders,
        IERC20[] memory _tokens,
        IOFT[] memory _ofts,
        address[] memory _destinations
    ) external payable onlyOwner {
        uint256 _sendParamLength = _sendParams.length;
        uint256 _senderLength = _senders.length;
        uint256 _tokenLength = _tokens.length;
        uint256 _oftLength = _ofts.length;
        uint256 _destinationLength = _destinations.length;
        if (
            _sendParamLength != _senderLength &&
            _senderLength != _tokenLength &&
            _tokenLength != _oftLength &&
            _oftLength != _destinationLength
        ) {
            revert MismatchedArrayLengths();
        }
        for (uint256 _i; _i < _sendParamLength; _i++) {
            _tokens[_i].transferFrom(_senders[_i], address(this), _sendParams[_i].amountLD);
            MessagingFee memory fee = _ofts[_i].quoteSend(_sendParams[_i], false);
            _ofts[_i].send{ value: fee.nativeFee }(_sendParams[_i], fee, _destinations[_i]);
        }
    }

    function bridgeWithEthFeeFromWallet(
        SendParam memory sendParam,
        IOFT _oft,
        address _destination
    ) external payable onlyOwner {
        MessagingFee memory fee = _oft.quoteSend(sendParam, false);
        _oft.send{ value: fee.nativeFee }(sendParam, fee, payable(_destination));
    }

    function bridgeWithEthFeeFromSender(
        SendParam memory sendParam,
        IOFT _oft,
        IERC20 _token,
        address _sender,
        address _destination
    ) external payable onlyOwner {
        _token.transferFrom(_sender, address(this), sendParam.amountLD);
        MessagingFee memory fee = _oft.quoteSend(sendParam, false);
        _oft.send{ value: fee.nativeFee }(sendParam, fee, payable(_destination));
    }

    function withdrawOFT(IERC20 _token, address _beneficiary, uint256 _amount) external onlyOwner {
        _token.transfer(_beneficiary, _amount);
    }

    function withdrawEth(address _beneficiary) external onlyOwner {
        (bool _success, ) = payable(_beneficiary).call{ value: address(this).balance }("");
        if (!_success) {
            revert WithdrawEthFailed();
        }
    }

    function approveToken(IERC20 _token, address _spender, uint256 _amount) external onlyOwner {
        _token.approve(_spender, _amount);
    }

    // Admin

    function initialize(address _delegate) external initializer {
        __Ownable_init();
        _transferOwnership(_delegate);
    }
}
