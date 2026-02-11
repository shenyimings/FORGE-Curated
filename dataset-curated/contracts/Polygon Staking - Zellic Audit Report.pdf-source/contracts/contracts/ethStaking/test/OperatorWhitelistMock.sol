// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

contract OperatorWhitelistMock {
    struct WhitelistEntry {
        bool isWhitelisted;
        bool isUsed;
    }

    mapping(address => WhitelistEntry) private whitelist;

    constructor(address[] memory _whitelist) {
        for (uint256 i = 0; i < _whitelist.length; i++) {
            whitelist[_whitelist[i]] = WhitelistEntry(true, false);
        }
    }

    function useWhitelist(address _operator) external view {
        require(whitelist[_operator].isWhitelisted, "Operator is not whitelisted");
        //require(!whitelist[_operator].isUsed, "Operator whitelist spot already used");
        //whitelist[_operator].isUsed = true;
    }

    function getWhitelistEntry(address _operator) external view returns (WhitelistEntry memory) {
        return whitelist[_operator];
    }
}
