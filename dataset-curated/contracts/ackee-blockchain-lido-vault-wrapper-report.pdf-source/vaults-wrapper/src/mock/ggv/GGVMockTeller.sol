// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GGVVaultMock} from "./GGVVaultMock.sol";
import {IStETH} from "src/interfaces/core/IStETH.sol";
import {IWstETH} from "src/interfaces/core/IWstETH.sol";
import {ITellerWithMultiAssetSupport} from "src/interfaces/ggv/ITellerWithMultiAssetSupport.sol";

contract GGVMockTeller is ITellerWithMultiAssetSupport {
    struct Asset {
        bool allowDeposits;
        bool allowWithdraws;
        uint16 sharePremium;
    }

    address public owner;
    GGVVaultMock internal immutable _VAULT;
    uint256 internal immutable ONE_SHARE;
    IStETH public immutable STETH;
    IWstETH public immutable WSTETH;

    mapping(ERC20 asset => Asset) public assets;

    event ReferralAddress(address indexed referralAddress);

    constructor(address _owner, address __vault, address _steth, address _wsteth) {
        owner = _owner;
        _VAULT = GGVVaultMock(__vault);
        STETH = IStETH(_steth);
        WSTETH = IWstETH(_wsteth);

        // eq to 10 ** vault.decimals()
        ONE_SHARE = 10 ** 18;

        _updateAssetData(ERC20(_steth), true, false, 0);
        _updateAssetData(ERC20(_wsteth), true, true, 0);
    }

    function changeOwner(address newOwner) external {
        if (msg.sender != owner) {
            revert("Sender is not an owner");
        }
        owner = newOwner;
    }

    function deposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint, address referralAddress)
        external
        returns (uint256 shares)
    {
        Asset memory asset = assets[depositAsset];
        if (!asset.allowDeposits) {
            revert("Deposits not allowed");
        }
        if (depositAmount == 0) {
            revert("Deposit amount must be greater than 0");
        }

        uint256 stethShares;
        if (address(depositAsset) == address(STETH)) {
            stethShares = STETH.getSharesByPooledEth(depositAmount);
        } else if (address(depositAsset) == address(WSTETH)) {
            stethShares = depositAmount;
        } else {
            revert("Unsupported asset");
        }

        // hardcode share calculation for only steth
        shares = _VAULT.getSharesByAssets(stethShares);
        if (shares < minimumMint) revert("Minted shares less than minimumMint");

        _VAULT.depositByTeller(address(depositAsset), shares, stethShares, msg.sender);

        emit ReferralAddress(referralAddress);
    }

    function _updateAssetData(ERC20 asset, bool allowDeposits, bool allowWithdraws, uint16 sharePremium) internal {
        assets[asset] =
            Asset({allowDeposits: allowDeposits, allowWithdraws: allowWithdraws, sharePremium: sharePremium});
    }

    function updateAssetData(ERC20 asset, bool allowDeposits, bool allowWithdraws, uint16 sharePremium) external {
        require(msg.sender == owner, "Only owner can update asset data");
        _updateAssetData(asset, allowDeposits, allowWithdraws, sharePremium);
    }

    function authority() external view returns (address) {
        return owner;
    }

    function vault() external view returns (address) {
        return address(_VAULT);
    }

    // STUBS

    function accountant() external view returns (address) {
        return address(this);
    }

    event NonPure();

    function bulkDeposit(ERC20, uint256, uint256, address) external returns (uint256) {
        emit NonPure();
        revert("not implemented");
    }

    function bulkWithdraw(ERC20, uint256, uint256, address) external returns (uint256) {
        emit NonPure();
        revert("not implemented");
    }
}
