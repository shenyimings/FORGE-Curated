// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import './Interface.sol';
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import './StakeToken.sol';
import "forge-std/console.sol";

contract StakeFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;
    address public factoryAddress;
    mapping(uint256 => address) public stakeTokens;
    EnumerableSet.UintSet private assetIDs;
    address public stImpl;
    mapping(uint256 => address) public stImpls;

    event CreateStakeToken(address stakeToken, uint256 assetID, uint48 cooldown);
    event SetSTImpl(address oldSTImpl, address stImpl);
    event UpgradeStakeToken(uint256 assetID, address oldSTImpl, address stImpl);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address factoryAddress_, address stImpl_) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        require(factoryAddress_ != address(0), "factory is zero address");
        factoryAddress = factoryAddress_;
        _setSTImpl(stImpl_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setSTImpl(address stImpl_) external onlyOwner {
        _setSTImpl(stImpl_);
    }

    function _setSTImpl(address stImpl_) internal {
        require(stImpl_ != address(0), "stImpl is zero address");
        require(stImpl_ != stImpl, "stImpl not change");
        emit SetSTImpl(stImpl, stImpl_);
        stImpl = stImpl_;
    }

    function upgradeSTImpl(uint256[] memory assetIDs_) external onlyOwner {
        uint assetID;
        for (uint i = 0; i < assetIDs_.length; i++) {
            assetID = assetIDs_[i];
            require(assetIDs.contains(assetID), "stake token not exist");
            require(stImpls[assetID] != stImpl, "stake token already upgraded");
            UUPSUpgradeable(stakeTokens[assetID]).upgradeToAndCall(stImpl, new bytes(0));
            emit UpgradeStakeToken(assetID, stImpls[assetID], stImpl);
            stImpls[assetID] = stImpl;
        }
    }

    function createStakeToken(uint256 assetID, uint48 cooldown) external onlyOwner returns (address stakeToken)  {
        require(!assetIDs.contains(assetID), "stake token already exists");
        IAssetFactory factory = IAssetFactory(factoryAddress);
        address assetToken = factory.assetTokens(assetID);
        require(assetToken != address(0), "asset token not exists");
        string memory tokenName = IERC20Metadata(assetToken).name();
        string memory tokenSymbol = IERC20Metadata(assetToken).symbol();
        stakeToken = address(new ERC1967Proxy(
            stImpl,
            abi.encodeCall(StakeToken.initialize, (
                string.concat("Staked ", tokenName),
                string.concat("s", tokenSymbol),
                address(assetToken),
                cooldown,
                address(this)
            ))
        ));
        stakeTokens[assetID] = stakeToken;
        stImpls[assetID] = stImpl;
        assetIDs.add(assetID);
        emit CreateStakeToken(stakeToken, assetID, cooldown);
    }

    function getStakeTokens() external view returns (uint256[] memory ids, address[] memory tokens) {
        ids = assetIDs.values();
        tokens = new address[](ids.length);
        for (uint i = 0; i < tokens.length; i++) {
            tokens[i] = stakeTokens[assetIDs.at(i)];
        }
    }

    function pauseStakeToken(uint256 assetID) external onlyOwner {
        require(assetIDs.contains(assetID), "stake token not exists");
        StakeToken(stakeTokens[assetID]).pause();
    }

    function unpauseStakeToken(uint256 assetID) external onlyOwner {
        require(assetIDs.contains(assetID), "stake token not exists");
        StakeToken(stakeTokens[assetID]).unpause();
    }

    function updateCooldown(uint256 assetID, uint48 cooldown) external onlyOwner {
        require(assetIDs.contains(assetID), "stake token not exists");
        StakeToken(stakeTokens[assetID]).setCooldown(cooldown);
    }
}