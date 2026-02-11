// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

struct Token {
    string chain;
    string symbol;
    string addr;
    uint8 decimals;
    uint256 amount;
}

struct Asset {
    uint256 id;
    string name;
    string symbol;
    Token[] tokenset;
}

struct Order {
    string chain;
    address maker;
    uint256 nonce;
    Token[] inTokenset;
    Token[] outTokenset;
    string[] inAddressList;
    string[] outAddressList;
    uint256 inAmount;
    uint256 outAmount;
    uint256 deadline;
    address requester;
}

struct OrderInfo {
    Order order;
    bytes32 orderHash;
    bytes orderSign;
}

struct Range {
    uint256 min;
    uint256 max;
}

enum SwapRequestStatus {NONE, PENDING, MAKER_CONFIRMED, CONFIRMED, REJECTED, CANCEL, FORCE_CANCEL}

struct SwapRequest {
    bytes[] inTxHashs;
    bytes[] outTxHashs;
    SwapRequestStatus status;
    address requester;
    bool inByContract;
    bool outByContract;
    uint256 blocknumber;
    uint256 requestTimestamp;
}

enum RequestStatus {NONE, PENDING, CONFIRMED, REJECTED}

struct Request {
    uint nonce;
    address requester;
    address assetTokenAddress;
    uint amount;
    address swapAddress;
    bytes32 orderHash;
    RequestStatus status;
    uint requestTimestamp;
    uint issueFee;
}

interface IAssetToken is IERC20, IAccessControl {
    function decimals() external view returns (uint8);
    // id
    function id() external returns (uint256);
    // roles
    function ISSUER_ROLE() external returns (bytes32);
    function REBALANCER_ROLE() external returns (bytes32);
    function FEEMANAGER_ROLE() external returns (bytes32);
    // tokenset
    function getTokenset() external view returns (Token[] memory);
    function initTokenset(Token[] memory tokenset) external;
    function getBasket() external view returns (Token[] memory);
    // issue
    function lockIssue() external;
    function issuing() external view returns (bool);
    function unlockIssue() external;
    function mint(address account, uint amount) external;
    function burn(uint amount) external;
    // rebalance
    function lockRebalance() external;
    function rebalancing() external view returns (bool);
    function unlockRebalance() external;
    function rebalance(Token[] memory inBasket, Token[] memory outBasket) external;
    // fee
    function feeDecimals() external view returns (uint);
    function maxFee() external view returns (uint);
    function fee() external view returns (uint);
    function setFee(uint fee_) external;
    function lastCollectTimestamp() external view returns (uint);
    function feeCollected() external view returns (bool);
    function getFeeTokenset() external view returns (Token[] memory);
    function collectFeeTokenset() external;
    function lockBurnFee() external;
    function burningFee() external view returns (bool);
    function unlockBurnFee() external;
    function burnFeeTokenset(Token[] memory feeTokenset) external;
}

interface IAssetFactory {
    function vault() external view returns (address);
    function chain() external view returns (string memory);
    // asset tokens
    function createAssetToken(Asset memory asset, uint maxFee, address issuer, address rebalancer, address feeMamanger, address swap) external returns (address);
    function assetTokens(uint assetID) external view returns (address);
    function hasAssetID(uint assetID) external view returns (bool);
    function getAssetIDs() external view returns (uint[] memory);
    function issuers(uint assetID) external view returns (address);
    function rebalancers(uint assetID) external view returns (address);
    function feeManagers(uint assetID) external view returns (address);
    function swaps(uint assetID) external view returns (address);
}

interface ISwap is IAccessControl {
    function TAKER_ROLE() external returns (bytes32);
    function MAKER_ROLE() external returns (bytes32);
    function checkOrderInfo(OrderInfo memory orderInfo) external view returns (uint);
    function getOrderHashs() external view returns (bytes32[] memory);
    function getOrderHashLength() external view returns (uint256);
    function getOrderHash(uint256 idx) external view returns (bytes32);
    function getSwapRequest(bytes32 orderHash) external view returns (SwapRequest memory);
    function addSwapRequest(OrderInfo memory orderInfo, bool inByContract, bool outByContract) external;
    function makerConfirmSwapRequest(OrderInfo memory orderInfo, bytes[] memory outTxHashs) external;
    function makerRejectSwapRequest(OrderInfo memory orderInfo) external;
    function rollbackSwapRequest(OrderInfo memory orderInfo) external;
    function cancelSwapRequest(OrderInfo memory orderInfo) external;
    function confirmSwapRequest(OrderInfo memory orderInfo, bytes[] memory inTxHashs) external;
    function setTakerAddresses(string[] memory takerReceivers_, string[] memory takerSenders_) external;
    function getTakerAddresses() external view returns (string[] memory receivers, string[] memory senders);
    function getWhiteListTokens() external view returns (Token[] memory tokens);
}

interface IAssetController {
    function factoryAddress() external returns (address);
}

interface IAssetIssuer is IAssetController {
    // mint
    function getMintRequestLength() external view returns (uint256);
    function getMintRequest(uint256 nonce) external view returns (Request memory);
    function addMintRequest(uint256 assetID, OrderInfo memory orderInfo, uint256 maxIssueFee) external returns (uint);
    function rejectMintRequest(uint256 nonce, OrderInfo memory orderInfo, bool force) external;
    function confirmMintRequest(uint nonce, OrderInfo memory orderInfo, bytes[] memory inTxHashs) external;
    // redeem
    function getRedeemRequestLength() external view returns (uint256);
    function getRedeemRequest(uint256 nonce) external view returns (Request memory);
    function addRedeemRequest(uint256 assetID, OrderInfo memory orderInfo, uint256 maxIssueFee) external returns (uint256);
    function rejectRedeemRequest(uint256 nonce) external;
    function confirmRedeemRequest(uint nonce, OrderInfo memory orderInfo, bytes[] memory inTxHashs, bool force) external;
    // manage participants
    function isParticipant(uint256 assetID, address participant) external view returns (bool);
    function getParticipants(uint256 assetID) external view returns (address[] memory);
    function getParticipantLength(uint256 assetID) external view returns (uint256);
    function getParticipant(uint256 assetID, uint256 idx) external view returns (address);
    function addParticipant(uint256 assetID, address participant) external;
    function removeParticipant(uint256 assetID, address participant) external;
    // fee
    function setIssueFee(uint256 assetID, uint256 issueFee) external;
    function getIssueFee(uint256 assetID) external view returns (uint256);
    function feeDecimals() external view returns (uint256);
    // issue amount range
    function getIssueAmountRange(uint256 assetID) external view returns (Range memory);
    function setIssueAmountRange(uint256 assetID, Range calldata issueAmountRange) external;
    // burn for
    function burnFor(uint256 assetID, uint256 amount) external;
}

interface IAssetRebalancer is IAssetController {
    function getRebalanceRequestLength() external view returns (uint256);
    function getRebalanceRequest(uint256 nonce) external view returns (Request memory);
    function addRebalanceRequest(uint256 assetID, Token[] memory basket, OrderInfo memory orderInfo) external returns (uint256);
    function rejectRebalanceRequest(uint256 nonce) external;
    function confirmRebalanceRequest(uint nonce, OrderInfo memory orderInfo, bytes[] memory inTxHashs) external;
}

interface IAssetFeeManager is IAssetController {
    function setFee(uint256 assetID, uint256 fee) external;
    function collectFeeTokenset(uint256 assetID) external;
    function getBurnFeeRequestLength() external view returns (uint256);
    function getBurnFeeRequest(uint256 nonce) external view returns (Request memory);
    function addBurnFeeRequest(uint256 assetID, OrderInfo memory orderInfo) external returns (uint256);
    function rejectBurnFeeRequest(uint256 nonce) external;
    function confirmBurnFeeRequest(uint nonce, OrderInfo memory orderInfo, bytes[] memory inTxHashs) external;
}