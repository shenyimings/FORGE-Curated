// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DestinationSettler, Route} from "../ERC7683/DestinationSettler.sol";
import {Portal} from "../Portal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AddressConverter} from "../libs/AddressConverter.sol";
import {TokenAmount} from "../types/Intent.sol";

contract TestDestinationSettlerComplete is DestinationSettler {
    using AddressConverter for bytes32;

    Portal public immutable PORTAL;

    constructor(address _portal) {
        PORTAL = Portal(payable(_portal));
    }

    function fulfillAndProve(
        bytes32 _intentHash,
        Route memory _route,
        bytes32 _rewardHash,
        bytes32 _claimant,
        address _prover,
        uint64 _source,
        bytes memory _data
    ) public payable override returns (bytes[] memory) {
        // First, transfer tokens from the solver (msg.sender) to this contract
        uint256 routeTokenCount = _route.tokens.length;
        for (uint256 i = 0; i < routeTokenCount; ++i) {
            TokenAmount memory token = _route.tokens[i];
            IERC20(token.token).transferFrom(
                msg.sender,
                address(this),
                token.amount
            );
            // Then approve the portal to spend these tokens
            IERC20(token.token).approve(address(PORTAL), token.amount);
        }

        // Call the portal's fulfillAndProve function
        return
            PORTAL.fulfillAndProve{value: msg.value}(
                _intentHash,
                _route,
                _rewardHash,
                _claimant,
                _prover,
                _source,
                _data
            );
    }
}
