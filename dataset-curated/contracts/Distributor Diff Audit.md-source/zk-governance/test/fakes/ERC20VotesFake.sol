// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ERC20VotesFake is ERC20Votes {
  error ERC6372InconsistentClock();

  constructor() ERC20("Fake", "FAKE") ERC20Permit("Fake") {}

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
  }

  function clock() public view virtual override returns (uint48) {
    return SafeCast.toUint48(block.timestamp);
  }

  function CLOCK_MODE() public view virtual override returns (string memory) {
    if (clock() != SafeCast.toUint48(block.timestamp)) {
      revert ERC6372InconsistentClock();
    }
    return "mode=timestamp";
  }
}
