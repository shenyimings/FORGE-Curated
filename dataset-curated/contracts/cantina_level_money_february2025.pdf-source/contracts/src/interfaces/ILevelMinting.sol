// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import "./ILevelMintingEvents.sol";

interface ILevelMinting is ILevelMintingEvents {
    enum Role {
        Minter,
        Redeemer
    }

    enum OrderType {
        MINT,
        REDEEM
    }

    enum SignatureType {
        EIP712
    }

    struct Signature {
        SignatureType signature_type;
        bytes signature_bytes;
    }

    struct Route {
        address[] addresses;
        uint256[] ratios;
    }

    struct Order {
        OrderType order_type;
        address benefactor;
        address beneficiary;
        address collateral_asset;
        uint256 collateral_amount;
        uint256 lvlusd_amount;
    }

    struct UserCooldown {
        uint104 cooldownStart;
        Order order;
    }

    error Duplicate();
    error InvalidAddress();
    error InvalidlvlUSDAddress();
    error InvalidZeroAddress();
    error InvalidAssetAddress();
    error InvalidReserveAddress();
    error InvalidOrder();
    error InvalidAffirmedAmount();
    error InvalidAmount();
    error InvalidRoute();
    error InvalidRatios();
    error UnsupportedAsset();
    error NoAssetsProvided();
    error InvalidCooldown();
    error OperationNotAllowed();
    error InvalidNonce();
    error TransferFailed();
    error MaxMintPerBlockExceeded();
    error MaxRedeemPerBlockExceeded();
    error MsgSenderIsNotBenefactor();
    error OracleUndefined();
    error OraclePriceIsZero();
    error MinimumlvlUSDAmountNotMet();
    error MinimumCollateralAmountNotMet();
    error OraclesLengthNotEqualToAssetsLength();

    // function hashOrder(Order calldata order) external view returns (bytes32);

    function verifyOrder(Order calldata order) external view returns (bool);

    function verifyRoute(Route calldata route, OrderType order_type) external view returns (bool);

    function mint(Order calldata order, Route calldata route) external;

    function mintDefault(Order calldata order) external;

    function initiateRedeem(Order memory order) external;

    function completeRedeem(address token) external;

    function getPriceAndDecimals(address collateralToken) external view returns (int256, uint256);
}
