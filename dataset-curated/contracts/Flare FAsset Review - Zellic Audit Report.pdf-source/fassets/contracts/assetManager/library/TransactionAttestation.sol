// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IFdcVerification, IPayment, IBalanceDecreasingTransaction, IConfirmedBlockHeightExists,
        IReferencedPaymentNonexistence, IAddressValidity}
    from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {Globals} from "./Globals.sol";


library TransactionAttestation {

    // payment status constants
    uint8 internal constant PAYMENT_SUCCESS = 0;
    uint8 internal constant PAYMENT_FAILED = 1;
    uint8 internal constant PAYMENT_BLOCKED = 2;

    error PaymentFailed();
    error InvalidChain();
    error LegalPaymentNotProven();
    error TransactionNotProven();
    error BlockHeightNotProven();
    error NonPaymentNotProven();
    error AddressValidityNotProven();


    function verifyPaymentSuccess(
        IPayment.Proof calldata _proof
    )
        internal view
    {
        require(_proof.data.responseBody.status == PAYMENT_SUCCESS, PaymentFailed());
        verifyPayment(_proof);
    }

    function verifyPayment(
        IPayment.Proof calldata _proof
    )
        internal view
    {
        AssetManagerSettings.Data storage _settings = Globals.getSettings();
        IFdcVerification fdcVerification = IFdcVerification(_settings.fdcVerification);
        require(_proof.data.sourceId == _settings.chainId, InvalidChain());
        require(fdcVerification.verifyPayment(_proof), LegalPaymentNotProven());
    }

    function verifyBalanceDecreasingTransaction(
        IBalanceDecreasingTransaction.Proof calldata _proof
    )
        internal view
    {
        AssetManagerSettings.Data storage _settings = Globals.getSettings();
        IFdcVerification fdcVerification = IFdcVerification(_settings.fdcVerification);
        require(_proof.data.sourceId == _settings.chainId, InvalidChain());
        require(fdcVerification.verifyBalanceDecreasingTransaction(_proof), TransactionNotProven());
    }

    function verifyConfirmedBlockHeightExists(
        IConfirmedBlockHeightExists.Proof calldata _proof
    )
        internal view
    {
        AssetManagerSettings.Data storage _settings = Globals.getSettings();
        IFdcVerification fdcVerification = IFdcVerification(_settings.fdcVerification);
        require(_proof.data.sourceId == _settings.chainId, InvalidChain());
        require(fdcVerification.verifyConfirmedBlockHeightExists(_proof), BlockHeightNotProven());
    }

    function verifyReferencedPaymentNonexistence(
        IReferencedPaymentNonexistence.Proof calldata _proof
    )
        internal view
    {
        AssetManagerSettings.Data storage _settings = Globals.getSettings();
        IFdcVerification fdcVerification = IFdcVerification(_settings.fdcVerification);
        require(_proof.data.sourceId == _settings.chainId, InvalidChain());
        require(fdcVerification.verifyReferencedPaymentNonexistence(_proof), NonPaymentNotProven());
    }

    function verifyAddressValidity(
        IAddressValidity.Proof calldata _proof
    )
        internal view
    {
        AssetManagerSettings.Data storage _settings = Globals.getSettings();
        IFdcVerification fdcVerification = IFdcVerification(_settings.fdcVerification);
        require(_proof.data.sourceId == _settings.chainId, InvalidChain());
        require(fdcVerification.verifyAddressValidity(_proof), AddressValidityNotProven());
    }
}
