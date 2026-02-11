// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeable } from "../FraxOFTUpgradeable.sol";


contract OFTUpgradeableMock is FraxOFTUpgradeable {

    bool minted;

    constructor(address _lzEndpoint) FraxOFTUpgradeable(_lzEndpoint) {}

    function mintInitialSupply(address _to, uint256 _amount) external {
        require(!minted);
        require(msg.sender == owner());

        _mint(_to, _amount);
        minted = true;
    }
}
