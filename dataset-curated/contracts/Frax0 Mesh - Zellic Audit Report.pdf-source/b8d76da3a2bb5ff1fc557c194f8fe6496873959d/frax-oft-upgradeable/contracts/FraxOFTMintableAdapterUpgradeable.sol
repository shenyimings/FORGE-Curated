// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTAdapterUpgradeable.sol";
import { SupplyTrackingModule } from "./modules/SupplyTrackingModule.sol";

interface IERC20PermitPermissionedOptiMintable {
    function minter_burn_from(address, uint256) external;
    function minter_mint(address, uint256) external;
}

contract FraxOFTMintableAdapterUpgradeable is OFTAdapterUpgradeable, SupplyTrackingModule {
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }

    /// @notice Recover all tokens to owner
    /// @dev added in v1.1.0
    function recover() external {
        uint256 balance = innerToken.balanceOf(address(this));
        if (balance == 0) return;

        innerToken.transfer(owner(), balance);
    }

    /// @notice Set the initial total supply for a given chain ID
    /// @dev added in v1.1.0
    function setInitialTotalSupply(uint32 _eid, uint256 _amount) external onlyOwner {
        _setInitialTotalSupply(_eid, _amount);
    }

    /// @dev overrides OFTAdapterUpgradeable.sol to burn the tokens from the sender/track supply
    /// @dev added in v1.1.0
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        _addToTotalTransferTo(_dstEid, amountSentLD);

        IERC20PermitPermissionedOptiMintable(address(innerToken)).minter_burn_from(msg.sender, amountSentLD);
    }

    /// @dev overrides OFTAdapterUpgradeable to mint the tokens to the sender/track supply
    /// @dev added in v1.1.0
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override returns (uint256 amountReceivedLD) {

        _addToTotalTransferFrom(_srcEid, _amountLD);

        IERC20PermitPermissionedOptiMintable(address(innerToken)).minter_mint(_to, _amountLD);
        return _amountLD;
    }
}
