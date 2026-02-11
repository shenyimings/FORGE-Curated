// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { IAtomicSolver } from "./IAtomicSolver.sol";
import { AccountantWithRateProviders } from "../base/Roles/AccountantWithRateProviders.sol";

/**
 * @title AtomicQueue
 * @notice Allows users to create `AtomicRequests` that specify an ERC20 asset to `offer`
 *         and an ERC20 asset to `want` in return.
 * @notice Making atomic requests where the exchange rate between offer and want is not
 *         relatively stable is effectively the same as placing a limit order between
 *         those assets, so requests can be filled at a rate worse than the current market rate.
 * @notice It is possible for a user to make multiple requests that use the same offer asset.
 *         If this is done it is important that the user has approved the queue to spend the
 *         total amount of assets aggregated from all their requests, and to also have enough
 *         `offer` asset to cover the aggregate total request of `offerAmount`.
 * @author crispymangoes
 */
contract AtomicQueue is ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // ========================================= STRUCTS =========================================

    /**
     * @notice Stores request information needed to fulfill a users atomic request.
     * @param deadline unix timestamp for when request is no longer valid
     * @param offerAmount the amount of `offer` asset the user wants converted to `want` asset
     * @param inSolve bool used during solves to prevent duplicate users, and to prevent redoing multiple checks
     */
    struct AtomicRequest {
        uint64 deadline; // deadline to fulfill request
        uint96 offerAmount; // The amount of offer asset the user wants to sell.
        bool inSolve; // Indicates whether this user is currently having their request fulfilled.
    }

    /**
     * @notice Used in `viewSolveMetaData` helper function to return data in a clean struct.
     * @param user the address of the user
     * @param flags 8 bits indicating the state of the user only the first 4 bits are used XXXX0000
     *              Either all flags are false(user is solvable) or only 1 is true(an error occurred).
     *              From right to left
     *              - 0: indicates user deadline has passed.
     *              - 1: indicates user request has zero offer amount.
     *              - 2: indicates user does not have enough offer asset in wallet.
     *              - 3: indicates user has not given AtomicQueue approval.
     * @param assetsToOffer the amount of offer asset to solve
     * @param assetsForWant the amount of assets users want for their offer assets
     */
    struct SolveMetaData {
        address user;
        uint8 flags;
        uint256 assetsToOffer;
        uint256 assetsForWant;
    }

    // ========================================= GLOBAL STATE =========================================
    AccountantWithRateProviders public immutable accountant;

    /**
     * @notice Maps user address to offer asset to want asset to a AtomicRequest struct.
     */
    mapping(address => mapping(ERC20 => mapping(ERC20 => AtomicRequest))) public userAtomicRequest;

    //============================== ERRORS ===============================

    error AtomicQueue__UserRepeated(address user);
    error AtomicQueue__RequestDeadlineExceeded(address user);
    error AtomicQueue__UserNotInSolve(address user);
    error AtomicQueue__ZeroOfferAmount(address user);
    error AtomicQueue__OnlyCallableInternally();

    //============================== EVENTS ===============================

    /**
     * @notice Emitted when `updateAtomicRequest` is called.
     */
    event AtomicRequestUpdated(
        address user,
        address offerToken,
        address wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    /**
     * @notice Emitted when `solve` exchanges a users offer asset for their want asset.
     */
    event AtomicRequestFulfilled(
        address user,
        address offerToken,
        address wantToken,
        uint256 offerAmountSpent,
        uint256 wantAmountReceived,
        uint256 timestamp
    );

    //============================== CONSTRUCTOR ===============================

    constructor(address _accountant) {
        accountant = AccountantWithRateProviders(_accountant);
    }

    //============================== USER FUNCTIONS ===============================

    /**
     * @notice Get a users Atomic Request.
     * @param user the address of the user to get the request for
     * @param offer the ERC0 token they want to exchange for the want
     * @param want the ERC20 token they want in exchange for the offer
     */
    function getUserAtomicRequest(address user, ERC20 offer, ERC20 want) external view returns (AtomicRequest memory) {
        return userAtomicRequest[user][offer][want];
    }

    /**
     * @notice Helper function that returns either
     *         true: Withdraw request is valid.
     *         false: Withdraw request is not valid.
     * @dev It is possible for a withdraw request to return false from this function, but using the
     *      request in `updateAtomicRequest` will succeed, but solvers will not be able to include
     *      the user in `solve` unless some other state is changed.
     * @param offer the ERC0 token they want to exchange for the want
     * @param user the address of the user making the request
     * @param userRequest the request struct to validate
     */
    function isAtomicRequestValid(
        ERC20 offer,
        address user,
        AtomicRequest calldata userRequest
    )
        external
        view
        returns (bool)
    {
        if (userRequest.offerAmount > offer.balanceOf(user)) return false;
        if (block.timestamp > userRequest.deadline) return false;
        if (offer.allowance(user, address(this)) < userRequest.offerAmount) return false;
        if (userRequest.offerAmount == 0) return false;

        return true;
    }

    /**
     * @notice Allows user to add/update their withdraw request.
     * @param offer the ERC20 token the user is offering in exchange for the want
     * @param want the ERC20 token the user wants in exchange for offer
     * @param deadline unix timestamp for when request is no longer valid
     * @param offerAmount the amount of offer asset to exchange
     */
    function updateAtomicRequest(ERC20 offer, ERC20 want, uint64 deadline, uint96 offerAmount) external nonReentrant {
        AtomicRequest storage request = userAtomicRequest[msg.sender][offer][want];

        request.deadline = deadline;
        request.offerAmount = offerAmount;

        emit AtomicRequestUpdated(msg.sender, address(offer), address(want), offerAmount, deadline, 0, block.timestamp);
    }

    //============================== SOLVER FUNCTIONS ===============================

    /**
     * @notice Called by solvers in order to exchange offer asset for want asset.
     * @notice Solvers are optimistically transferred the offer asset, then are required to
     *         approve this contract to spend enough of want assets to cover all requests.
     * @dev It is very likely `solve` TXs will be front run if broadcasted to public mem pools,
     *      so solvers should use private mem pools.
     * @param offer the ERC20 offer token to solve for
     * @param want the ERC20 want token to solve for
     * @param users an array of user addresses to solve for
     * @param runData extra data that is passed back to solver when `finishSolve` is called
     * @param solver the address to make `finishSolve` callback to
     */
    function solve(
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        bytes calldata runData,
        address solver
    )
        external
        nonReentrant
    {
        (uint256 assetsToOffer, uint256 assetsForWant) = _prepareSolve(offer, want, users, solver);

        IAtomicSolver(solver).finishSolve(runData, msg.sender, offer, want, assetsToOffer, assetsForWant);

        _finalizeSolve(offer, want, users, solver);
    }

    //============================== INTERNAL HELPER FUNCTIONS ===============================
    /**
     * @notice New internal function to handle first phase of solve
     * @dev Validates all user requests and transfers offer tokens to solver
     * @dev Calculates total assets needed using current NAV from accountant
     * @param offer the ERC20 offer token
     * @param want the ERC20 want token
     * @param users array of users to process
     * @param solver the solver address receiving offer tokens
     * @return assetsToOffer total offer tokens transferred to solver
     * @return assetsForWant total want tokens solver needs to provide
     */
    function _prepareSolve(
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        address solver
    )
        internal
        returns (uint256 assetsToOffer, uint256 assetsForWant)
    {
        uint256 rate = accountant.getRateInQuoteSafe(want);
        uint256 offerDecimals = 10 ** offer.decimals();

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest storage request = userAtomicRequest[users[i]][offer][want];

            if (request.inSolve || block.timestamp > request.deadline || request.offerAmount == 0) {
                continue;
            }

            try this.attemptTransfer(offer, users[i], solver, request.offerAmount) {
                assetsForWant += rate.mulDivDown(request.offerAmount, offerDecimals);
                assetsToOffer += request.offerAmount;
                request.inSolve = true;
            } catch {
                continue;
            }
        }
    }

    /**
     * @notice Internal function to handle final phase of solve
     * @dev Transfers want tokens from solver to users and cleans up state
     * @dev Uses same NAV rate for all calculations to ensure consistency
     * @param offer the ERC20 offer token
     * @param want the ERC20 want token
     * @param users array of users to process
     * @param solver the solver address providing want tokens
     */
    function _finalizeSolve(ERC20 offer, ERC20 want, address[] calldata users, address solver) internal {
        uint256 rate = accountant.getRateInQuoteSafe(want);
        uint256 offerDecimals = 10 ** offer.decimals();

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest storage request = userAtomicRequest[users[i]][offer][want];

            if (request.inSolve) {
                uint256 amountOut = rate.mulDivDown(request.offerAmount, offerDecimals);

                want.safeTransferFrom(solver, users[i], amountOut);

                emit AtomicRequestFulfilled(
                    users[i], address(offer), address(want), request.offerAmount, amountOut, block.timestamp
                );

                request.offerAmount = 0;
                request.deadline = 0;
                request.inSolve = false;
            } else {
                revert AtomicQueue__UserNotInSolve(users[i]);
            }
        }
    }

    /**
     * @notice Helper function solvers can use to determine if users are solvable, and the required amounts to do so.
     * @notice Repeated users are not accounted for in this setup, so if solvers have repeat users in their `users`
     *         array the results can be wrong.
     * @dev Since a user can have multiple requests with the same offer asset but different want asset, it is
     *      possible for `viewSolveMetaData` to report no errors, but for a solve to fail, if any solves were done
     *      between the time `viewSolveMetaData` and before `solve` is called.
     * @param offer the ERC20 offer token to check for solvability
     * @param want the ERC20 want token to check for solvability
     * @param users an array of user addresses to check for solvability
     */
    function viewSolveMetaData(
        ERC20 offer,
        ERC20 want,
        address[] calldata users
    )
        external
        view
        returns (SolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer)
    {
        metaData = new SolveMetaData[](users.length);
        uint256 rate = accountant.getRateInQuoteSafe(want);
        uint256 offerDecimalsPow = 10 ** offer.decimals();

        for (uint256 i; i < users.length; ++i) {
            AtomicRequest memory request = userAtomicRequest[users[i]][offer][want];
            metaData[i].user = users[i];

            if (block.timestamp > request.deadline) {
                metaData[i].flags |= uint8(1);
            }
            if (request.offerAmount == 0) {
                metaData[i].flags |= uint8(1) << 1;
            }
            if (offer.balanceOf(users[i]) < request.offerAmount) {
                metaData[i].flags |= uint8(1) << 2;
            }
            if (offer.allowance(users[i], address(this)) < request.offerAmount) {
                metaData[i].flags |= uint8(1) << 3;
            }

            metaData[i].assetsToOffer = request.offerAmount;
            metaData[i].assetsForWant = rate.mulDivDown(request.offerAmount, offerDecimalsPow);

            if (metaData[i].flags == 0) {
                totalAssetsForWant += metaData[i].assetsForWant;
                totalAssetsToOffer += request.offerAmount;
            }
        }
    }

    /**
     * @notice External helper function to enable try-catch with safeTransferFrom
     * @dev Only callable by this contract itself
     * @param token The ERC20 token to transfer
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param amount The amount to transfer
     */
    function attemptTransfer(ERC20 token, address from, address to, uint256 amount) external {
        if (msg.sender != address(this)) revert AtomicQueue__OnlyCallableInternally();
        token.safeTransferFrom(from, to, amount);
    }
}
