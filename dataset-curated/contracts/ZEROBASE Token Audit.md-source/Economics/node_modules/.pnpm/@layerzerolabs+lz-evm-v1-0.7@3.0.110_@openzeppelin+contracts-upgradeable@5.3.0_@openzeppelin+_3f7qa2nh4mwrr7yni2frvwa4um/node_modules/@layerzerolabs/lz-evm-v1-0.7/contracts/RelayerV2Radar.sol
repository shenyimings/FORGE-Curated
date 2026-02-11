// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "hardhat-deploy/solc_0.7/proxy/Proxied.sol";

import "./interfaces/ILayerZeroRelayerV2.sol";
import "./interfaces/ILayerZeroRelayerV2PriceData.sol";
import "./interfaces/ILayerZeroUltraLightNodeV2.sol";
import "./interfaces/ILayerZeroPriceFeed.sol";

// RelayerV2Radar has an instance of RelayerV2.
// It does not need to set prices.
// it has view functions that use the internal RelayerV2 price data.
contract RelayerV2Radar is
    ReentrancyGuard,
    OwnableUpgradeable,
    Proxied,
    ILayerZeroRelayerV2,
    ILayerZeroRelayerV2PriceData
{
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using SafeMath for uint128;
    using SafeMath for uint64;

    ILayerZeroUltraLightNodeV2 public uln; // UltraLightNodeV2Radar
    ILayerZeroRelayerV2PriceData public relayerV2;

    address public stargateBridgeAddress;

    //    struct DstPrice {
    //        uint128 dstPriceRatio; // 10^10
    //        uint128 dstGasPriceInWei;
    //    }
    //
    //    struct DstConfig {
    //        uint128 dstNativeAmtCap;
    //        uint64 baseGas;
    //        uint64 gasPerByte;
    //    }

    //    // [_chainId] => DstPriceData. change often
    //    mapping(uint16 => RelayerV2.DstPrice) public dstPriceLookup;
    //    // [_chainId][_outboundProofType] => DstConfig. change much less often
    //    mapping(uint16 => mapping(uint16 => RelayerV2.DstConfig)) public dstConfigLookup;
    mapping(address => bool) public approvedAddresses;

    event Withdraw(address to, uint amount);
    event ApproveAddress(address addr, bool approved);
    event AssignJob(uint totalFee);
    event ValueTransferFailed(address indexed to, uint indexed quantity);
    event SetDstPrice(uint16 chainId, uint128 dstPriceRatio, uint128 dstGasPriceInWei);
    event SetDstConfig(
        uint16 chainId,
        uint16 outboundProofType,
        uint128 dstNativeAmtCap,
        uint64 baseGas,
        uint64 gasPerByte
    );

    // new pauseable relayer
    bool public paused;

    // map of legacyChainid => v2 chainId. allows lookup thru to RelayerV2 contract (which is updated frequently)
    mapping(uint16 => uint16) public legacyToV2ChainId; // legacy ChainId => v2 chainId

    // Upgrade
    ILayerZeroPriceFeed public priceFeed;
    // all encoded param bytes except for proof for validateTransactionProofV1
    uint128 public multiplierBps;
    uint16 public validateProofBytes;
    uint16 public fpBytes;
    uint16 public mptOverhead; // average overhead for mpt

    // owner is always approved
    modifier onlyApproved() {
        if (owner() != msg.sender) {
            require(isApproved(msg.sender), "Relayer: not approved");
        }
        _;
    }

    function initialize(address _ulnRadar, address _relayerV2, address _priceFeed) public proxied initializer {
        __Ownable_init();
        uln = ILayerZeroUltraLightNodeV2(_ulnRadar);
        setApprovedAddress(address(this), true);

        relayerV2 = ILayerZeroRelayerV2PriceData(_relayerV2);

        legacyToV2ChainId[1] = 101; // ethereum
        legacyToV2ChainId[2] = 102; // bsc
        legacyToV2ChainId[12] = 112; // fantom

        priceFeed = ILayerZeroPriceFeed(_priceFeed);
        validateProofBytes = 164;
        fpBytes = 160;
        mptOverhead = 500;
    }

    function onUpgrade(address _priceFeed) public proxied {
        multiplierBps = 12000;
        priceFeed = ILayerZeroPriceFeed(_priceFeed);
        validateProofBytes = 164;
        fpBytes = 160;
        mptOverhead = 500;
    }

    function getV2ChainId(uint16 _legacyChainId) public view returns (uint16) {
        require(legacyToV2ChainId[_legacyChainId] != 0, "getLegacyChainId(): lookup not found");
        return legacyToV2ChainId[_legacyChainId];
    }

    //----------------------------------------------------------------------------------
    // onlyApproved

    function setDstPrice(uint16 _chainId, uint128 _dstPriceRatio, uint128 _dstGasPriceInWei) external onlyApproved {
        //        dstPriceLookup[_chainId] = DstPrice(_dstPriceRatio, _dstGasPriceInWei);
        //        emit SetDstPrice(_chainId, _dstPriceRatio, _dstGasPriceInWei);
    }

    function setPriceFeed(address _priceFeed) external onlyApproved {
        priceFeed = ILayerZeroPriceFeed(_priceFeed);
    }

    function setPriceMultiplierBps(uint128 _multiplierBps) external onlyApproved {
        multiplierBps = _multiplierBps;
    }

    function setDstConfig(
        uint16 _chainId,
        uint16 _outboundProofType,
        uint128 _dstNativeAmtCap,
        uint64 _baseGas,
        uint64 _gasPerByte
    ) external onlyApproved {
        //        dstConfigLookup[_chainId][_outboundProofType] = DstConfig(_dstNativeAmtCap, _baseGas, _gasPerByte);
        //        emit SetDstConfig(_chainId, _outboundProofType, _dstNativeAmtCap, _baseGas, _gasPerByte);
    }

    function dstPriceLookup(
        uint16 _legacyChainId
    ) public view override returns (ILayerZeroRelayerV2PriceData.DstPrice memory) {
        return relayerV2.dstPriceLookup(getV2ChainId(_legacyChainId));
    }

    function dstConfigLookup(
        uint16 _legacyChainId,
        uint16 _outboundProofType
    ) public view override returns (ILayerZeroRelayerV2PriceData.DstConfig memory) {
        return relayerV2.dstConfigLookup(getV2ChainId(_legacyChainId), _outboundProofType);
    }

    function setStargateAddress(address _stargateAddress) external onlyApproved {
        stargateBridgeAddress = _stargateAddress;
    }

    //----------------------------------------------------------------------------------
    // onlyOwner

    function setApprovedAddress(address _relayerAddress, bool _approve) public onlyOwner {
        approvedAddresses[_relayerAddress] = _approve;
        emit ApproveAddress(_relayerAddress, _approve);
    }

    function setPause(bool _paused) public onlyOwner {
        paused = _paused;
    }

    // txType 1
    // bytes  [2       32      ]
    // fields [txType  extraGas]
    // txType 2
    // bytes  [2       32        32            bytes[]         ]
    // fields [txType  extraGas  dstNativeAmt  dstNativeAddress]
    // User App Address is not used in this version
    function _getPrices(
        uint16 _dstChainId,
        uint16 _outboundProofType,
        address,
        uint _payloadSize,
        bytes memory _adapterParameters
    ) internal view returns (uint) {
        require(!paused, "Admin: paused");
        // decoding the _adapterParameters - reverts if type 2 and there is no dstNativeAddress
        require(
            _adapterParameters.length == 34 || _adapterParameters.length > 66,
            "Relayer: wrong _adapterParameters size"
        );
        uint16 txType;
        uint extraGas;
        assembly {
            txType := mload(add(_adapterParameters, 2))
            extraGas := mload(add(_adapterParameters, 34))
        }
        require(extraGas > 0, "Relayer: gas too low");
        require(txType == 1 || txType == 2, "Relayer: unsupported txType");

        DstConfig memory dstConfig = dstConfigLookup(_dstChainId, _outboundProofType);

        uint dstNativeAmt = 0;
        if (txType == 2) {
            assembly {
                dstNativeAmt := mload(add(_adapterParameters, 66))
            }
            require(dstConfig.dstNativeAmtCap >= dstNativeAmt, "Relayer: dstNativeAmt too large");
        }

        // validateTransactionProof bytes = fixedBytes + proofBytes
        // V2 has an extra 32 bytes for payable address
        uint totalFixedBytes = txType == 2 ? uint(validateProofBytes).add(32) : validateProofBytes;
        uint proofBytes = _outboundProofType == 2 ? fpBytes : _payloadSize.add(mptOverhead);
        uint totalCallDataBytes = totalFixedBytes.add(proofBytes);

        uint16 dstChainId = _dstChainId; // stack too deep
        (uint fee, uint128 priceRatio) = priceFeed.estimateFeeByChain(
            getV2ChainId(dstChainId),
            totalCallDataBytes,
            dstConfig.baseGas.add(extraGas)
        );
        uint airdropAmount = dstNativeAmt.mul(priceRatio).div(10 ** 10);
        return fee.add(airdropAmount).mul(multiplierBps).div(10000);
    }

    function getFee(
        uint16 _dstChainId,
        uint16 _outboundProofType,
        address _userApplication,
        uint _payloadSize,
        bytes calldata _adapterParams
    ) external view override returns (uint) {
        require(_payloadSize <= 10000, "Relayer: _payloadSize tooooo big");
        return _getPrices(_dstChainId, _outboundProofType, _userApplication, _payloadSize, _adapterParams);
    }

    function isApproved(address _relayerAddress) public view returns (bool) {
        return approvedAddresses[_relayerAddress];
    }

    function assignJob(
        uint16 _dstChainId,
        uint16 _outboundProofType,
        address _userApplication,
        uint _payloadSize,
        bytes calldata _adapterParams
    ) external override returns (uint) {
        require(msg.sender == address(uln), "Relayer: invalid uln");
        require(_payloadSize <= 10000, "Relayer: _payloadSize tooooo big");
        uint fee = _getPrices(_dstChainId, _outboundProofType, _userApplication, _payloadSize, _adapterParams);
        emit AssignJob(fee);
        return fee;
    }

    function withdrawFee(address payable _to, uint _amount) external override onlyApproved {
        uint totalFee = uln.accruedNativeFee(address(this));
        require(_amount <= totalFee, "Relayer: not enough fee for withdrawal");
        uln.withdrawNative(_to, _amount);
    }

    function validateTransactionProofV2(
        uint16 _srcChainId,
        address _dstAddress,
        uint _gasLimit,
        bytes32 _blockHash,
        bytes32 _data,
        bytes calldata _transactionProof,
        address payable _to
    ) external payable onlyApproved nonReentrant {
        (bool sent, ) = _to.call{value: msg.value}("");
        //require(sent, "Relayer: failed to send ether");
        if (!sent) {
            emit ValueTransferFailed(_to, msg.value);
        }
        uln.validateTransactionProof(_srcChainId, _dstAddress, _gasLimit, _blockHash, _data, _transactionProof);
    }

    function validateTransactionProofV1(
        uint16 _srcChainId,
        address _dstAddress,
        uint _gasLimit,
        bytes32 _blockHash,
        bytes32 _data,
        bytes calldata _transactionProof
    ) external onlyApproved nonReentrant {
        uln.validateTransactionProof(_srcChainId, _dstAddress, _gasLimit, _blockHash, _data, _transactionProof);
    }
}
