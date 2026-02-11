// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import './Interface.sol';
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract AssetController is Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, IAssetController {
    address public factoryAddress;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address factoryAddress_
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner_);
        __Pausable_init();
        require(factoryAddress_ != address(0), "factory is zero address");
        factoryAddress = factoryAddress_;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function checkRequestOrderInfo(Request memory request, OrderInfo memory orderInfo) internal pure {
        require(request.orderHash == orderInfo.orderHash, "order hash not match");
        require(orderInfo.orderHash == keccak256(abi.encode(orderInfo.order)), "order hash invalid");
    }

    function rollbackSwapRequest(address swap, OrderInfo memory orderInfo) external onlyOwner {
        require(swap != address(0), "zero swap address");
        ISwap(swap).rollbackSwapRequest(orderInfo);
    }

    function cancelSwapRequest(address swap, OrderInfo memory orderInfo) external onlyOwner {
        require(swap != address(0), "zero swap address");
        ISwap(swap).cancelSwapRequest(orderInfo);
    }
}