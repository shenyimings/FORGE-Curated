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
import "./interfaces/ILayerZeroUltraLightNodeV2.sol";
import "./interfaces/ILayerZeroPriceFeedV2.sol";
import "./libs/RateLimiter.sol";

interface IStargateComposer {
    function isSending() external view returns (bool);
}

contract RelayerV2 is ReentrancyGuard, OwnableUpgradeable, Proxied, ILayerZeroRelayerV2 {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using SafeMath for uint128;
    using SafeMath for uint64;
    using RateLimiter for RateLimiter.Info;

    ILayerZeroUltraLightNodeV2 public uln;
    address public stargateBridgeAddress;
    uint public constant AIRDROP_GAS_LIMIT = 10000;

    struct DstPrice {
        uint128 dstPriceRatio; // 10^10
        uint128 dstGasPriceInWei;
    }

    struct DstConfig {
        uint128 dstNativeAmtCap;
        uint64 baseGas;
        uint64 gasPerByte;
    }

    struct DstMultiplier {
        uint16 chainId;
        uint128 multiplier;
    }

    struct DstFloorMargin {
        uint16 chainId;
        uint128 floorMargin;
    }

    // [_chainId] => DstPriceData. change often
    mapping(uint16 => DstPrice) public dstPriceLookupOld;
    // [_chainId][_outboundProofType] => DstConfig. change much less often
    mapping(uint16 => mapping(uint16 => DstConfig)) public dstConfigLookup;
    mapping(address => bool) public approvedAddresses;

    event Withdraw(address to, uint amount);
    event ApproveAddress(address addr, bool approved);
    event SetPriceConfigUpdater(address priceConfigUpdater, bool allow);
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

    // Update for Price Feed
    ILayerZeroPriceFeedV2 public priceFeed;
    // multipler for airdrop
    uint128 public multiplierBps;

    // PriceFeedContract Upgrade
    // all encoded param bytes except for proof for validateTransactionProofV1
    uint16 public validateProofBytes;
    uint16 public fpBytes;
    uint16 public mptOverhead;

    // [chainId] => [multiplier]
    mapping(uint16 => uint128) public dstMultipliers;
    // [chainId] => [floor margin in USD]
    mapping(uint16 => uint128) public dstFloorMarginsUSD;
    mapping(address => bool) public priceConfigUpdaters;

    // stargate guard
    IStargateComposer public stargateComposer;
    address public stargateBridgeAddr;

    uint256 public nativeDecimalsRate;

    RateLimiter.Info public limiter; // deprecated

    event RateLimiterSet(uint64 capacity, uint64 rate); // deprecated

    mapping(address => bool) public limiterWhitelist; // if true, sender bypasses rate limits
    mapping(uint16 => RateLimiter.Info) public limiters;
    event DstRateLimiterSet(uint16 dstChain, uint64 capacity, uint64 rate);

    // owner is always approved
    modifier onlyApproved() {
        if (owner() != msg.sender) {
            require(isApproved(msg.sender), "Relayer: not approved");
        }
        _;
    }

    modifier onlyPriceConfigUpdater() {
        if (owner() != msg.sender && !approvedAddresses[msg.sender]) {
            require(priceConfigUpdaters[msg.sender], "Relayer: not updater");
        }
        _;
    }

    function initialize(
        address _uln,
        address _priceFeed,
        address _stargateBridgeAddr,
        address _stargateComposer,
        uint256 _nativeDecimalsRate
    ) public proxied initializer {
        __Ownable_init();
        uln = ILayerZeroUltraLightNodeV2(_uln);
        setApprovedAddress(address(this), true);
        multiplierBps = 12000;
        priceFeed = ILayerZeroPriceFeedV2(_priceFeed);
        validateProofBytes = 164;
        fpBytes = 160;
        mptOverhead = 500;
        stargateBridgeAddr = _stargateBridgeAddr;
        stargateComposer = IStargateComposer(_stargateComposer);
        nativeDecimalsRate = _nativeDecimalsRate;
    }

    function onUpgrade(
        address _stargateBridgeAddr,
        address _stargateComposer,
        uint256 _nativeDecimalsRate
    ) public proxied {
        stargateBridgeAddr = _stargateBridgeAddr;
        stargateComposer = IStargateComposer(_stargateComposer);
        nativeDecimalsRate = _nativeDecimalsRate;
    }

    //----------------------------------------------------------------------------------
    // onlyApproved
    function setLimiterWhitelist(address _addr, bool _skipRateLimits) external onlyApproved {
        limiterWhitelist[_addr] = _skipRateLimits;
    }

    function setDstPrice(uint16 _chainId, uint128 _dstPriceRatio, uint128 _dstGasPriceInWei) external onlyApproved {
        // No longer used: Write prices in PriceFeed.
    }

    function setPriceFeed(address _priceFeed) external onlyApproved {
        priceFeed = ILayerZeroPriceFeedV2(_priceFeed);
    }

    function setPriceMultiplierBps(uint128 _multiplierBps) external onlyApproved {
        multiplierBps = _multiplierBps;
    }

    function setDstPriceMultipliers(DstMultiplier[] calldata _multipliers) external onlyPriceConfigUpdater {
        for (uint i = 0; i < _multipliers.length; i++) {
            DstMultiplier calldata _data = _multipliers[i];
            dstMultipliers[_data.chainId] = _data.multiplier;
        }
    }

    function setDstFloorMarginsUSD(DstFloorMargin[] calldata _margins) external onlyPriceConfigUpdater {
        for (uint i = 0; i < _margins.length; i++) {
            DstFloorMargin calldata _data = _margins[i];
            dstFloorMarginsUSD[_data.chainId] = _data.floorMargin;
        }
    }

    function setDstConfig(
        uint16 _chainId,
        uint16 _outboundProofType,
        uint128 _dstNativeAmtCap,
        uint64 _baseGas,
        uint64 _gasPerByte
    ) external onlyApproved {
        dstConfigLookup[_chainId][_outboundProofType] = DstConfig(_dstNativeAmtCap, _baseGas, _gasPerByte);
        emit SetDstConfig(_chainId, _outboundProofType, _dstNativeAmtCap, _baseGas, _gasPerByte);
    }

    function setStargateAddress(address _stargateAddress) external onlyApproved {
        stargateBridgeAddress = _stargateAddress;
    }

    //----------------------------------------------------------------------------------
    // onlyOwner
    function configRateLimiter(uint16 _dstChainId, uint64 _capacity, uint64 _rate) external onlyOwner {
        RateLimiter.Info storage dstLimiter = limiters[_dstChainId];
        dstLimiter.setCapacity(_capacity);
        dstLimiter.setRate(_rate);
        emit DstRateLimiterSet(_dstChainId, _capacity, _rate);
    }

    function setApprovedAddress(address _relayerAddress, bool _approve) public onlyOwner {
        approvedAddresses[_relayerAddress] = _approve;
        emit ApproveAddress(_relayerAddress, _approve);
    }

    function setPriceConfigUpdater(address _priceConfigUpdater, bool _allow) public onlyOwner {
        priceConfigUpdaters[_priceConfigUpdater] = _allow;
        emit SetPriceConfigUpdater(_priceConfigUpdater, _allow);
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

        DstConfig storage dstConfig = dstConfigLookup[_dstChainId][_outboundProofType];

        // validateTransactionProof bytes = fixedBytes + proofBytes
        // V2 has an extra 32 bytes for payable address
        uint totalFixedBytes = txType == 2 ? uint(validateProofBytes).add(32) : validateProofBytes;
        uint proofBytes = _outboundProofType == 2 ? _payloadSize.add(fpBytes) : _payloadSize.add(mptOverhead);

        uint16 dstChainId = _dstChainId; // stack too deep
        (uint fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 nativePriceUSD) = priceFeed
            .estimateFeeByEid(dstChainId, totalFixedBytes.add(proofBytes), dstConfig.baseGas.add(extraGas));

        uint dstNativeAmt = 0;
        if (txType == 2) {
            assembly {
                dstNativeAmt := mload(add(_adapterParameters, 66))
            }
            require(dstConfig.dstNativeAmtCap >= dstNativeAmt, "Relayer: dstNativeAmt too large");
        }
        uint airdropAmount = 0;
        if (dstNativeAmt > 0) {
            // gas saver if no airdrop
            airdropAmount = dstNativeAmt.mul(priceRatio).div(priceRatioDenominator).mul(multiplierBps).div(10000); // cheaper than priceFeed.getPriceRatioDenominator()
        }
        return _getDstTxCost(dstChainId, fee, nativePriceUSD).add(airdropAmount);
    }

    function _getDstTxCost(uint16 _dstChainId, uint _fee, uint128 nativeTokenPriceUSD) private view returns (uint) {
        uint128 _dstMultiplier = dstMultipliers[_dstChainId];
        if (_dstMultiplier == 0) {
            _dstMultiplier = multiplierBps;
        }
        uint dstTxCostWithMultiplier = _fee.mul(_dstMultiplier).div(10000);

        if (nativeTokenPriceUSD == 0) {
            return dstTxCostWithMultiplier;
        }

        uint dstTxCostWithMargin = _fee.add(
            dstFloorMarginsUSD[_dstChainId].mul(nativeDecimalsRate).div(nativeTokenPriceUSD)
        );

        return dstTxCostWithMargin > dstTxCostWithMultiplier ? dstTxCostWithMargin : dstTxCostWithMultiplier;
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

    // view function to convert pricefeed price to current price (for backwards compatibility)
    function dstPriceLookup(uint16 _dstChainId) public view returns (DstPrice memory) {
        ILayerZeroPriceFeedV2.Price memory price = priceFeed.getPrice(_dstChainId);
        return DstPrice(price.priceRatio, price.gasPriceInUnit);
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
    ) external override returns (uint fee) {
        if (_dstChainId >= 10000) {
            RateLimiter.Info storage dstLimiter = limiters[_dstChainId];
            // sandbox or testnet
            if (!limiterWhitelist[_userApplication] && dstLimiter.capacity > 0) {
                dstLimiter.tryConsume(10000);
            }
        }

        require(msg.sender == address(uln), "Relayer: invalid uln");
        require(_payloadSize <= 10000, "Relayer: _payloadSize > 10000");

        if (_userApplication == stargateBridgeAddr) {
            // following way also prevents user from inputting to address greater than 32 bytes
            bool validPayload = (_payloadSize == 544 || // swap with no payload
                _payloadSize == 320 || // redeem local callback
                _payloadSize == 288 || // redeem local
                _payloadSize == 160); // send credits

            if (!validPayload) {
                require(stargateComposer.isSending(), "Relayer: stargate composer is not sending");
            }
        }

        fee = _getPrices(_dstChainId, _outboundProofType, _userApplication, _payloadSize, _adapterParams);
        emit AssignJob(fee);
    }

    function withdrawFee(address payable _to, uint _amount) external override onlyApproved {
        uint totalFee = uln.accruedNativeFee(address(this));
        require(_amount <= totalFee, "Relayer: not enough fee for withdrawal");
        uln.withdrawNative(_to, _amount);
    }

    function withdrawToken(address _token, address _to, uint _amount) external onlyApproved {
        if (_token == address(0)) {
            uint total = address(this).balance;
            require(_amount <= total, "Relayer: not enough native fee for withdrawal");
            (bool sent, ) = payable(_to).call{ value: _amount }("");
            require(sent, "Relayer: failed to send ether");
        } else {
            uint total = IERC20(_token).balanceOf(address(this));
            require(_amount <= total, "Relayer: not enough fee for withdrawal");
            IERC20(_token).safeTransfer(_to, _amount);
        }
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
        (bool sent, ) = _to.call{ gas: AIRDROP_GAS_LIMIT, value: msg.value }("");
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
