// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

/// @title IZeroExV4 Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IZeroExV4 {
    enum SignatureType {
        ILLEGAL,
        INVALID,
        EIP712,
        ETHSIGN,
        PRESIGNED
    }

    struct LimitOrder {
        address makerToken;
        address takerToken;
        uint128 makerAmount;
        uint128 takerAmount;
        uint128 takerTokenFeeAmount;
        address maker;
        address taker;
        address sender;
        address feeRecipient;
        bytes32 pool;
        uint64 expiry;
        uint256 salt;
    }

    struct RfqOrder {
        address makerToken;
        address takerToken;
        uint128 makerAmount;
        uint128 takerAmount;
        address maker;
        address taker;
        address txOrigin;
        bytes32 pool;
        uint64 expiry;
        uint256 salt;
    }

    struct OtcOrder {
        address makerToken;
        address takerToken;
        uint128 makerAmount;
        uint128 takerAmount;
        address maker;
        address taker;
        address txOrigin;
        uint256 expiryAndNonce;
    }

    struct Signature {
        SignatureType signatureType;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function fillOrKillLimitOrder(LimitOrder memory _order, Signature memory _signature, uint128 _takerTokenFillAmount)
        external
        payable
        returns (uint128 makerTokenFilledAmount_);

    function fillOrKillRfqOrder(RfqOrder memory _order, Signature memory _signature, uint128 _takerTokenFillAmount)
        external
        returns (uint128 makerTokenFilledAmount_);

    function fillOtcOrder(OtcOrder memory _order, Signature memory _signature, uint128 _takerTokenFillAmount)
        external
        returns (uint128 takerTokenFilledAmount_, uint128 makerTokenFilledAmount_);
}
