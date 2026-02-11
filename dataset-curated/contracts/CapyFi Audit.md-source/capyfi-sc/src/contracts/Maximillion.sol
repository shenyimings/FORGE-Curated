// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import './CLac.sol';

/**
 * @title Compound's Maximillion Contract
 * @author Compound
 */
contract Maximillion {
    /**
     * @notice The default cLAC market to repay in
     */
    CLac public cLac;

    /**
     * @notice Construct a Maximillion to repay max in a CLac market
     */
    constructor(CLac cLac_) {
        cLac = cLac_;
    }

    /**
     * @notice msg.sender sends Lac to repay an account's borrow in the cLac market
     * @dev The provided Lac is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     */
    function repayBehalf(address borrower) public payable {
        repayBehalfExplicit(borrower, cLac);
    }

    /**
     * @notice msg.sender sends Lac to repay an account's borrow in a cLac market
     * @dev The provided Lac is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     * @param cLac_ The address of the cLac contract to repay in
     */
    function repayBehalfExplicit(address borrower, CLac cLac_) public payable {
        uint received = msg.value;
        uint borrows = cLac_.borrowBalanceCurrent(borrower);
        if (received > borrows) {
            cLac_.repayBorrowBehalf{value: borrows}(borrower);
            payable(msg.sender).transfer(received - borrows);
        } else {
            cLac_.repayBorrowBehalf{value: received}(borrower);
        }
    }
}
