// SPDX-License-Identifier: Apache-2.0
// THIS IS GENERATED FILE. DO NOT EDIT.
pragma solidity ^0.8.28;

import { IVersioned } from '../interfaces/lib/IVersioned.sol';

contract Versioned is IVersioned {
  string public constant GIT_TAG = '{{git_tag}}';

  string public constant GIT_COMMIT = '{{git_commit}}';
}
