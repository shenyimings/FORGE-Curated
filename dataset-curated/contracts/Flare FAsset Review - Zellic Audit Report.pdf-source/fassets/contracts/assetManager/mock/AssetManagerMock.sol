// SPDX-License-Identifier: MIT
// solhint-disable gas-custom-errors

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWNat} from "../../flareSmartContracts/interfaces/IWNat.sol";
import {IIFAsset} from "../../fassetToken/interfaces/IIFAsset.sol";
import {Agent} from "../library/data/Agent.sol";
import {EmergencyPause} from "../../userInterfaces/data/EmergencyPause.sol";


contract AssetManagerMock {
    IWNat private wNat;
    IIFAsset public fasset;
    address private commonOwner;
    bool private checkForValidAgentVaultAddress = true;
    address private collateralPool;

    // allow correct decoding of passed errors
    error PoolTokenAlreadySet();
    error CannotDestroyPoolWithIssuedTokens();

    event AgentRedemptionInCollateral(address _recipient, uint256 _amountUBA);
    event AgentRedemption(address _recipient, string _underlying, uint256 _amountUBA, address payable _executor);
    event CollateralUpdated(address agentVault, address token);

    uint256 internal maxRedemption = type(uint256).max;
    uint256 internal fassetsBackedByPool = type(uint256).max;
    uint256 internal timelockDuration = 0 days;
    uint256 public assetPriceMul = 1;
    uint256 public assetPriceDiv = 2;
    uint256 public lotSize = 1;
    uint256 public minPoolCollateralRatioBIPS = 0;
    uint256 public assetMintingGranularityUBA = 1e9;

    constructor(IWNat _wNat) {
        wNat = _wNat;
    }

    function getWNat() external view returns (IWNat) {
        return wNat;
    }

    function callFunctionAt(address _contract, bytes memory _payload) external {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _contract.call(_payload);
        _passReturnOrRevert(success);
    }

    function setCommonOwner(address _owner) external {
        commonOwner = _owner;
    }

    function getAgentVaultOwner(address /*_agentVault*/) external view
        returns (address _ownerManagementAddress)
    {
        return commonOwner;
    }

    function isAgentVaultOwner(address /*_agentVault*/, address _address) external view returns (bool) {
        return _address == commonOwner;
    }

    function isVaultCollateralToken(IERC20 /* _token */) external pure returns (bool) {
        return true;
    }

    function updateCollateral(address _agentVault, IERC20 _token) external {
        require(!checkForValidAgentVaultAddress, Agent.InvalidAgentVaultAddress());
        emit CollateralUpdated(_agentVault, address(_token));
    }

    function setCheckForValidAgentVaultAddress(bool _check) external {
        checkForValidAgentVaultAddress = _check;
    }

    function getCollateralPool(address /*_agentVault*/) external view returns (address) {
        return collateralPool;
    }

    function setCollateralPool(address pool) external {
        collateralPool = pool;
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // Methods specific to collateral pool contract

    function redeemFromAgent(
        address /* _agentVault */, address _redeemer, uint256 _amountUBA,
        string memory _receiverUnderlyingAddress, address payable _executor
    ) external payable {
        fasset.burn(msg.sender, _amountUBA);
        emit AgentRedemption(_redeemer, _receiverUnderlyingAddress, _amountUBA, _executor);
    }

    function redeemFromAgentInCollateral(
        address /* _agentVault */, address _redeemer, uint256 _amountUBA
    ) external {
        fasset.burn(msg.sender, _amountUBA);
        emit AgentRedemptionInCollateral(_redeemer, _amountUBA);
    }

    function registerFAssetForCollateralPool(IIFAsset _fasset) external {
        fasset = _fasset;
    }

    function getFAssetsBackedByPool(address /* _backer */) external view returns (uint256) {
        return Math.min(fassetsBackedByPool, fasset.totalSupply());
    }

    function maxRedemptionFromAgent(address /*agentVault*/) external view returns (uint256) {
        return maxRedemption;
    }

    function getCollateralPoolTokenTimelockSeconds() external view returns (uint256) {
        return timelockDuration;
    }

    function assetPriceNatWei() public view returns (uint256, uint256) {
        return (assetPriceMul, assetPriceDiv);
    }

    function fAsset()
        external view
        returns (IIFAsset)
    {
        return fasset;
    }

    function emergencyPaused()
        external pure
        returns (bool)
    {
        return false;
    }

    function emergencyPauseLevel()
        external pure
        returns (EmergencyPause.Level)
    {
        return EmergencyPause.Level.NONE;
    }

    function getAgentMinPoolCollateralRatioBIPS(address /* _agentVault */) external view returns (uint256) {
        return minPoolCollateralRatioBIPS;
    }

    /////////////////////////////////////////////////////////////////////////////
    // artificial setters for testing

    function setAssetPriceNatWei(uint256 _mul, uint256 _div) external {
        assetPriceMul = _mul;
        assetPriceDiv = _div;
    }

    function setLotSize(uint256 _lotSize) public {
        lotSize = _lotSize;
    }

    function setFAssetsBackedByPool(uint256 _fassetsBackedByPool) external {
        fassetsBackedByPool = _fassetsBackedByPool;
    }

    function setMaxRedemptionFromAgent(uint256 _maxRedemption) external {
        maxRedemption = _maxRedemption;
    }

    function setTimelockDuration(uint256 _timelockDuration) external {
        timelockDuration = _timelockDuration;
    }

    function setMinPoolCollateralRatioBIPS(uint256 _minPoolCollateralRatioBIPS) external {
        minPoolCollateralRatioBIPS = _minPoolCollateralRatioBIPS;
    }

   function _passReturnOrRevert(bool _success) private pure {
        // pass exact return or revert data - needs to be done in assembly
        //solhint-disable-next-line no-inline-assembly
        assembly {
            let size := returndatasize()
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, size))
            returndatacopy(ptr, 0, size)
            if _success {
                return(ptr, size)
            }
            revert(ptr, size)
        }
    }
}
