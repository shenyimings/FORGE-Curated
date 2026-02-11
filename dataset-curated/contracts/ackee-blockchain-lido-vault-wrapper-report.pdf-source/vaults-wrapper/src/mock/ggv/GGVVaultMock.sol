// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BorrowedMath} from "./BorrowedMath.sol";
import {GGVMockTeller} from "./GGVMockTeller.sol";
import {GGVQueueMock} from "./GGVQueueMock.sol";
import {IStETH} from "src/interfaces/core/IStETH.sol";
import {IWstETH} from "src/interfaces/core/IWstETH.sol";
import {ITellerWithMultiAssetSupport} from "src/interfaces/ggv/ITellerWithMultiAssetSupport.sol";

contract GGVVaultMock is ERC20 {
    address public owner;

    ITellerWithMultiAssetSupport public immutable TELLER;
    GGVQueueMock public immutable BORING_QUEUE;
    IStETH public immutable STETH;
    IWstETH public immutable WSTETH;

    // steth shares as base vault asset
    // real ggv uses weth but it should be okay to peg it to steth shares for mock
    uint256 public _totalAssets;

    error OnlyOwner();
    error OnlyTeller();
    error OnlyQueue();

    constructor(address _owner, address _steth, address _wsteth) ERC20("GGVVaultMock", "tGGV") {
        owner = _owner;
        TELLER = ITellerWithMultiAssetSupport(address(new GGVMockTeller(_owner, address(this), _steth, _wsteth)));
        BORING_QUEUE = new GGVQueueMock(address(this), _steth, _wsteth, _owner);
        STETH = IStETH(_steth);
        WSTETH = IWstETH(_wsteth);

        // Mint some initial tokens to the dead address to avoid zero totalSupply issues
        _mint(address(0xdead), 1e18);
        _totalAssets = 1e18;
    }

    function changeOwner(address newOwner) external {
        if (msg.sender != owner) {
            revert("Sender is not an owner");
        }
        owner = newOwner;
    }

    function _onlyOwner() internal view {
        if (msg.sender != owner) revert OnlyOwner();
    }

    function _onlyTeller() internal view {
        if (msg.sender != address(TELLER)) revert OnlyTeller();
    }

    function _onlyQueue() internal view {
        if (msg.sender != address(BORING_QUEUE)) revert OnlyQueue();
    }

    function rebaseSteth(uint256 _stethShares) external {
        _onlyOwner();
        STETH.transferSharesFrom(msg.sender, address(this), _stethShares);
        _totalAssets += _stethShares;
    }

    function negativeRebaseSteth(uint256 stethSharesToRebaseWith) external {
        _onlyOwner();
        STETH.transferShares(msg.sender, stethSharesToRebaseWith);
        _totalAssets -= stethSharesToRebaseWith;
    }

    function rebaseWsteth(uint256 wstethAmount) external {
        _onlyOwner();
        require(WSTETH.transferFrom(msg.sender, address(this), wstethAmount), "Transfer failed");
        _totalAssets += wstethAmount;
    }

    function negativeRebaseWsteth(uint256 wstethAmount) external {
        _onlyOwner();
        require(WSTETH.transfer(msg.sender, wstethAmount), "Transfer failed");
        _totalAssets -= wstethAmount;
    }

    function getSharesByAssets(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAssets_ = totalAssets();
        if (supply == 0 || totalAssets_ == 0) return assets;

        return BorrowedMath.mulDivDown(assets, supply, totalAssets_);
    }

    function getAssetsByShares(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAssets_ = totalAssets();
        if (supply == 0) return shares;
        return BorrowedMath.mulDivDown(shares, totalAssets_, supply);
    }

    function depositByTeller(address asset, uint256 shares, uint256 assets, address user) external {
        _onlyTeller();

        if (asset == address(STETH)) {
            STETH.transferSharesFrom(user, address(this), assets);
        } else if (asset == address(WSTETH)) {
            require(WSTETH.transferFrom(user, address(this), assets), "Transfer failed");
        } else {
            revert("Unsupported asset");
        }

        _mint(user, shares);
        _totalAssets += assets;
    }

    function burnSharesReturnAssets(ERC20 assetOut, uint256 shares, uint256 assets, address user) external {
        _onlyQueue();
        _burn(address(BORING_QUEUE), shares);
        _totalAssets -= assets;
        require(assetOut.transfer(user, assets), "Transfer failed");
    }

    function totalAssets() public view returns (uint256) {
        return _totalAssets;
    }
}
