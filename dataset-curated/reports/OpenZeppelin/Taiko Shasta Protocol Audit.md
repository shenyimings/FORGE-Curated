\- January 29, 2026

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

**Summary**

**Type:**  Layer 2 & Rollups  
**Timeline:**  From 2025-11-10 → To 2025-12-05  
**Languages:**  Solidity

**Findings**  
Total issues: 28 (13 resolved, 2 partially resolved)  
Critical: 6 (4 resolved) · High: 2 (2 resolved) · Medium: 4 (0 resolved, 1 partially resolved) · Low: 9 (5 resolved)

**Notes & Additional Information**  
7 notes raised (2 resolved, 1 partially resolved)

**Client Reported Issues**  
0 issues reported (0 resolved)

Scope
-----

OpenZeppelin performed an audit of the [taikoxyz/taiko-mono](https://github.com/taikoxyz/taiko-mono) repository at commit [5034456](https://github.com/taikoxyz/taiko-mono/commit/503445678a4bd875d761e56ba80a29a5b8e68d6e).

In scope were the following files:

`packages
└── protocol
    └── contracts
        ├── layer1
        │   ├── core
        │   │   ├── iface
        │   │   │   ├── ICodec.sol
        │   │   │   ├── IForcedInclusionStore.sol
        │   │   │   ├── IInbox.sol
        │   │   │   └── IProposerChecker.sol
        │   │   ├── impl
        │   │   │   ├── CodecOptimized.sol
        │   │   │   ├── CodecSimple.sol
        │   │   │   ├── Inbox.sol
        │   │   │   ├── InboxOptimized1.sol
        │   │   │   └── InboxOptimized2.sol
        │   │   └── libs
        │   │       ├── LibBlobs.sol
        │   │       ├── LibBondInstruction.sol
        │   │       ├── LibForcedInclusion.sol
        │   │       ├── LibHashOptimized.sol
        │   │       ├── LibHashSimple.sol
        │   │       ├── LibManifest.sol
        │   │       ├── LibPackUnpack.sol
        │   │       ├── LibProposeInputDecoder.sol
        │   │       ├── LibProposedEventEncoder.sol
        │   │       ├── LibProveInputDecoder.sol
        │   │       └── LibProvedEventEncoder.sol
        │   ├── mainnet
        │   │   └── MainnetInbox.sol
        │   ├── preconf
        │   │   └── impl
        │   │       └── PreconfWhitelist.sol
        │   └── verifiers
        │       ├── IProofVerifier.sol
        │       ├── LibPublicInput.sol
        │       ├── Risc0Verifier.sol
        │       ├── SP1Verifier.sol
        │       ├── SgxVerifier.sol
        │       └── compose
        │           ├── AnyTwoVerifier.sol
        │           ├── AnyVerifier.sol
        │           ├── ComposeVerifier.sol
        │           └── SgxAndZkVerifier.sol
        ├── layer2
        │   └── core
        │       ├── Anchor.sol
        │       ├── AnchorForkRouter.sol
        │       ├── BondManager.sol
        │       └── IBondManager.sol
        └── shared
            ├── fork-router
            │   └── ForkRouter.sol
            └── signal
                ├── ICheckpointStore.sol
                ├── ISignalService.sol
                ├── LibSignals.sol
                └── SignalService.sol` 

Critical Severity
-----------------

### Incorrect Span Handling in `_finalize()` Causes Permanent Finalization Halt

The [`_finalize()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L955-L1046) logic assumes that the `proposalId` processed in each iteration is both:

*   The first unfinalized proposal (`lastFinalizedProposalId + 1`)
*   The last finalized proposal after processing that iteration.

This is only correct when `transitionRecord.span == 1`. When `span > 1`, the function finalizes multiple proposals but only advances `lastFinalizedProposalId` by one, leading to an inconsistent state that permanently breaks finalization.

When an aggregated transition record with `span > 1` is used (as in `InboxOptimized1._buildAndSaveAggregatedTransitionRecords()`), the record is stored only under the first proposal ID of the span (e.g., `proposalId = 100` with `span = 2` covers proposals 100 and 101). During finalization, the loop:

1.  Correctly processes the span record at `proposalId = 100` and finalizes both proposals 100 and 101 logically.
2.  Incorrectly sets `coreState.lastFinalizedProposalId = 100` instead of `101`.
3.  Advances the local `proposalId` to `100 + span = 102` for the next iteration.

On the next `_finalize()` call, the function starts from `coreState.lastFinalizedProposalId + 1 = 101` and attempts to load a transition record keyed by `(proposalId = 101, parentTransitionHash = lastFinalizedTransitionHash)`. Such a record does not exist because the aggregated record was stored at proposal 100. As a result, `_getTransitionRecordHashAndDeadline()` returns `recordHash = 0`, the loop breaks immediately, and no proposals are ever finalized again.

This leaves:

*   `lastFinalizedProposalId` stuck at the first proposal in the span.
*   Unfinalized proposals accumulating.
*   `_getAvailableCapacity()` eventually returning zero because `numUnfinalizedProposals` reaches `ringBufferSize - 1`.
*   `propose()` reverting with `NotEnoughCapacity()`.

The net effect is a permanent DoS of the rollup:

*   No further proposals can be finalized.
*   No new proposals can be created once the ring buffer fills.
*   Prover bonds remain locked, as they are only released during finalization.

This bug only manifests when `span > 1` is used (e.g., in `InboxOptimized1` / `InboxOptimized2` or any similar aggregation implementation). The base `Inbox` contract, which always sets `span = 1`, is not affected.

Consider updating `lastFinalizedProposalId` to the last proposal covered by the span rather than the first.

With this change:

*   For `span = 1`, behavior is unchanged (`lastFinalizedProposalId` advances by exactly one).
*   For `span > 1`, `lastFinalizedProposalId` correctly reflects the last finalized proposal in the span, so the next `_finalize()` call starts at the true next unfinalized proposal, and `_getTransitionRecordHashAndDeadline()` looks up the correct transition record.

_**Update:** Resolved in [pull request #20927](https://github.com/taikoxyz/taiko-mono/pull/20927)._

### Finalization Denial of Service due to Forced Record Hash Mismatch

The [`Inbox`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol) and [`InboxOptimized1`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/InboxOptimized1.sol) contracts facilitate state progression by allowing provers to submit transition records. To maintain state consistency, the system implements a conflict detection mechanism that intends conflicting transitions from ever being finalized by setting the `finalizationDeadline` to the maximum possible value. More specifically, this occurs whenever a submitted transition record hash differs from an existing one for the same proposal and parent.

Although the current finalization logic contains a separate defect that bypasses the deadline check, fixing that defect would expose a Denial of Service vector where valid, non-contradictory transition records are treated as conflicting. There are three distinct vectors where valid proofs result in different hashes, triggering the freeze:

1.  **Aggregation Conflict (`InboxOptimized1`):** `InboxOptimized1` allows [aggregating](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/InboxOptimized1.sol#L194-L208) consecutive proposals. An aggregated record (e.g., covering proposals P1-P5) has a `span > 1` and a hash derived from P5. A single-step record for P1 has `span = 1` and a hash derived from P1. Both are valid, but their hashes differ. An attacker can submit a single-step proof against an honest aggregated proof to trigger the conflict and block finalization.
2.  **Time-Dependent Bond Variance:** Bond instructions depend on `block.timestamp`. A proof submitted [inside the proving window](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibBondInstruction.sol#L82-L84) (no bonds) generates a different hash than a proof submitted moments later [outside the window](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibBondInstruction.sol#L86-L93) (with bonds). Two honest provers racing near the window boundary can accidentally trigger the DoS.
3.  **Prover-Dependent Bond Variance:** In the extended proving window, the designated prover incurs [no liveness bond](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibBondInstruction.sol#L92), while other provers do. Similarly, after the extended proving window, the proposer being the prover incurs [no liveness bond](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibBondInstruction.sol#L93), while other provers do. In either case, the resulting records will differ in their `bondInstructions` list, causing a hash mismatch and triggering the freeze.

The current conflict detection logic is too rigid for the variable nature of transition records. One option is removing the on-chain conflict detection causing the infinite deadline extension. Instead, consider relying on the proof verifier's integrity. Otherwise, consider redesigning the conflict handling logic to manage valid record variations more gracefully. Instead of triggering a permanent freeze upon any hash mismatch, the protocol should differentiate between genuine state contradictions and benign differences in proof structure or bond obligations.

_**Update:** Acknowledged, will resolve. This issues will be addressed with the re-design. The team stated:_

> _Remove on-chain conflict detection entirely. We rely on the multi proof system to detect any conflicts before they are posted on-chain to the `prove` function_

### Chain Continuity Violation in InboxOptimized1 Transition Aggregation

The `InboxOptimized1` contract breaks transition chain continuity when aggregating multiple transitions into a single `TransitionRecord`. In [`_buildAndSaveAggregatedTransitionRecords`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/InboxOptimized1.sol#L175), transitions are grouped based solely on consecutive proposal IDs. While the accumulator’s `transitionHash` and `span` are updated to reflect the latest transition in the group, the function never verifies that each transition’s `parentTransitionHash` matches the `transitionHash` of the previous transition in the batch.

In the non-optimized `Inbox.sol`, continuity is implicitly enforced by finalization: [`_finalize`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L955) looks up the next transition record by `(proposalId, lastFinalizedTransitionHash)`. This means a transition is only accepted if it explicitly declares the current finalized hash as its parent, ensuring that every step in the chain is cryptographically linked to the previous one.

In `InboxOptimized1`, aggregation introduces a “shortcut” record:

1.  The record key is derived from the first transition’s `(proposalId, parentTransitionHash)`.
2.  The record’s `transitionHash` is set to the last transition in the aggregated sequence.
3.  The `span` indicates how many proposals are skipped during finalization.

Because the aggregation loop only checks that proposal IDs are consecutive, an attacker can construct a batch of transitions that is locally valid per-step but globally disconnected from the canonical chain. For example, starting from a finalized transition `A`, the attacker can:

*   Create a valid transition `B` with `parentTransitionHash = hash(A)`.
*   Create another valid transition `C` for the next proposal ID, but with `parentTransitionHash = hash(X)`, where `X` is an arbitrary, non-canonical state.
*   Submit `[B, C]` as a batch. The contract aggregates them into a single record keyed by `(id(B), hash(A))`, with `transitionHash = hash(C)` and `span = 2`.

During finalization, the system finds this aggregated record using the current state `(id(B), hash(A))` and directly updates the chain tip to `hash(C)`, effectively “teleporting” the state from the canonical branch `A` to a branch derived from `X`. The intermediate link “`B` → `C`” is never validated as a proper parent–child relationship, allowing disjoint transitions to be accepted as a valid segment of the chain.

This breaks the core security assumption that every finalized transition must be anchored to the canonical history. An attacker can leverage this to finalize transitions from arbitrary states, including ones that encode invalid balances or bypass protocol invariants, leading to consensus failure and potentially unlimited asset theft or inflation.

To restore safety, the aggregation loop must enforce strict continuity between each pair of aggregated transitions. Before extending the current group with a new transition, the contract should ensure that its parent hash matches the current accumulated `transitionHash`.

_**Update:** Acknowledged, will resolve. This issues will be addressed with the re-design. The team stated:_

> _Change the design to consecutive proving_

### Denial of Service via Unsafe ABI Decoding in Anchor Contract

The [`Anchor`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol) contract facilitates L2 block processing through the [`anchorV4`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L221) function, which accepts an ABI-encoded `ProverAuth` struct as part of its calldata. This data is processed within the `validateProverAuth` function, where [`abi.decode`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L346) is employed to parse the byte array into a structured format for signature verification and prover designation.

The `validateProverAuth` function attempts to decode the provided `proverAuth` bytes without verifying that they form a valid ABI encoding. This [`proverAuth`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibManifest.sol#L50) data is part of the `ProposalManifest` struct that is provided through the blob during regular proposals. If these bytes are malformed (specifically data that satisfies the minimum length requirement but fails decoding) the `abi.decode` operation will revert. Since the successful execution of the `anchorV4` transaction is a system-imposed requirement for L2 block validity, this revert causes the execution engine to mark the block as invalid.

This rejection creates a critical deadlock in the L2 chain derivation process. The off-chain driver, observing the block rejection, enters an infinite retry loop attempting to process the same invalid payload, resulting in a permanent L2 chain halt. With the L2 chain stuck, the state transitions required to prove the L1 proposal can unlikely occur. Consequently, the proposal containing the malformed data cannot be proved or finalized, stalling the finalization of subsequent valid proposals that depend on the halted state.

Consider implementing a robust decoding pattern within the `Anchor` contract by wrapping the `abi.decode` operation in an external call to the contract itself (e.g., `try this.decodeProverAuth(...)`). This architecture allows the contract to catch reverts caused by malformed input. In the catch block, the logic should apply safe fallback values (such as designating the proposer with a zero proving fee) to ensure the `AnchorV4` transaction executes successfully. This modification preserves chain liveness and ensures forced inclusions can be processed regardless of data malformation.

_**Update:** Resolved in [pull request #20912](https://github.com/taikoxyz/taiko-mono/pull/20912). The team stated:_

> _Wrap the call to `validateProverAuth`in a try/catch statement. Additionally, an unfound issue in this contract was the proverAuthLength, which has been changed in the same fix PR._

### Lack of Cryptographic Binding Between Proof and Guest Program ID

The [`Risc0Verifier`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/Risc0Verifier.sol#L1) and [`SP1Verifier`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SP1Verifier.sol#L1) contracts employ a recursive verification architecture where a generic aggregation program verifies proofs generated by specific guest programs. These guest programs are identified by a [`blockImageId`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/Risc0Verifier.sol#L60) (for Risc0) or [`blockProvingProgram`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SP1Verifier.sol#L59) (for SP1). The respective `verifyProof` functions in both contracts take a cryptographic `seal` (or proof data) and check that the provided guest program ID is listed in their `isImageTrusted` or `isProgramTrusted` mappings before calling the external verifier (e.g., `riscoGroth16Verifier` or `sp1RemoteVerifier`) to validate the seal against the `aggregationImageId`/`aggregationProgram` and `journalDigest`/`publicInput`.

However, the current implementations fail to enforce a cryptographic link between the verified proof and the claimed guest program ID. The external verifiers (`riscoGroth16Verifier.verify` and `ISP1Verifier.verifyProof`) confirm that the aggregation program ran correctly and produced the given journal/public input, but they do not verify which inner program the aggregation program executed. This means an attacker can execute a malicious guest program to generate an invalid state transition, aggregate this proof using the legitimate aggregation program, and submit it to `verifyProof` alongside the trusted `blockImageId`/`blockProvingProgram`. Since the contracts do not verify that the aggregation proof actually attested to the trusted guest program ID, the malicious proof is accepted, allowing the attacker to bypass the validity rules of the protocol.

Consider updating the Risc0 and SP1 aggregation circuits to expose the verified inner guest program ID (e.g., `blockImageId`, `blockProvingProgram`) within their `journalDigest` and `publicInput`. The `verifyProof` functions should then be updated to validate that the guest program ID actually verified by the circuit matches the trusted guest program ID required by the protocol.

_**Update:** Resolved in [pull request #20916](https://github.com/taikoxyz/taiko-mono/pull/20916). The team stated:_

> _Expose sub image ID to be aggregated to public input_

### Problematic Conflict Resolution Design

The current [`TransitionConflictDetected`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/iface/IInbox.sol#L213) design assumes that, once a conflict is detected, finalization is effectively paused until governance deploys an upgrade that bumps [`_compositeKeyVersion`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L125) and “wipes” transition records. Even if everything behaves honestly (no bypasses, no malicious finalization), this design still introduces several serious problems on both L1 and L2.

When `conflictingTransitionDetected` is set:

*   [`_finalize`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L955) is effectively blocked for the conflicting proposal (and for all later proposals, since the chain cannot safely move forward).
*   New proposals continue to be stored in [`_proposalHashes`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L143) (a ring buffer).
*   New proofs continue to be stored in transition records keyed by `_compositeKeyVersion` and proposal id.
*   Recovery is expected via a contract upgrade that increments `_compositeKeyVersion`, making all existing transition records unreachable.

Under these assumptions, the following issues arise.

#### 1\. From delayed finalization to full unavailability

The system continues to accept [`propose()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L232), [`prove()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L300), and [`saveForcedInclusion()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L324) after a conflict is detected:

*   `lastFinalizedProposalId` is stuck, but `nextProposalId` keeps increasing.
*   The ring buffer fills with proposals that cannot be finalized until the conflict is resolved.
*   Once the number of pending proposals reaches `_ringBufferSize`, `_getAvailableCapacity` returns zero and `propose()` reverts with `NotEnoughCapacity`.

At this point, the protocol moves from “just delayed finalization” to complete unavailability: no more proposals can be accepted and no existing proposals can be finalized.

#### 2\. Permanent deadlock due to “wrong-fork” proposals

The current recovery mechanism only invalidates transition records via `_compositeKeyVersion` bumps; it does **not** touch proposals already stored in `_proposalHashes`. This creates a permanent deadlock if governance needs to re-root the chain on a different parent.

**Scenario**

1.  A buggy or malicious transition A is finalized as lastFinalizedTransitionHash. New proposals are added to the ring buffer with parentHash values that ultimately depend on A, and their coreStateHash implicitly certifies A as the correct parent state.
2.  A later proposal triggers a conflict that reveals A was incorrect. Finalization pauses, but `propose()` continues, so more proposals referencing the chain with A accumulate in the ring buffer.
3.  Governance upgrades and bumps `_compositeKeyVersion`. Existing transition proofs are discarded, but all proposals (including those built on A) remain in `_proposalHashes` with their original `parentHash`.
4.  Governance decides the canonical parent should instead be **B** (a chain that does _not_ include A).

**Deadlock**

When finalization resumes:

*   `_finalize` processes proposals in ring-buffer order, starting from `lastFinalizedProposalId + 1`.
*   The next pending proposal still has a `parentHash` on the fork including A.
*   `_finalize` asks for a valid transition proof for a **child of A** under the new `_compositeKeyVersion`.

No honest prover can supply such a proof, because A is no longer part of the intended canonical chain (we want to build on B). The contract also has no mechanism to:

*   skip this wrong-fork proposal,
*   rebind it to B, or
*   prune it from the ring buffer.

So `_finalize` is stuck waiting for a proof that cannot exist; `lastFinalizedProposalId` never advances, its ring-buffer slot is never freed, and if the buffer is saturated with similar wrong-fork proposals:

*   `propose()` reverts with `NotEnoughCapacity`, and
*   the Inbox is effectively **permanently bricked**, even after governance “fixes” the canonical parent.

#### 3\. “Zombie proofs” and weakened slashing due to delayed fix

Between conflict detection and the upgrade, provers are still allowed to call `prove()`:

*   They pay proof-verification costs and submit proofs tied to the current `_compositeKeyVersion`.
*   When `_compositeKeyVersion` is later incremented, all these proofs are silently invalidated.
*   No slashing or reward instruction is ever generated for them; honest provers lose expected rewards and waste gas, while malicious provers may avoid penalties.

This is worsened by the interaction with the L2 bond withdrawal logic:

*   Bond logic is on L2 in `BondManager.sol`.
*   `requestWithdrawal()` checks only the user’s L2 bond balance; it does **not** check any L1 Inbox state (such as `conflictingTransitionDetected`).
*   On L1, `propose()` is not paused by the conflict flag, so L2 blocks and timestamps keep progressing, eventually satisfying `withdrawalDelay`.

If governance reacts slowly (manual intervention takes longer than `withdrawalDelay`):

*   A malicious actor can trigger a conflict, then immediately call `requestWithdrawal()` on L2.
*   If governance resolves the conflict and attempts to slash after `withdrawalDelay` has passed, the malicious actor can already have called `withdraw()` and drained their bond.
*   Subsequent slashing instructions will fail because `debitBond` can only take funds that still exist (which may now be zero).
*   Honest provers, seeing the conflict and uncertainty, are also incentivized to rush to withdraw, reducing the security budget and harming liveness.

#### 4\. Forced inclusions continue during conflict, enabling cheap griefing

The protocol does not pause forced inclusions when a conflict is detected. This is not just a liveness choice; it creates a concrete vulnerability:

*   Attack vector: An attacker can continue to submit forced inclusions and then use the permissionless proposal fallback to propose them, bypassing the whitelist and rapidly filling the ring buffer with “zombie” proposals. This can permanently brick the Inbox.
*   Cost recovery: Because `propose()` refunds forced inclusion fees to the `msg.sender`, the attacker can recycle their own fees. The effective cost of flooding the system is mostly gas, making the griefing attack cheaper.
*   User harm: Legitimate users can be tricked into paying for forced inclusions during the conflict. If their transaction ends up in a proposal built on a transition that governance later discards (wrong fork), or if recovery requires resetting ring-buffer state and discarding these proposals, their forced inclusion fee is irrecoverably paid to the proposer while their transaction never finalizes.

#### 5\. Conflict flag does not act as a circuit breaker

The `conflictingTransitionDetected` flag:

*   Does **not** gate `propose()`, `prove()`, or `saveForcedInclusion()`.
*   Provides no on-chain backpressure to off-chain infrastructure or users.

As a result, the system keeps accepting work (proposals, proofs, inclusions) even though it cannot make forward progress and is very likely to discard that work during a later upgrade. This creates predictable, systemic gas waste and potential bond loss.

#### 6\. Upgrade path is a coarse “nuclear option”

Relying solely on `_compositeKeyVersion` bumps for recovery is overly coarse:

*   All pending proofs are discarded, including those unrelated to the conflict, and must be re-proven.
*   Governance has no ability to prune or skip proposals whose `parentHash` is known to be invalid.
*   Governance cannot mark specific proposal ids as resolved in favor of a given transition hash and then resume finalization from there.

Instead, the protocol is forced into a full “invalidate everything and rebuild from scratch” cycle, which is slow, expensive, and fragile.

A more robust design for conflict handling should:

*   Treat `conflictingTransitionDetected` as a hard circuit breaker on `propose()`, `prove()`, and `saveForcedInclusion()`, preventing new proposals and proofs after a conflict and avoiding ring-buffer saturation and zombie proofs.
*   Provide governance/admin functions to:
    
*   Explicitly resolve conflicts by assigning a canonical transition hash for a particular proposal id and clearing the conflict state.
    
*   Prune, skip, or otherwise discard proposals whose `parentHash` does not match the canonical `lastFinalizedTransitionHash`, freeing ring-buffer slots and preventing permanent deadlocks.
*   Include explicit unwind paths for bonds and proof-related state so that honest provers can recover funds when a version or set of records is invalidated by a conflict-driven upgrade.

As an alternative direction, it may be safer to remove on-chain conflict detection entirely and rely on a “Multi-Proof” strategy with Aggregation (AND), combined with robust off-chain watchtowers that:

*   Verify every finalized transition against a local node.
*   Alert the team immediately if the on-chain hash diverges from the local view (since the contract would no longer raise a conflict flag).

This alternative is only safe if the multi-proof design makes conflicting transitions extremely unlikely and if the off-chain monitoring and response process is strong and well-tested.

_**Update:** Resolved in [pull request #20927](https://github.com/taikoxyz/taiko-mono/pull/20927)._

High Severity
-------------

### Unfinalizable Proposals via Aggregation Overflow

The `InboxOptimized1` contract reduces gas costs by aggregating consecutive proposals into a single `TransitionRecord` during proving. This record uses a `uint8` `span` field to track how many proposals are covered. However, [`_buildAndSaveAggregatedTransitionRecords`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/InboxOptimized1.sol#L175) allows aggregating more than 255 proposals in an `unchecked` block. When 256 consecutive proposals are aggregated, `span` overflows from 255 to 0. This invalid `TransitionRecord` (with `span = 0`) is then hashed and stored in `_transitionRecordHashAndDeadline`, corrupting state and permanently bricking the finalization process.

In [`_finalize()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L955-L1046), the stored record cannot be reconciled:

1.  **Hash mismatch:** If the caller supplies the mathematically correct record (with `span = 256`), its hash will not match the stored hash (computed over `span = 0`).
2.  **Sanity check failure:** If the caller instead supplies the stored record (with `span = 0`) so the hash matches, `_finalize()` reverts on `require(transitionRecord.span > 0, InvalidSpan())`.

This creates an unresolvable deadlock: the affected `TransitionRecord` can never be finalized, so `lastFinalizedProposalId` stops advancing. As new proposals continue to be submitted, the number of unfinalized proposals eventually reaches the `ringBufferSize` (e.g., 16,800 on mainnet). At that point, `propose()` permanently reverts with `NotEnoughCapacity()`, halting the system.

An attacker who can generate valid proofs (e.g., a prover) can exploit this by:

1.  Waiting for 256 consecutive proposals to be submitted, optionally contributing some of them if they have permission to propose.
2.  Calling `prove()` once with a valid proof that covers these 256 proposals.
3.  Triggering aggregation into a single `TransitionRecord` whose `span` overflows to 0, permanently blocking finalization for that range.

Consider changing `TransitionRecord.span` to a larger type (e.g., `uint16`), or add a check in `_buildAndSaveAggregatedTransitionRecords` to cap aggregation at 255 proposals per record.

_**Update:** Resolved in [pull request #20927](https://github.com/taikoxyz/taiko-mono/pull/20927)._

### Ineffective Conflict Handling Allows Finalization of Conflicted Transitions

The conflict handling mechanism used between [`InboxOptimized1`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/InboxOptimized1.sol#L89-L128) and [`Inbox`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L533-L557) fails to prevent finalization of transitions that have been explicitly flagged as conflicted. When `InboxOptimized1` detects a hash collision for the same proposal and parent (i.e., same key in the ring buffer but different transition data), it overwrites the slot with the new transition and sets its `finalizationDeadline` to the maximum value, intending to mark the entry as permanently non-finalizable.

The enforcement of this flag is delegated to the `_finalize` logic in `Inbox`. However, `_finalize` only considers the `finalizationDeadline` in the path where no transition data is supplied by the caller (implicit finalization). When the caller explicitly provides a `TransitionRecord` in the calldata, `_finalize` only checks that the supplied record matches the stored hash and immediately updates the chain state, ignoring the stored `finalizationDeadline`. As a result, the “never finalize” marker applied to conflicting transitions is not honored in the explicit finalization path.

An attacker can exploit this mismatch as follows:

1.  A legitimate prover stores a valid transition for a given proposal and parent state.
2.  A malicious prover submits a conflicting transition with the same proposal and parent, causing `InboxOptimized1` to overwrite the ring buffer slot and set its deadline to the maximum value.
3.  A proposer, acting in coordination with the malicious prover, then calls the propose entrypoint and includes this conflicting transition in the list of transition records passed as input.
4.  During finalization, the contract observes that the supplied record matches the stored hash and finalizes it, never checking the stored `finalizationDeadline`.
5.  The conflicting transition becomes canonical, and the original valid transition is effectively discarded.

This behavior completely undermines the intended conflict mitigation mechanism. Any transition that has been flagged as conflicted can still be finalized by anyone willing to provide its data explicitly, allowing malicious or incorrect transitions to replace valid ones and weakening the guarantees around honest prover outcomes.

To address this, the finalization logic should always enforce the conflict and deadline semantics regardless of how the transition data is supplied. The contract should consistently read both the stored hash and the associated deadline (or conflict flag), and refuse to finalize transitions that are marked as conflicted or otherwise not eligible, even when the caller provides a matching `TransitionRecord` in calldata.

_**Update:** Resolved in [pull request #20927](https://github.com/taikoxyz/taiko-mono/pull/20927). The team removed the on-chain conflict detection entirely. The protocol now relies on the multi proof system to detect any conflicts before they are posted on-chain to the `prove` function._

Medium Severity
---------------

### Inconsistent Inheritance Patterns and Defective Initialization Logic

The protocol's upgradeability architecture and storage management strategy exhibit multiple structural inconsistencies and functional defects, primarily seen in the [`AnchorForkRouter`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/AnchorForkRouter.sol#L56) and [`Anchor`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L26) contracts. The following specific issues complicate the maintainability of the codebase and compromise its initialization security:

*   The design relies on complex inheritance chains to maintain storage slot compatibility, which is brittle and difficult to audit.
*   Inheritance usage is inconsistent, with some contracts [utilizing `EssentialContract`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L26) while others separately inherit [`UUPSUpgradeable` and `Ownable2StepUpgradeable`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/shared/fork-router/ForkRouter.sol#L22), which [`EssentialContract` extends](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/shared/common/EssentialContract.sol#L10).
*   The system lacks a functional mechanism to initialize the `owner` address within the proxy's storage, rendering inherited access control modifiers ineffective and upgradeability impossible.
*   The current structure creates ambiguity regarding whether initialization logic is intended to execute within the `AnchorForkRouter` or the delegated `Anchor` contract.
*   The [`_transferOwnership`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L206) invocation in the Anchor constructor only affect's the implementation's state, not the Proxy's.
*   Constructors in implementation contracts do not consistently invoke `_disableInitializers()`, leaving them potentially open to initialization.

Consider migrating to [EIP-7201](https://eips.ethereum.org/EIPS/eip-7201) (Namespaced Storage Layout) to decouple storage management from inheritance and eliminate layout confusion. However, be mindful that this breaking change would need careful consideration. To resolve the initialization failures, implement a functional `initialize` function to correctly set the proxy owner, ensure all implementation constructors call `_disableInitializers()`, and improve documentation to clarify the intended upgradeability lifecycle.

_**Update:** Partially Resolved in [pull request #20811](https://github.com/taikoxyz/taiko-mono/pull/20811). The team stated:_

> _It is true that the fork router design is complex, and that's why we've tried to document it extensively. Unfortunately it is necessary to allow us to do breaking changes to the contracts(which this fork does on most of them), and still be able to deploy the contracts before the fork activates. After the fork activates we plan to do another proposal to the DAO to eliminate the fork routers, and that way the inheritance chain will become simpler._
> 
> _As far as we can tell, there's no issues in the storage itself so we don't think this should classified as an issue, or in any case as a low or note(given it is a design decision, and not a bug)._
> 
> _Fix: The ownership initialization has been removed from the Anchor constructor on this [PR](https://github.com/taikoxyz/taiko-mono/pull/20811), altough it was never an issue on mainnet since the contract has already been initialized. We've also added [storage layout files](https://github.com/taikoxyz/taiko-mono/pull/20928) for both fork routers so that it becomes easier to review their layouts align with those of the contracts they route to._

### Missing Synchronization Between BondManager and PreconfWhitelist Allows Low-Bond “Zombie” Proposers

[`BondManager`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/BondManager.sol) and [`PreconfWhitelist`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/impl/PreconfWhitelist.sol) are not kept in sync, allowing operators that are no longer properly bonded to remain whitelisted and continue to be selected as proposers.

When a proposer is slashed below `minBond` or requests a withdrawal, `BondManager` immediately treats them as low-bond. However, this change is not propagated to `PreconfWhitelist`: the operator stays whitelisted until an external actor removes them. The current [ejector](https://github.com/taikoxyz/taiko-mono/tree/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/ejector) monitor only reacts to whitelist and liveness events and does not monitor bonding state.

If such a low-bond (or withdrawing) proposer is selected for an epoch, upstream logic detects that they are not properly bonded and replaces their proposals with default/empty manifests. This leads to:

*   Reduced liveness, as slots or epochs can be wasted on empty manifests instead of user transactions.
*   Wasted L1 gas and operational overhead on proving structurally irrelevant proposals.
*   Poor UX due to delayed and unpredictable transaction inclusion from economically invalid but still-whitelisted “zombie” operators.
*   All components behave “as designed” (no obvious failures), so standard monitoring may not flag that liveness is being silently eroded by economically invalid but still-whitelisted “zombie” operators.

Proposer eligibility should be derived from bonding state to close this gap. Extend the ejector/watchdog to subscribe to `BondManager` events (slashing, withdrawal requests) and automatically remove affected operators from `PreconfWhitelist` as soon as they become low-bond or initiate withdrawal.

This ensures only properly bonded operators are eligible, preserving liveness and avoiding unnecessary gas costs and user disruption.

### Inconsistent `Proved` Event Payload Creates Data Availability Gap for Aggregated Transitions

The [`InboxOptimized1`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/InboxOptimized1.so) contract aggregates multiple consecutive transitions into a single `TransitionRecord` when `span > 1`. In this case, [`_setTransitionRecordHashAndDeadline`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L501) emits a `Proved` event containing:

*   `transition`: the transition data for the first proposal in the aggregated span, including its full `Checkpoint` (block hash and state root).
*   `transitionRecord`: the aggregated record for the last proposal in the span, including only the `checkpointHash` of its `Checkpoint`.

However, the event never exposes the full `Checkpoint` preimage for the end of the span, only its hash.

The off-chain indexer ([`shasta_indexer`](https://github.com/taikoxyz/taiko-mono/blob/72998ad3358658a51fb4e0fbfa8e60370b29eeab/packages/taiko-client/pkg/state_indexer/indexer.go)) that consumes this `Proved` event mirrors the event payload as-is. It does not derive or fetch the missing end-of-span `Checkpoint` preimage needed for finalization.

This design conflicts with the intended usage of the event stream as a self-sufficient data source for constructing `ProposeInput`. The `propose` function expects a `ProposeInput.checkpoint` whose hash matches `record.checkpointHash` for the last finalized transition. Any Proposer relying solely on this event-driven indexer cannot construct a valid `ProposeInput` for aggregated proofs without additional L2 queries.

Even if this behavior is intentional from a protocol design perspective, it introduces a data availability gap for L1 operations:

*   The L1 `Proved` event stream is no longer sufficient to drive finalization for aggregated transitions.
*   If the L2 RPC is unavailable, out-of-sync, or restricted, finalization of aggregated spans can stall despite valid proofs being present on L1.
*   This harms liveness and undermines the robustness and decentralization benefits of using L1 events as the primary source of truth.

To preserve the self-sufficiency of the L1 event stream and avoid this gap, consider extending the `Proved` event to include the full `Checkpoint` for the end of the span (in addition to or instead of the start), so off-chain components can reconstruct `ProposeInput` directly from logs. Alternatively, emit an additional event containing the end-of-span `Checkpoint` whenever an aggregated `TransitionRecord` is created.

### Forced Inclusion and Permissionless Fallback Can Be Throttled via `LastProcessedAt` Coupling

The forced inclusion mechanism currently decides when the head of the queue is “due” based on:

> [`max(submission_timestamp, lastProcessedAt) + forcedInclusionDelay`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibForcedInclusion.sol#L172C39-L172C83)

Whenever any forced inclusion is processed, [`_dequeueAndProcessForcedInclusions`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L883) updates `lastProcessedAt` to `block.timestamp`. The permissionless inclusion logic reuses the same pattern to compute the timestamp after which anyone may propose.

Because the queue is FIFO, a specific transaction cannot be censored forever, but a malicious proposer can throttle the rate at which the queue clears:

*   When the head becomes due, the proposer processes only `minForcedInclusionCount` (set to 1 on mainnet).
*   This updates `lastProcessedAt` to “now”, so the next transaction’s due time becomes roughly now + `forcedInclusionDelay`.
*   Repeating this pattern makes the delay for a transaction at position `k` roughly `k × forcedInclusionDelay`, rather than being bounded by a single delay window.

The permissionless fallback is weakened more severely. It is intended to activate if transactions have waited longer than `forcedInclusionDelay × multiplier`, but because its threshold is also based on `max(submission_timestamp, lastProcessedAt)`, a proposer can keep `lastProcessedAt ≈ now` by including a single forced inclusion whenever needed. This continuously pushes the permissionless deadline into the future, so `allowsPermissionless` never becomes true while the malicious proposer (or cartel) remains in control, even if some entries have been waiting far longer than the intended bound.

Proposer incentives and rotation mitigate some scenarios but do not remove the risk:

*   **Proposer rotation:** If at least one honest proposer appears in the rotation, they are economically motivated to clear the queue and collect the fees. This limits censorship in a healthy system, but the permissionless fallback is specifically designed for worst-case conditions (e.g., majority collusion or a systemic bug). Under those assumptions, this coupling to `lastProcessedAt` breaks the intended safety valve.
*   **Fee incentives:** Forced inclusion fees grow with queue depth (e.g., `fee = baseFee × (1 + numPending / threshold)` with `baseFee ≈ 0.01 ETH` and `threshold = 50` on mainnet). This makes spamming expensive for an external attacker and creates a direct incentive for proposers to include forced inclusion transactions and clear the queue. However, a proposer may still rationally prefer censorship or throttling (e.g., to preserve an L2 MEV/arbitrage position) over collecting these fees, and the protocol allows them to do so while remaining “compliant” by processing only one forced inclusion per opportunity.
*   **Colluding proposers:** If proposers coordinate, they can fill the forced inclusion queue using their own transactions and effectively “refund” themselves the forced inclusion fees. They still incur L1 data costs and bear the risk that a future honest proposer clears the queue and captures the fees, but as long as the cartel remains in control, they can maintain a long, throttled queue and keep permissionless fallback disabled.

The core design flaw is that liveness guarantees and permissionless activation are defined relative to `lastProcessedAt` (the proposer’s last activity) instead of strictly to submission timestamps. This lets a censoring or lazy proposer set keep the system in a low-throughput, high-latency state and prevent the permissionless safety mechanism from ever activating during their control window.

A more robust design should derive both forced-inclusion due-ness and permissionless thresholds solely from submission timestamps, ensuring that once a transaction has aged beyond the configured delay (and multiplier, if applicable), it becomes irrevocably due, regardless of how often the current proposer touches the queue.

_**Update:** Acknowledged, will resolve. This issues will be addressed with the re-design. The team stated:_

> _While initially a design decision to avoid forced inclusions to spam the prover too quickly, we ended up deciding to remove `lastProcessedAt`_
> 
> _Fix: Remove `lastProcessedAt` field_

Low Severity
------------

### Misleading Documentation

Several comments and interface descriptions are inconsistent with the actual contract behavior and data layout, which can mislead integrators and auditors about security guarantees, storage usage, and protocol semantics.

The following inconsistencies were identified:

*   **L2 withdrawal restrictions misdocumented in `IBondManager`**  
    The interface describes [L1 withdrawals as time-gated and L2 withdrawals as “unrestricted”](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/IBondManager.sol#L90-L95), while the L2 `BondManager` implementation actually enforces both a minimum remaining bond and a time-based withdrawal delay via `withdrawalRequestedAt`. This understates the true restrictions on L2 withdrawals and misrepresents the withdrawal security model.
    
*   **Incorrect L1 reference in `BondManager` header**  
    The `BondManager` contract lives under an L2 path and is used by the L2 `Anchor` contract, yet its header still calls it the “[L1 implementation of BondManager”](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/BondManager.sol#L10). This outdated wording contradicts its real environment and usage.
    
*   **Wrong storage size documented for `ReusableTransitionRecord`**  
    The [`ReusableTransitionRecord`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/InboxOptimized1.sol#L29) struct is documented as using 304 bits, but in reality it is using 512 bits total. This can lead to incorrect assumptions about storage packing and gas costs.
    
*   **Overstated guarantees for `getProposalHash`**  
    [`getProposalHash`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L372) is documented as returning the proposal hash by proposal ID, but due to the ring buffer, older hashes may be overwritten when the buffer wraps. The comment omits this limitation, encouraging readers to assume hashes are retained indefinitely and uniquely indexed by ID, which is not the case.
    
*   **Misleading `_newInstance` parameter semantics in `hashPublicInputs`**  
    `_newInstance` parameter of the [`hashPublicInputs`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/LibPublicInput.sol#L18) is described as a new signing address for the SGX verifier, but in [`verifyProof`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SgxVerifier.sol#L126) it does not appear to be persisted for future proofs. This creates confusion around how (or whether) verifier instances or keys are actually rotated, and may cause integrators to overestimate the key-rotation behavior.
    
*   **Incorrect description of `authorized` in L2 `BondManager`**  
    The [`authorized`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/BondManager.sol#L20) immutable is documented as the inbox, although in practice it is the `Anchor` contract. This mislabels which component is actually allowed to call privileged functions and can confuse reasoning about cross-contract interactions.
    
*   **Non-enforced limit on forced inclusions in `LibForcedInclusion`**  
    A comment in [`LibForcedInclusion`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibForcedInclusion.sol#L18) claims forced inclusions are limited to [one L2 block only](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibForcedInclusion.sol#L15), but no such limit is enforced in the code. Readers may therefore reason under a constraint that does not exist, which is especially risky when analyzing DoS vectors or worst-case resource usage.
    

These discrepancies should be fixed so that comments and interfaces accurately describe behavior, roles, and constraints. Keeping the documentation aligned with the implementation makes the security model clearer and reduces the risk of incorrect assumptions in integration and review.

_**Update:** Resolved in pull requests [#20932](https://github.com/taikoxyz/taiko-mono/pull/20932), [#20884](https://github.com/taikoxyz/taiko-mono/pull/20884), and [#20781](https://github.com/taikoxyz/taiko-mono/pull/20781)._

### Proving Window Misconfiguration Leads to Altered Bond Mechanics

The `Inbox` constructor copies [`provingWindow` and `extendedProvingWindow`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L166-L188) from the config without enforcing `extendedProvingWindow >= provingWindow`.

Bond classification for a transition is derived in [`_buildTransitionRecord`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L613-L628) via [`calculateBondInstructions`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibBondInstruction.sol#L67-L109). Proofs are classified as on-time if `proofTimestamp <= proposal.timestamp + provingWindow`, and late vs very-late using `extendedProvingWindow`. When `extendedProvingWindow < provingWindow`, the interval `(provingWindow, extendedProvingWindow]` is empty, so every proof after `provingWindow` is treated as very-late. This shifts the bond type from liveness to provability and the payer from `designatedProver` to `proposer`, and the resulting instructions are applied to balances by [`_processBondInstructions`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L428-L463).

For example, with `provingWindow = 4h` and `extendedProvingWindow = 2h`, a proof submitted at `T + 5h` after proposal time `T` is always classified as very-late, eliminating the intended “late” band and altering incentives for external provers.

Enforce `extendedProvingWindow >= provingWindow` in the `Inbox` constructor to prevent misconfigured deployments, and additionally validate and document this invariant at configuration-generation and monitoring layers as defense in depth.

_**Update:** Resolved in [pull request #20927](https://github.com/taikoxyz/taiko-mono/pull/20927)._

### Default Fail-Open Configuration for SGX Enclave Attestation

The [`SgxVerifier`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SgxVerifier.sol) contract relies on the [`AutomataDcapV3Attestation`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/automata-attestation/AutomataDcapV3Attestation.sol) contract for verifying the legitimacy of SGX enclaves. A critical aspect of this verification is ensuring that the attested enclave's `MRENCLAVE` and `MRSIGNER` measurements match a set of predefined trusted values. This check is controlled by the `checkLocalEnclaveReport` state variable within the `AutomataDcapV3Attestation` contract.

The [`checkLocalEnclaveReport`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/automata-attestation/AutomataDcapV3Attestation.sol#L37) state variable remains `false` by default. This configuration causes the essential `MRENCLAVE` and `MRSIGNER` validation steps to be conditionally bypassed. Consequently, any SGX enclave capable of generating a cryptographically valid Intel quote, regardless of the software it executes, can be successfully registered by the `SgxVerifier`. Although the system relies on an honest owner to properly configure parameters, an insecure default configuration creates an unnecessary attack surface.

Consider modifying the `AutomataDcapV3Attestation` contract to set the `checkLocalEnclaveReport` variable to `true` during initialization. This change would ensure that critical enclave identity checks are active by default, requiring a deliberate action from the owner to disable them, thereby aligning with a "secure by default" posture.

### Re-activation Causes Permanent DoS Due to Stale Ring Buffer State

The `Inbox` contract includes an [`activate`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L208) function designed to initialize the system or handle L1 reorgs during the initial 2-hour activation window. This function resets core state variables, such as `nextProposalId`, to their genesis values. The contract utilizes a ring buffer (`_proposalHashes`) to store proposal hashes, enforcing sequential validity by checking the content of the next buffer slot. Specifically, if the next slot is occupied, the logic in `_verifyChainHead` assumes the buffer has wrapped around and requires proof that the proposal in the next slot is strictly older than the current chain head.

A vulnerability exists where calling `activate` a second time fails to clear previously stored proposal hashes from the ring buffer. If any proposals were submitted between the first and second activation, their hashes remain in `_proposalHashes`. Upon reset, `nextProposalId` returns to 1 (for the first new proposal), which targets index 1 in the buffer. The contract [detects the non-zero hash](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L1105) from the "old" proposal at this index and enforces the wrap-around logic. This requires the `id` of the proposal in slot 1 (which is 1) to be less than the `id` of the genesis proposal (which is 0). This condition is impossible to satisfy (`1 < 0`), causing all subsequent proposal submissions to revert and rendering the contract permanently unusable.

Consider iterating through the ring buffer within the `_activateInbox` function to clear any stale hashes up to the previous `nextProposalId` before resetting the state. Given that this function is restricted to the first two hours of operation and proposal throughput is constrained by block times and whitelisted proposers, the number of slots to clear will remain well within the block gas limit. This ensures that the ring buffer correctly reflects a fresh state, preventing the erroneous trigger of wrap-around logic and maintaining chain availability.

### Beacon Block Root Retrieval Lacks Fallback for Missed Slots

The `PreconfWhitelist` contract determines the active operator for a given epoch by [deriving randomness](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/impl/PreconfWhitelist.sol#L280) from the beacon block root associated with the epoch's start timestamp. This randomness is retrieved via the `_getRandomNumber` function, which currently queries the beacon roots contract for the exact timestamp of the epoch boundary.

The use of [`LibPreconfUtils.getBeaconBlockRootAt`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/libs/LibPreconfUtils.sol#L60) strictly requires a block to exist at the specific calculation timestamp. If the slot at the epoch boundary is missed, the function returns `bytes32(0)`, resulting in a randomness value of zero. This causes the operator selection logic to deterministically default to the operator at index 0, which introduces a selection bias.

Consider replacing the call to `getBeaconBlockRootAt` with [`getBeaconBlockRootAtOrAfter`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/libs/LibPreconfUtils.sol#L39) within the `_getRandomNumber` function. This change ensures that if the boundary slot is missed, the system correctly locates the next available valid beacon block root, thereby preserving the intended randomness distribution and removing the dependency on a single operator during network anomalies.

_**Update:** Resolved in [pull request #20992](https://github.com/taikoxyz/taiko-mono/pull/20992)._

### Code Improvement Opportunities

Several opportunities to enhance code quality, maintainability, and efficiency were identified through the removal of redundant checks, leveraging more efficient EVM opcodes, and improving data structure and type handling.

1.  **Inconsistent Constructor Input Validation in `SP1Verifier.sol`**: The [constructor](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SP1Verifier.sol#L32) of `SP1Verifier.sol` does not include non-zero checks for the `_taikoChainId` and `_sp1RemoteVerifier` parameter. This contrasts with the [validation](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/Risc0Verifier.sol#L34-L35) present in `Risc0Verifier.sol`. Consider adding the two checks to the `SP1Verifier` constructor for consistency and robustness.
2.  **Redundant Zero-Address Check in `ForkRouter.sol`**: The [`_fallback`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/shared/fork-router/ForkRouter.sol#L53) function in `ForkRouter.sol` includes a runtime check `require(fork != address(0), ZeroForkAddress());`. However, the `fork` variable can only be assigned `oldFork` or `newFork`, both of which are immutable addresses set during contract construction. If the constructor ensures these immutables are non-zero, this runtime check becomes redundant. Consider moving the non-zero address validation for `oldFork` and `newFork` entirely to the `ForkRouter` constructor and removing the redundant runtime check in `_fallback`.
3.  **Suboptimal Array Copying in `LibBondInstruction.sol`**: The `_bulkCopyBondInstructions` function within `LibBondInstruction.sol` currently performs [memory copying](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibBondInstruction.sol#L149-L171) using a manual word-by-word assembly loop. The `mcopy` opcode offers a more efficient and gas-optimized approach for bulk memory operations. Consider refactoring `_bulkCopyBondInstructions` to utilize the `mcopy` opcode for improved gas efficiency and code clarity.
4.  **Redundant Length Encoding in `LibProveInputDecoder.sol`**: The `_calculateProveDataSize` function in `LibProveInputDecoder.sol` adds 4 bytes for [encoding array lengths](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibProveInputDecoder.sol#L184), specifically for `_proposals.length` and `_transitions.length`. Given that the `prove` function in `Inbox.sol` [enforces equality](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L304-L305) among `_proposals.length`, `_transitions.length`, and `_metadata.length`, encoding only one of these lengths would suffice, as the others can be inferred. Consider modifying the encoding scheme so that only one array length is stored, reducing encoded data size and corresponding gas costs.
5.  **Suboptimal Type Definition for Verifier Types in `ComposeVerifier.sol`**: The `ComposeVerifier.sol` contract [defines various verifier types](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/compose/ComposeVerifier.sol#L19-L25) using `uint8` constants (e.g., `SGX_GETH = 1`). While functional, Solidity enums provide a more type-safe and readable mechanism for representing a fixed set of discrete choices, preventing the use of arbitrary `uint8` values. Consider replacing the `uint8` constants with a Solidity `enum VerifierType` to improve type safety and code readability.
6.  **Inconsistent Bond Type Validation Across Decoding Libraries**: The `LibProvedEventEncoder` library [explicitly checks](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibProvedEventEncoder.sol#L107) for `InvalidBondType` during its decoding process. However, other related libraries, specifically [`LibProposeInputDecoder`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibProposeInputDecoder.sol#L248-L250) and [`LibProposedEventEncoder`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibProposedEventEncoder.sol#L154-L156), which also handle bond instruction data, lack this validation. This inconsistency can lead to scenarios where invalid bond types are processed without explicit error handling in some parts of the system. Consider ensuring consistent bond type validation across all relevant decoding and encoding libraries to maintain data integrity.

_**Update:** Resolved in [pull request #20995](https://github.com/taikoxyz/taiko-mono/pull/20995). Point 3 and 6 no longer apply since the code was removed._

### Gas Asymmetry and Low-Bond Path Enable Griefing of Previous Prover

There is a structural gas asymmetry between [proposing](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L232) and [proving](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L300): proving a proposal is significantly more expensive in gas than submitting it. This creates a griefing vector when combined with the way the designated prover is selected in low-bond situations.

Under normal circumstances, the proposer and prover are the same entity. When they are not the same, the prover must provide an explicit authentication, and the protocol enforces a fee to be paid by the proposer to the prover. This aligns incentives: if the proposer causes work for someone else, they pay for that work.

However, when the proposer is considered [“low bond”](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/docs/Derivation.md?plain=1#L184-L191) (for example, after being slashed below the minimum bond or after requesting a withdrawal), the flow changes:

*   The designated prover is automatically set to the [previous prover](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L302-L304) instead of the proposer or an authenticated third party.
*   No prover authentication is required in this case.
*   No prover fee is paid by the proposer, despite the prover still bearing the higher proving gas cost.

Because proving is substantially more expensive than proposing, a whitelisted but low-bond proposer can repeatedly submit cheap proposals that force the previous designated prover to incur high proving costs without compensation and without having opted in via authentication. This effectively results in a “forced labor” griefing scenario against the previous prover.

In the current trust model, proposers in the whitelist are assumed to be trusted operators, and an off-chain ejector service already exists to remove misbehaving or non-performing operators. To close the gap that enables this griefing pattern, the mitigation should ensure that an operator cannot remain whitelisted once they are no longer properly bonded:

*   As soon as a whitelisted proposer requests a withdrawal or their bond falls below the required minimum due to slashing, they should be ejected from the whitelist.
*   This can be enforced by extending the existing off-chain ejector/watchdog to monitor bond-related events and automatically remove such operators from the whitelist while their funds are still locked, so they cannot exploit the gas asymmetry in a low-bond state.

_**Update:** Acknowledged, will resolve. The team stated:_

> _The ejector software will be updated to make sure low bond operators are ejected promptly._
> 
> _While true that is is a burden for the previous prover, the cost of proving will be small(you just need to prove the proposer did not have enough bond on L2 and treat the whole proposal as an invalid proposal) and there’s no incentive for proposers to do this, since they miss out on L2 fees._

### Deposits After Withdrawal Keep Proposer in Permanent Low-Bond “Zombie” State

After calling [`requestWithdrawal()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/BondManager.sol#L130), a proposer who later deposits enough funds to cover the minimum bond remains permanently classified as low bond on L2 until they explicitly call `cancelWithdrawal()`. During this period, they can still be selected as proposer, but all of their proposals will be treated as low-bond and downgraded to the default manifest.

The `hasSufficientBond` check requires both a sufficient balance and `withdrawalRequestedAt == 0`

Once `requestWithdrawal()` is called, `withdrawalRequestedAt` becomes non-zero. The `deposit()` function only increases `balance` and does not reset `withdrawalRequestedAt`. As a result, the following sequence:

1.  Proposer calls `requestWithdrawal()` on L2.
2.  Later, proposer calls `deposit()` with enough funds to satisfy `minBond` (or more).

leads to a state where:

*   The account’s bond balance is sufficient (`balance >= minBond + _additionalBond`), but
*   `withdrawalRequestedAt != 0`, so
*   `hasSufficientBond(...) == false` forever, until `cancelWithdrawal()` is called.

On L2, any component that relies on `hasSufficientBond` to classify proposals (e.g., `Anchor`) will see this proposer as low bond even though they are fully funded. Concretely, when this proposer is selected and submits a block:

*   `Anchor` will flag the proposal as low-bond.
*   The block data will be discarded and replaced with a default, empty manifest.
*   The designated prover inherited from the parent block will receive 0 fee for proving it.

So the “zombie” nature of the state is:

*   The proposer can still be elected and propose blocks,
*   They keep paying gas to propose,
*   But all of their proposals are deterministically downgraded to default manifests until they explicitly call `cancelWithdrawal()`.

In practice, this can cause:

*   Honest proposers to assume they are correctly bonded and active, while the protocol treats all their proposals as low-bond.
*   Confusing UX, as there is no direct indication that a fresh deposit did not restore eligibility.
*   User transactions included in the original proposals are dropped when the block is downgraded to an empty manifest, increasing confirmation delay.

Although the primary impact is on honest users who misunderstand the state machine, the same behavior can be intentionally maintained by a malicious proposer to remain in a special “flagged” state that interacts poorly with the rest of the protocol.

A concrete fix would be to have `deposit()` automatically clear a pending withdrawal when the balance becomes sufficient again.

If automatic clearing is not desired, the system should at minimum surface this requirement clearly (e.g., client-side checks, warnings, or explicit status indicators) so that proposers cannot reasonably believe they are valid when they are not.

_**Update:** Resolved in [pull request #20997](https://github.com/taikoxyz/taiko-mono/pull/20997). The issue was documented in the interface. The team stated:_

> _Canceling withdrawal requests behind the scenes can cause more confusion, instead we propose clearly documenting this behavior. Please check this PR._

### Unused proposalAge Parameter with Bypassable Design

The [`IProofVerifier`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/IProofVerifier.sol#L10-L24) interface includes a `_proposalAge` parameter intended to enable age-based verification logic for detecting "prover-killer" proposals, maliciously crafted blocks that are difficult or impossible to prove. The [`prove` function](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L300-L321) calculates this value and passes it to the configured proof verifier.

Two issues exist with the current implementation: 1. None of the deployed verifiers utilize the `_proposalAge` parameter. It is explicitly ignored in [`SgxVerifier`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SgxVerifier.sol#L127), [`SP1Verifier`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SP1Verifier.sol#L49), and [`Risc0Verifier`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/Risc0Verifier.sol#L52). 2. The calculation logic contains a fundamental design flaw: `proposalAge` defaults to zero for batch proofs. This allows any prover to bypass age-based verification by bundling the target proposal with one or more additional proposals, rendering the mechanism ineffective if implemented in the future.

Consider either removing the unused parameter to reduce code complexity, or, if age-based verification remains a design goal, modifying the calculation to apply to all proposals in a batch.

Notes & Additional Information
------------------------------

### Incorrect Solidity Version for Custom Errors in Require Statements

Throughout the [codebase](https://github.com/taikoxyz/taiko-mono/tree/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts), contracts utilize custom errors within `require` statements for enhanced error handling. Concurrently, the specified Solidity compiler version across these contracts is `^0.8.24`. This approach aims to leverage more gas-efficient and descriptive error messages than traditional string-based errors. The functionality allowing custom errors directly within `require` statements was introduced in Solidity version `0.8.26`. The current pragma `^0.8.24` does not natively support this feature, which may result in compilation errors.

Consider updating the Solidity pragma version in all relevant contracts to `0.8.26` or a higher compatible version. This adjustment will ensure proper compilation and full support for the custom error syntax within `require` statements, thereby aligning the codebase with its intended language feature usage and mitigating potential build-time issues.

_**Update:** Resolved in [pull request #21000](https://github.com/taikoxyz/taiko-mono/pull/21000)._

### Ring Buffer Size of 1 Makes Inbox Permanently Unable to Accept Proposals

`Inbox` maintains proposals in a ring buffer, where available capacity is calculated as the ring buffer size minus one, minus the number of unfinalized proposals, via [`_getAvailableCapacity`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L1081-L1087). The [`Inbox` constructor](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L166-L179) currently only rejects `ringBufferSize == 0`.

When `ringBufferSize == 1`, the capacity calculation always returns zero, even when there are no unfinalized proposals. After `activate` seeds the genesis proposal, any call to `propose` will revert with [`NotEnoughCapacity()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L250-L252). As a result, an `Inbox` deployed with `ringBufferSize = 1` is permanently unable to accept new proposals, causing a liveness failure driven purely by a misconfiguration that is not currently prevented at construction time.

To avoid deploying unusable instances, the constructor should enforce `ringBufferSize >= 2`, consistent with the one-slot reservation assumed in the capacity formula.

_**Update:** Resolved in [pull request #21002](https://github.com/taikoxyz/taiko-mono/pull/21002). The team stated:_

> _Harden ring buffer size check to ensure size cannot be 1_

### Outdated and Unused Code in Verifier Contracts

Multiple instances of outdated code, unused parameters, and redundant contract implementations were identified in the verifier codebase.

1.  **`SgxVerifier.sol`**: The constant [`INSTANCE_VALIDITY_DELAY`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/SgxVerifier.sol#L32) is currently set to `0` and used in the `_addInstances` function logic. Since the delay is effectively disabled, this constant and the associated addition logic in `_addInstances` are unnecessary.
2.  **`ComposeVerifier.sol`**: The [immutable variables](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/compose/ComposeVerifier.sol#L32-L35) `sgxGethVerifier`, `tdxGethVerifier`, and `opVerifier` are declared but appear unused in the provided contexts or logic, adding unnecessary code bloat.
3.  **Redundant Compose Verifiers**: The system currently includes multiple composition strategies ([`AnyTwoVerifier.sol`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/compose/AnyTwoVerifier.sol#L1), [`SgxAndZkVerifier.sol`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/compose/SgxAndZkVerifier.sol#L1), [`AnyVerifier.sol`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/verifiers/compose/AnyVerifier.sol#L1)). Given the protocol's requirement for proofs to be verified by both SGX and ZK (where ZK offers stronger security guarantees), `AnyTwoVerifier` effectively covers the necessary combinations (e.g., SGX+RISC0, SGX+SP1) as well as ZK+ZK (RISC0+SP1). `SgxAndZkVerifier` is redundant as it is a subset of `AnyTwoVerifier`'s logic. `AnyVerifier` (single proof) contradicts the multi-proof security model.

Consider the following cleanups:

1.  Remove `INSTANCE_VALIDITY_DELAY` from `SgxVerifier.sol` and simplify `_addInstances` accordingly.
2.  Remove the unused immutable variables (`sgxGethVerifier`, `tdxGethVerifier`, `opVerifier`) from `ComposeVerifier.sol`.
3.  Deprecate or remove `SgxAndZkVerifier.sol` and `AnyVerifier.sol`, standardizing on `AnyTwoVerifier.sol` for composable proof verification.

### Clarity and Consistency in Naming Conventions

Several instances of confusing or inconsistent naming conventions were identified, which can hinder readability, maintainability, and understanding of the codebase. Adhering to clear and consistent naming standards is crucial for long-term project health.

1.  **Misleading Variable Name in `Inbox.sol`**: Within the `_dequeueAndProcessForcedInclusions` function, the variable [`oldestTimestamp_`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L892) is intended to capture a timestamp related to the processing of forced inclusions. However, its value is derived from `_sources[0].blobSlice.timestamp.max(_lastProcessedAt)`, which logically represents the latest or most recent timestamp processed, not the oldest. This discrepancy between the variable's name and its actual computed value can lead to misinterpretation of the code's behavior.
2.  **Inconsistent Library Naming for Codec Functions**: The project utilizes [libraries](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/) for handling encoding and decoding operations, such as `LibProposedEventEncoder`, `LibProposeInputDecoder`, `LibProvedEventEncoder`, and `LibProveInputDecoder`. While these libraries facilitate data serialization and deserialization, their names inconsistently use "Encoder" or "Decoder." Consider sticking to a unified naming pattern.
3.  **Ambiguous Mapping Names in `PreconfWhitelist.sol`**: The `PreconfWhitelist` contract employs [two mappings](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/impl/PreconfWhitelist.sol#L41-L42), `operators` and `operatorMapping`, to manage proposer information. The `operators` mapping links an `address` to an `OperatorInfo` struct, while `operatorMapping` links a `uint256` index to an `address`. The similarity in names, despite their distinct keys and value types, creates ambiguity and can make it difficult to ascertain their precise role without deeper code inspection. Consider naming them `proposerInfo` and `proposerAddressByIndex` for instance.

Consider addressing above instances to improve the code's clarity.

_**Update:** Partially Resolved in [pull request #20872](https://github.com/taikoxyz/taiko-mono/pull/20872). The team stated:_

> _1\. we removed lastProcessed at, so now `oldestTimestamp_ = uint48(_sources[0].blobSlice.timestamp);` so this should not be an issue anymore._
> 
> _2\. Libraries have been renamed to LibProposeInputCodec, LibProposedEventCodec, etc. to match the general Codec naming convention. This is clear for our team, and we think internal shared language is also important_
> 
> _3\. While we agree this is true, this contract has already been deployed to mainnet and the audited version will upgrade it. The two variables mentioned are public, so we already have off-chain software that depends on it, so we would prefer avoiding the risk of doing those changes and redeploying it_

### Redundant Code and Unused Components Identification

Several instances of redundant code and unused components were identified across the codebase, indicating opportunities for simplification and optimization.

1.  **Redundant `totalFees > 0` Check:** The `_dequeueAndProcessForcedInclusions` function includes an [explicit check](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L906) (`if (totalFees > 0)`) before calling `_feeRecipient.sendEtherAndVerify`. This check is redundant because the `sendEtherAndVerify` function itself [handles a zero amount](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/shared/libs/LibAddress.sol#L53) by returning without performing a transfer. Consider removing the `if (totalFees > 0)` check to streamline the control flow.
2.  **Unused `BLOB_BYTES` Constant:** The [`BLOB_BYTES`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibBlobs.sol#L11-L13) constant is defined in `LibBlobs.sol` as `BLOB_FIELD_ELEMENTS * FIELD_ELEMENT_BYTES` but is not referenced anywhere within the contract. Unused code contributes to cognitive overhead and can create confusion regarding its purpose. Consider removing the `BLOB_BYTES` constant to clean up the codebase.
3.  **Redundant Encoding/Decoding Logic:** Across the core libraries, there is duplicated code for encoding and decoding specific structs. For instance, there are two `_encodeProposal` functions \[[1](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibProposeInputDecoder.sol#L145), [2](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibProveInputDecoder.sol#L85)\], while other encode/decode functions handle structs [inline](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/libs/LibProposedEventEncoder.sol#L34-L66). This duplication leads to code bloat and inconsistencies. Consider consolidating common encoding and decoding functions into a shared, dedicated library (e.g., `LibCodec` or `LibTypes`) that can be imported and utilized uniformly across the protocol. This would centralize logic and improve consistency.
4.  **Redundant `BlockParams` Struct:** The [`BlockParams`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer2/core/Anchor.sol#L53) struct in `Anchor.sol` (`anchorBlockNumber`, `anchorBlockHash`, `anchorStateRoot`) duplicates the fields and purpose of the [`Checkpoint`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/shared/signal/ICheckpointStore.sol#L13) struct defined in `ICheckpointStore.sol`. This redundancy introduces unnecessary complexity and an additional struct definition for essentially the same data, particularly since `Anchor.sol` already interacts with `ICheckpointStore`. Consider replacing the `BlockParams` struct with `ICheckpointStore.Checkpoint` directly wherever `BlockParams` is used, reducing redundancy and improving type consistency.
5.  **Unused `LibSignals.sol` Library:** The [`LibSignals.sol`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/shared/signal/LibSignals.sol#L1) library, which defines constants like `SIGNAL_ROOT` and `STATE_ROOT`, appears to be entirely unused throughout the codebase. Similar to other unused code, its presence adds unnecessary overhead. Consider removing `LibSignals.sol` if it is not intended for future use, or integrate its functionality if it serves a specific, currently unfulfilled purpose.

Consider addressing the above instances to enhance code quality, reduce maintenance effort, and improve overall system clarity.

### Error Definitions Declared in Implementations Instead of Interfaces

The whole [codebase](https://github.com/taikoxyz/taiko-mono/tree/503445678a4bd875d761e56ba80a29a5b8e68d6e) defines custom errors directly in implementation contracts while leaving the corresponding interfaces without these declarations.

As a result, external integrators, off-chain services, and test suites cannot rely on interfaces alone to understand or decode the complete behavior of a contract, including its revert conditions. Callers that need to catch or decode specific custom errors must import implementation contracts, binding them to a particular implementation and defeating the abstraction boundary that interfaces are meant to provide. This pattern also increases the risk of inconsistencies between multiple implementations of the same interface (for example, in upgrade scenarios or alternative deployments), where different implementations might accidentally diverge in error naming, parameters, or selectors, even though they nominally implement the same interface.

Consider declaring all interface-wide errors on the interface contracts themselves and reusing those declarations from the implementations. This centralization would improve discoverability, reduce the likelihood of inconsistent error definitions across implementations, and simplify integration and review by allowing external users and auditors to rely primarily on the interface files for an accurate specification.

### Unused Errors

Leaving unused error definitions in the codebase can lead to confusion and decrease the overall readability and maintainability of the code. It may give the impression of incomplete implementation or suggest that certain error checks were intended but not properly executed. Throughout the codebase, multiple instances of unused errors were identified, such as:

*   [`NoBondToWithdraw()`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/core/impl/Inbox.sol#L1147) on `inbox.sol`
*   `InvalidCoreState()` on [`MainnetInbox`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/mainnet/MainnetInbox.sol#L77) and [`DevnetInbox`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/devnet/DevnetInbox.sol#L78)
*   [`InvalidOperatorCount`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/impl/PreconfWhitelist.sol#L291) on `PreconfWhitelist`
*   [`OperatorAlreadyRemoved`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/impl/PreconfWhitelist.sol#L294) on `PreconfWhitelist`
*   [`OperatorNotAvailableYet`](https://github.com/taikoxyz/taiko-mono/blob/503445678a4bd875d761e56ba80a29a5b8e68d6e/packages/protocol/contracts/layer1/preconf/impl/PreconfWhitelist.sol#L295) on `PreconfWhitelist`

To enhance the clarity and efficiency of the code, consider finding and removing all unused errors from the codebase.

Conclusion
----------

We audited the Shasta protocol version of the Taiko Based Rollup throughout a 4 weeks engagement. The code currently exposes several high-impact correctness and liveness risks. Critical findings include multiple ways to permanently halt or misroute finalization, a denial-of-service risk from unsafe ABI decoding in `Anchor`, and the lack of cryptographic binding between proofs and trusted guest program IDs. High-severity issues include risks of unfinalizable proposals due to a span overflow and the lack of conflicting proves handling.

The Taiko team has been very helpful and responsive throughout the engagement. However, the concentration of high severity issues means remediation should be followed by a fresh re-audit once code changes are in place.

Appendix
--------

### Issue Classification

OpenZeppelin classifies smart contract vulnerabilities on a 5-level scale:

*   Critical
*   High
*   Medium
*   Low
*   Note/Information

#### **Critical Severity**

This classification is applied when the issue’s impact is catastrophic, threatening extensive damage to the client's reputation and/or causing severe financial loss to the client or users. The likelihood of exploitation can be high, warranting a swift response. Critical issues typically involve significant risks such as the permanent loss or locking of a large volume of users' sensitive assets or the failure of core system functionalities without viable mitigations. These issues demand immediate attention due to their potential to compromise system integrity or user trust significantly.

#### **High Severity**

These issues are characterized by the potential to substantially impact the client’s reputation and/or result in considerable financial losses. The likelihood of exploitation is significant, warranting a swift response. Such issues might include temporary loss or locking of a significant number of users' sensitive assets or disruptions to critical system functionalities, albeit with potential, yet limited, mitigations available. The emphasis is on the significant but not always catastrophic effects on system operation or asset security, necessitating prompt and effective remediation.

#### **Medium Severity**

Issues classified as being of medium severity can lead to a noticeable negative impact on the client's reputation and/or moderate financial losses. Such issues, if left unattended, have a moderate likelihood of being exploited or may cause unwanted side effects in the system. These issues are typically confined to a smaller subset of users' sensitive assets or might involve deviations from the specified system design that, while not directly financial in nature, compromise system integrity or user experience. The focus here is on issues that pose a real but contained risk, warranting timely attention to prevent escalation.

#### **Low Severity**

Low-severity issues are those that have a low impact on the client's operations and/or reputation. These issues may represent minor risks or inefficiencies to the client's specific business model. They are identified as areas for improvement that, while not urgent, could enhance the security and quality of the codebase if addressed.

#### **Notes & Additional Information Severity**

This category is reserved for issues that, despite having a minimal impact, are still important to resolve. Addressing these issues contributes to the overall security posture and code quality improvement but does not require immediate action. It reflects a commitment to maintaining high standards and continuous improvement, even in areas that do not pose immediate risks.