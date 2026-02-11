/*
 * SPDX-License-Identifier:    MIT
 */

pragma solidity ^0.6.2;


// aragonOS and aragon-apps rely on address(0) to denote native ETH, in
// contracts where both tokens and ETH are accepted
contract EtherTokenConstant {
    address internal constant ETH = address(0);
}