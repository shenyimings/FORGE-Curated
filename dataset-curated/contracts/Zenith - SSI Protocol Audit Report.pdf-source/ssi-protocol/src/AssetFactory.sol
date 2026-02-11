// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import "./Interface.sol";
import "./AssetToken.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "forge-std/console.sol";

contract AssetFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable, IAssetFactory {
    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.UintSet assetIDs;
    mapping(uint => address) public assetTokens;

    mapping(uint => address) public issuers;
    mapping(uint => address) public rebalancers;
    mapping(uint => address) public feeManagers;

    address public swap;
    address public vault;
    string public chain;
    address public tokenImpl;

    event AssetTokenCreated(address assetTokenAddress);
    event SetVault(address vault);
    event SetSwap(address swap);
    event SetTokenImpl(address tokenImpl);
    event UpgradeAssetToken(uint256 assetID, address tokenImpl);
    event SetIssuer(uint256 assetID, address oldIssuer, address issuer);
    event SetRebalancer(uint256 assetID, address oldRebalancer, address rebalancer);
    event SetFeeManager(uint256 assetID, address oldFeeManager, address feeManager);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address swap_, address vault_, string memory chain_, address tokenImpl_) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        require(swap_ != address(0), "swap address is zero");
        require(vault_ != address(0), "vault address is zero");
        require(tokenImpl_ != address(0), "token impl address is zero");
        swap = swap_;
        vault = vault_;
        chain = chain_;
        tokenImpl = tokenImpl_;
        emit SetVault(vault);
        emit SetSwap(swap);
        emit SetTokenImpl(tokenImpl);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setSwap(address swap_) external onlyOwner {
        require(swap_ != address(0), "swap address is zero");
        swap = swap_;
        emit SetSwap(swap);
    }

    function setVault(address vault_) external onlyOwner {
        require(vault_ != address(0), "vault address is zero");
        vault = vault_;
        emit SetVault(vault);
    }

    function setTokenImpl(address tokenImpl_) external onlyOwner {
        require(tokenImpl_ != address(0), "token impl address is zero");
        require(tokenImpl_ != tokenImpl, "token impl is not change");
        tokenImpl = tokenImpl_;
        emit SetTokenImpl(tokenImpl);
        for (uint i = 0; i < assetIDs.length(); i++) {
            address assetToken = assetTokens[assetIDs.at(i)];
            UUPSUpgradeable(assetToken).upgradeToAndCall(tokenImpl, new bytes(0));
            emit UpgradeAssetToken(assetIDs.at(i), tokenImpl);
        }
    }

    function createAssetToken(Asset memory asset, uint maxFee, address issuer, address rebalancer, address feeManager) external onlyOwner returns (address) {
        require(issuer != address(0) && rebalancer != address(0) && feeManager != address(0), "controllers not set");
        require(!assetIDs.contains(asset.id), "asset exists");
        address assetTokenAddress = address(new ERC1967Proxy(
            tokenImpl,
            abi.encodeCall(AssetToken.initialize, (asset.id, asset.name, asset.symbol, maxFee, address(this)))
        ));
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        assetToken.grantRole(assetToken.ISSUER_ROLE(), issuer);
        assetToken.grantRole(assetToken.REBALANCER_ROLE(), rebalancer);
        assetToken.grantRole(assetToken.FEEMANAGER_ROLE(), feeManager);
        assetToken.initTokenset(asset.tokenset);
        assetTokens[asset.id] = address(assetToken);
        issuers[asset.id] = issuer;
        rebalancers[asset.id] = rebalancer;
        feeManagers[asset.id] = feeManager;
        assetIDs.add(asset.id);
        emit AssetTokenCreated(address(assetToken));
        return address(assetToken);
    }

    function setIssuer(uint256 assetID, address issuer) external onlyOwner {
        require(issuer != address(0), "issuer is zero address");
        require(assetIDs.contains(assetID), "assetID not exists");
        IAssetToken assetToken = IAssetToken(assetTokens[assetID]);
        require(!assetToken.issuing(), "is issuing");
        address oldIssuer = issuers[assetID];
        assetToken.revokeRole(assetToken.ISSUER_ROLE(), oldIssuer);
        assetToken.grantRole(assetToken.ISSUER_ROLE(), issuer);
        emit SetIssuer(assetID, oldIssuer, issuer);
    }

    function setRebalancer(uint256 assetID, address rebalancer) external onlyOwner {
        require(rebalancer != address(0), "rebalancer is zero address");
        require(assetIDs.contains(assetID), "assetID not exists");
        IAssetToken assetToken = IAssetToken(assetTokens[assetID]);
        require(!assetToken.rebalancing(), "is rebalancing");
        address oldRebalancer = rebalancers[assetID];
        assetToken.revokeRole(assetToken.REBALANCER_ROLE(), oldRebalancer);
        assetToken.grantRole(assetToken.REBALANCER_ROLE(), rebalancer);
        emit SetRebalancer(assetID, oldRebalancer, rebalancer);
    }

    function setFeeManager(uint256 assetID, address feeManager) external onlyOwner {
        require(feeManager != address(0), "feeManager is zero address");
        require(assetIDs.contains(assetID), "assetID not exists");
        IAssetToken assetToken = IAssetToken(assetTokens[assetID]);
        address oldFeeManager = feeManagers[assetID];
        assetToken.revokeRole(assetToken.FEEMANAGER_ROLE(), oldFeeManager);
        assetToken.grantRole(assetToken.FEEMANAGER_ROLE(), feeManager);
        emit SetFeeManager(assetID, oldFeeManager, feeManager);
    }

    function hasAssetID(uint assetID) external view returns (bool) {
        return assetIDs.contains(assetID);
    }

    function getAssetIDs() external view returns (uint[] memory) {
        return assetIDs.values();
    }
}