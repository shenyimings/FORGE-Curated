\- October 16, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary

**Type:** Layer 2 & Rollups  
**Timeline:** September 10, 2025 → September 22, 2025  
**Languages:** Solidity

**Findings**  
Total issues: 43 (43 resolved)  
Critical: 0 (0 resolved) · High: 2 (2 resolved) · Medium: 7 (7 resolved) · Low: 11 (11 resolved)

**Notes & Additional Information**  
23 notes raised (23 resolved)

Scope
-----

OpenZeppelin audited the [jovaynetwork/jovay-contracts](https://github.com/jovaynetwork/jovay-contracts) repository at commit [24f525f](https://github.com/jovaynetwork/jovay-contracts/tree/24f525f379558eed27441f7233e5921591e0063d) of the audit/mainnet/dev branch.

Following the conclusion of the fix review, the final post-audit commit is [bdaf093](https://github.com/jovaynetwork/jovay-contracts/commit/bdaf093ad7061824cba02021da76a25217355451).

In scope were the following files:

`rollup_contracts
└── contracts
    ├── L1
    │   ├── bridge
    │   │   ├── L1BridgeProof.sol
    │   │   ├── L1ERC20Bridge.sol
    │   │   ├── L1ETHBridge.sol
    │   │   └── interfaces
    │   │       ├── IL1BridgeProof.sol
    │   │       ├── IL1ERC20Bridge.sol
    │   │       └── IL1ETHBridge.sol
    │   ├── core
    │   │   ├── L1Mailbox.sol
    │   │   └── Rollup.sol
    │   ├── interfaces
    │   │   ├── IL1MailQueue.sol
    │   │   ├── IL1Mailbox.sol
    │   │   └── IRollup.sol
    │   └── libraries
    │       ├── codec
    │       │   └── BatchHeaderCodec.sol
    │       └── verifier
    │           ├── ITeeRollupVerifier.sol
    │           ├── IZkRollupVerifier.sol
    │           └── WithdrawTrieVerifier.sol
    │
    ├── L2
    │   ├── bridge
    │   │   ├── L2ERC20Bridge.sol
    │   │   ├── L2ETHBridge.sol
    │   │   └── interfaces
    │   │       ├── IL2ERC20Bridge.sol
    │   │       └── IL2ETHBridge.sol
    │   ├── core
    │   │   ├── L1GasOracle.sol
    │   │   ├── L2CoinBase.sol
    │   │   └── L2Mailbox.sol
    │   ├── interfaces
    │   │   ├── IClaimAmount.sol
    │   │   ├── IL2MailQueue.sol
    │   │   └── IL2Mailbox.sol
    │   └── libraries
    │       └── common
    │           └── AppendOnlyMerkleTree.sol
    │
    └── common
        ├── BridgeBase.sol
        ├── ERC20Token.sol
        ├── MailBoxBase.sol
        ├── TokenBridge.sol
        └── interfaces
            ├── IBridgeBase.sol
            ├── IERC20Token.sol
            ├── IGasPriceOracle.sol
            ├── IMailBoxBase.sol
            └── ITokenBridge.sol` 

System Overview
---------------

The Jovay Network is a rollup built with data availability and finality checkpoints on Ethereum. The core L1 component is the `Rollup` contract, which accepts batch commitments, verifies them against a supported proof system, and records the resulting state roots and message roots. Data availability for each batch is committed on L1 via blobs, following the [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) specification, and batch linkage is enforced through parent and rolling-hash fields.

Cross-domain messaging is provided by the `L1Mailbox` and `L2Mailbox` contracts. The L1 mailbox accumulates L1→L2 messages in a queue, while the L2 mailbox maintains an append-only historic Merkle tree of L2→L1 messages whose root is posted back to L1 during verification. After a batch is verified, messages can be executed on the destination chain with standard inclusion proofs. On L2, message execution is performed by a designated relayer.

Asset movement relies on paired ETH and ERC-20 bridges on L1 and L2. Deposits originate on L1 and are finalized on L2 once the corresponding message is relayed. Withdrawals originate on L2, are committed into the L2 message root, and are finalized on L1 after inclusion is proven. Token mappings are maintained symmetrically across layers to ensure consistent asset representation.

The current verification mode supports TEE proofs. Zero-Knowledge (ZK) verification hooks exist in the codebase but are not active. Governance and operational controls follow standard patterns: contracts are upgradeable and pausable, relayers are allowlisted, and administrative parameters can be updated by the owner to adapt the system while preserving the batch-commit, verify, and finalize lifecycle.

Security Model and Trust Assumptions
------------------------------------

The system depends on trusted relayers and privileged contract owners to facilitate message passing and parameter management between L1 and L2. Correct operation requires these actors to behave honestly and reliably.

**L1 → L2 Messages**: No additional on-chain verification is performed. The relayer is solely responsible for honestly delivering the data. **L2 → L1 Messages**: Messages (submitted as batches of transactions) are verified on-chain. In the current version of the bridge, only TEE proofs are supported. For the purposes of this audit, it is assumed that TEE proof verification functions correctly.

In addition to ETH, the bridge supports ERC-20 token deposits. For the bridge to operate correctly, these must be standard ERC-20 tokens. The following are not supported and may cause reverts or unsafe behavior:

*   Tokens with fee-on-transfer mechanisms
*   Tokens with nonstandard transfer or pre-transfer hooks
*   Rebasing tokens

This audit was performed under the assumption that only standard ERC-20 tokens are used.

### Privileged Roles

The specific responsibilities and assumptions for each role are as follows:

*   **L1 and L2 Bridge Contract Owners**
    
    *   Responsible for setting and updating the mailbox address and the corresponding bridge contract address on the opposite chain.
    *   Expected not to pause the contracts arbitrarily, since when the contracts are paused, user funds cannot be withdrawn.
*   **ERC-20 Bridge Contract Owner**
    
    *   Responsible for setting the mirror token address on the opposite chain.
    *   It is assumed that token–mirror token pairs are correctly configured on both sides and remain consistent.
*   **`L1Mailbox` Owner**
    
    *   Can pause/unpause the `L1Mailbox` contract.
    *   Manages connected bridges and the `Rollup` contract address, ensuring only valid contracts with the expected behavior are registered.
    *   Sets and updates parameters such as `gasLimit` (which determines user deposit fees), withdrawer addresses (which can withdraw fees from the contract), and the `baseFee` used for computing user fees.
    *   Can update the `latestQueueIndex`, which determines the latest L2→L1 message in the queue. This must only be modified during mailbox upgrades.
*   **`L2Mailbox` Owner**
    
    *   Can pause/unpause the `L2Mailbox` contract.
    *   Responsible for configuring bridge addresses and setting the base fee.
*   **`Rollup` Owner**
    
    *   Sets the mailbox contract addresses that interact with the `Rollup` contract, as well as proof verifier addresses.
    *   Configures key parameters of the `Rollup` contract.
    *   Responsible for importing the genesis batch of L2 transactions and the initial state root. Incorrect setup could prevent the bridge from functioning.
*   **`L1GasOracle` Owner**
    
    *   Configures gas-related parameters on the L1 side.
    *   Honest updates are required to ensure correct gas pricing.
*   **`L2Coinbase` Owner**
    
    *   Receives fees on the L2 side of the bridge.
    *   Can set the withdrawer addresses that are authorized to withdraw these fees.
*   **Relayers**
    
    *   Relayers are external actors critical for liveness and cross-chain correctness. Their responsibilities include:
    *   Reading every `SentMsg` event from the `L1Mailbox` (representing deposits) and relaying the exact same data to the `L2Mailbox` by calling `relayMsg`.
    *   Submitting valid batches of L2 transactions to the `Rollup` contract on the L1 side.
    *   Providing validity proofs for previously submitted batches.
    *   Updating the L1 Gas Oracle with accurate data about L1 gas prices.
    *   System liveness depends on their correct behavior: if the relayers stop relaying, deposits and withdrawals cannot be finalized, effectively freezing the bridge. If they submit invalid batches, verification fails and the bridge remains halted until the `Rollup` owner reverts the faulty batches.

High Severity
-------------

### Incorrect Use of ERC-20 `amount_` As ETH Value in L2 ERC-20 Bridge `withdraw`

The [`L2ERC20Bridge`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L10-L76) contract is responsible for handling deposits (L1 → L2) and withdrawals (L2 → L1) of ERC-20 tokens. When a user withdraws tokens, the bridge burns the specified token amount on L2 and then [sends](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L47) a cross-domain message to the L1 bridge via the `L2Mailbox` contract. This is achieved by calling the mailbox’s standard [`sendMsg` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L43-L75), which takes several parameters: the destination (`toBridge`), the ETH value to forward with the message (`value`), the encoded message data, the gas limit, and the sender's address. The `value` parameter here is intended to specify the **amount of ETH** (if any) that should accompany the message.

However, in the current implementation, the `withdraw` function [mistakenly](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L47) uses the ERC-20 token amount (`amount_`) as the `value` argument to the `sendMsg` function. This is incorrect because `amount_` refers to the quantity of ERC-20 tokens being withdrawn, not ETH. For ERC-20 withdrawals, the ETH value should always be 0, since no ETH needs to be transferred with the message. If left uncorrected, this error can cause the mailbox to interpret the ERC-20 token amount as ETH, leading to inconsistent cross-domain accounting or potential ETH transfer attempts where no ETH was intended. This may result in loss of funds for the user or unexpected message execution failures on the L1 bridge side.

Consider updating the `withdraw` function so that the `value` passed to `IMailBoxBase.sendMsg` is 0 when withdrawing ERC-20 tokens. In addition, consider ensuring that only ETH withdrawals set a non-zero value.

_**Update:** Resolved in [pull request #18](https://github.com/jovaynetwork/jovay-contracts/pull/18)._

### Broken Set Token Mapping Flow

When an ERC-20 token is deposited in the `L1ERC20Bridge` contract, the contract checks whether the "mirror token" (its L2 counterpart)[has been set](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L32-L33). If so, the original tokens are transferred to the bridge contract and a message is emitted for relaying to the L2 side, where the corresponding amount of the mirror token is minted for the user. For this mechanism to work correctly, both sides of the bridge should maintain identical mappings between L1 tokens and their corresponding L2 counterparts.

On the L1 side, the bridge owner calls [`setTokenMapping`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L21-L29), which stores a `setTokenMapping` message in the mailbox that is intended for the L2 side. Relayers are then expected to pass this message to the `L2Mailbox` contract, which subsequently calls the [`setTokenMapping`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L16-L18) of the `L2ERC20Bridge` contract. However, the `setTokenMapping` function in `L2ERC20Bridge` is currently only callable by the owner of the contract. The owner cannot be the mailbox contract, because in that case, it would be impossible to call some crucial functions (e.g., the [`pause` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/BridgeBase.sol#L52-L54)). As a result, the token mapping update fails on L2, leaving the two sides out of sync. Without consistent mappings, ERC-20 bridging is not possible.

Consider also allowing the `L2Mailbox` contract to call the `L2ERC20Bridge.setTokenMapping` function, ensuring that token mappings are properly propagated across both sides of the bridge.

_**Update:** Resolved in [pull request #24](https://github.com/jovaynetwork/jovay-contracts/pull/24)._

Medium Severity
---------------

### Inconsistent Handling of `l2MsgRoot` Across Proofs

The [`verifyBatch`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L187-L230) function of the `Rollup` contract allows relayers to perform an on-chain verification of a batch of L2 transactions that has been previously committed. To do so, the relayer provides the batch header, the state root after the batch, and the `l2MsgRoot`. In the current implementation, only one proof type is supported (TEE proofs). However, the system is designed to also support ZK proofs in the future, and a batch will only be considered verified once both proofs have been submitted and validated.

The contract [enforces](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L206) the consistency of the `_postStateRoot` across proofs by checking that `finalizedStateRoots[_batchIndex]` is either zero (for the first submitted proof) or equal to the value from the first proof (for the second proof). However, no such check is performed for the `l2MsgRoot`. As a result, the second submitted proof can overwrite it.

While it is true that if both proofs are valid, they should inherently agree on the `l2MsgRoot` since identical state roots imply identical included messages, but relying on this assumption weakens the intended security model. The rationale for requiring two distinct proofs is to increase robustness against bugs in a single proof system or verifier. If such a bug were to exist, it could allow both proofs to pass verification while producing different `l2MsgRoot` values. In that case, the two proofs would not actually be attesting the same messages, yet the system would fail to detect the inconsistency and would incorrectly accept the second value as accurate.

Consider explicitly checking that both proofs agree not only on the `postStateRoot` but also on the `l2MsgRoot` to strengthen the security guarantees.

_**Update:** Resolved in [pull request #24](https://github.com/jovaynetwork/jovay-contracts/pull/24)._

### Unclear L1 Message Queue Logic

The L1 message queue in the `L1Mailbox` contract is difficult to reason about due to commented-out code paths and inconsistent state handling. The owner-settable [`setLastQueueIndex`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L220-L222) exists but is not coherently integrated with the rest of the queue flow. Meanwhile, [`getMsg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L204-L215) appears to assume that old entries are popped, yet `popFront()` is [commented out](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L242) in `popMsgs`, so entries are never actually removed. In particular, this results in `stableRollingHash` never being updated. This can cause `getMsg` to return rolling hashes that do not match the true queue state (especially after manual updates to `lastestQueueIndex` or in the special case that it returns [`stableRollingHash`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L211-L212), that is always outdated), creating ambiguity in how finalized L1 messages are tracked and risking downstream batch-commit inconsistencies.

Consider clearly documenting the intended queue lifecycle and enforcing it in the code. If messages are meant to be removed, reinstate popping in `popMsgs` and keep indices in sync. Otherwise, refactor `getMsg` to avoid relying on `lastestQueueIndex`. In addition, remove dead code or owner-only escape hatches that can desynchronize state.

_**Update:** Resolved in [pull request #34](https://github.com/jovaynetwork/jovay-contracts/pull/34). The Jovay team stated:_

> _We need to provide further clarification on this matter, as the scenarios for mainnet and testnet are distinct._
> 
> _**Testnet Scenario (Upgrade Path)**: A previous version of the contract is already deployed on the testnet. In this version, elements from `msgQueue` are actually removed, and the `setLastQueueIndex` function does not exist. Due to the performance impact of deleting elements from `msgQueue`, we decided to modify the logic to no longer delete them. This change must be implemented via an upgrade. Consequently, we introduced the `setLastQueueIndex` function._
> 
> _During the upgrade, the `setLastQueueIndex` function will be called once, using `lastestQueueIndex` to track the index of the next message to be finalized. It is important to note that the queue is expected to be empty before this call is made. Following the upgrade, the logic of the `getMsg` function is also updated to calculate the index of the element to read from `msgQueue` based on `lastestQueueIndex`. We will elaborate on this process further in the upgrade documentation to prevent any ambiguity._
> 
> _**Mainnet Scenario (Fresh Deployment)**: In contrast, the contract has not yet been deployed on mainnet. For the mainnet deployment, elements in `msgQueue` will never be deleted, and `the setLastQueueIndex` function will not be called. As a result, `lastestQueueIndex` will remain 0. Fetching data via the current `getMsg` function appears to work correctly under this clean-state condition._

### Missing Manual Finalization Mechanism for ERC-20 Tokens Can Lead to Locked Funds

Relayers are responsible for bridging messages between L1 and L2. On the L2 side, they submit messages to the `L2Mailbox` contract by calling the [`relayMsg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L85-L108) function and providing the message details. This message can be a `finalizeDeposit` call for ETH or ERC-20 tokens, or a `setTokenMapping` invocation.

The `relayMsg` function [stores the hash of the message in `receiveMsgMap`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L98) to prevent double submissions and then attempts to execute the action described in the message using [a low-level call](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L99). If the low-level call fails, the transaction does not revert. This design allows ETH deposits to be finalized manually by the user, since the user can later finalize the transaction by calling [`claimDeposit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L53-L60).

In contrast, for `setTokenMapping` and `finalizeDeposit` for ERC-20 tokens, there does not exist a similar mechanism that would allow users to manually finalize the execution if the low-level call fails. Since the message hash is already stored in `receiveMsgMap`, the relayer cannot resubmit the message. In the case of `setTokenMapping`, the owner on the L1 side can resubmit the transaction that will create a new message that the relayer will transfer on the L2 side. However, the ERC-20 token deposit will remain incomplete, and deposited tokens will remain locked in the `L1Mailbox` contract without any tokens being delivered to the user on L2.

Consider adding a manual finalization function for ERC-20 deposits and `setTokenMapping`, similar to the `claimDeposit` function for ETH.

_**Update:** Resolved in [pull request #42](https://github.com/jovaynetwork/jovay-contracts/pull/42). The Jovay team stated:_

> _We have added failure-handling logic for ERC-20 token transfers. For the `setTokenMapping` function, we think an in-contract failure-handling mechanism is unnecessary. If a transaction fails, the expected behavior is for the relayer to simply retry it._

### Mutable `layer2ChainId` Can Break Batch Verification and Cause DoS

The `layer2ChainId` variable is initialized in [`initialize`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L104) and can later be updated via [`setL2ChainId`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L361). Batches are committed through [`commitBatch`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L151-L184), which records their hash in [`committedBatches`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L50). Later, verification occurs in [`verifyBatch`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L187-L218), where `layer2ChainId` is passed to [`_verifyTeeProof`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L291-L297) as part of the commitment input. If `layer2ChainId` is updated after batches are committed but before they are verified, proof commitments will no longer match. Since verification requires sequential order (`_batchIndex == _verifiedBatchIndex + 1`), this mismatch halts progress entirely, introducing a DoS risk.

Consider binding the chain ID to each batch at commit time and referencing that stored value during verification. Alternatively, consider restricting `setL2ChainId` to only be callable when there are no pending unverified batches.

_**Update:** Resolved in [pull request #17](https://github.com/jovaynetwork/jovay-contracts/pull/17)._

### Zero-Amount Withdraw Allows Spam Messaging

The [`withdraw`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L21-L31) function of the `L2ETHbridge` contract [enforces that `msg.value` is non-zero](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L22), but it does not verify that the `amount_` argument, which determines the actual withdrawal amount, is also greater than 0. This allows a malicious user to call `withdraw` with a minimal non-zero `msg.value` while setting `amount_` and `gasLimit_` to zero. In such a call, the mailbox still emits a `finalizeWithdraw` message, and at the end of the execution, the attacker is [refunded the full `msg.value`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L68-L74). The relayer must then include this message in a batch and subsequently submit and verify it on L1.

As a result, anyone with a small amount of native tokens on the L2 side can spam the system with a large number of zero-amount withdrawal messages, only paying the local L2 gas cost. This could result in a DoS condition, as the relayer would have to submit batches filled with spam withdrawal requests, making it significantly harder for legitimate withdrawals to be processed.

In the [`withdraw`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L21-L31) function, consider enforcing that the `amount_` argument is also non-zero. In addition, consider requiring a minimum non-refundable gas fee to discourage spamming with economically worthless withdrawals.

_**Update:** Resolved in [pull request #15](https://github.com/jovaynetwork/jovay-contracts/pull/15). The Jovay team stated:_

> _Implementing a minimum withdrawal limit would require us to also add a minimum deposit limit to prevent users from getting their funds stuck. Therefore, we have adjusted our fix for M-04 to only ensure that `amount_` is greater than 0._

### Missing Gas Bounds and Fee Accounting in `L2Mailbox`

When a user calls the [`withdraw`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L21) function on the L2 side of the bridge, they must also specify the `gasLimit`. In the [`sendMsg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L43-L75) function of the `L2Mailbox` contract, this parameter is used to compute the fee the user pays, which serves as a compensation for the relayers to cover the gas costs of bridging messages. Unlike the [`L1Mailbox` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L105-L106), the `L2Mailbox` contract does not enforce any bounds on the `gasLimit`.

If the `gasLimit` is set to zero, the user avoids paying any fee while still creating valid withdrawal messages that relayers must later submit and verify on L1. An attacker could therefore spam the system at negligible cost, forcing relayers to process withdrawals without being compensated for them. Although relayers do not need to relay each individual transaction on L1 but only batches of transactions, which reduces the gas cost per transaction, the introduction of ZK proofs in the future, whose on-chain verification is not cheap, could make this problem significant.

Moreover, the issue becomes worse because users are allowed to include in a withdrawal a `msg_` argument of type `bytes` and arbitrary length, which can increase significant the size of the blob. However, the fee estimation logic in `L2Mailbox` does not account for the length of the submitted data. The same issue also exists in `L1Mailbox`, in the case of deposits. In addition, the `L2Mailbox` contract does not include any mechanism to account for the total fees collected, such as the [`feeBalance`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L126) variable in `L1Mailbox`, nor does it provide a withdrawal function for these fees. This results in untracked funds within the contract and no way for designated addresses to collect them.

Consider introducing bounds for the `gasLimit` in the `L2Mailbox` contract, making fees proportional to the length of the provided data and adding proper fee accounting along with a withdrawal function that is only callable by authorized addresses to ensure fair fee handling.

_**Update:** Resolved in [pull request #16](https://github.com/jovaynetwork/jovay-contracts/pull/16). The Jovay team stated:_

> _We need to clarify that the fees for a transaction initiated on L2—including the transaction fee and the cost of verification on L1—are all encompassed within the L2 transaction fee. Therefore, by design, the `L2Mailbox` contract itself does not handle any fees, and consequently, there is no need to implement fee-handling logic within it. To prevent fees on L2, we are simply setting `baseFee` in the `L2Mailbox` contract to zero. As a result, even when a user passes a `gasLimit_` for a withdrawal, the calculated fee is nullified and effectively returned to users._

### Gas Handling Inconsistencies in Bridge Message Execution

In `finalizeDeposit`, [the implementation forwards](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L45) `gasleft() / 2` to the recipient. However, this approach is arbitrary and may leave too little gas for the callee. A safer and clearer pattern is to reserve a fixed, audited budget for post-call bookkeeping and forwarding the rest.

Consider replacing the `gasleft() / 2` approach with a fixed, well-audited reserve pattern, forwarding the remainder to the target.

_**Update:** Resolved in [pull request #35](https://github.com/jovaynetwork/jovay-contracts/pull/35)._

Low Severity
------------

### Redundant `ADMIN_ROLE` Definition Instead of Using `DEFAULT_ADMIN_ROLE`

The `ERC20Token` contract [introduces](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L34-L38) a custom `ADMIN_ROLE` and sets it as the admin for all roles. However, OpenZeppelin’s `AccessControl` already provides `DEFAULT_ADMIN_ROLE` with the same purpose. Defining a parallel `ADMIN_ROLE` creates ambiguity and increases the risk of errors, especially since `DEFAULT_ADMIN_ROLE` remains unassigned. By default, any new role in OpenZeppelin contracts has `DEFAULT_ADMIN_ROLE` as its admin, meaning those roles cannot be granted unless `DEFAULT_ADMIN_ROLE` is also held. This setup can lead to inconsistent privilege management and potential loss of control if new roles are introduced. Furthermore, explicitly redefining role admins is gas-inefficient.

Consider using the built-in `DEFAULT_ADMIN_ROLE` instead of introducing a custom `ADMIN_ROLE` to reduce the risk of errors and optimize gas consumption.

_**Update:** Resolved in [pull request #21](https://github.com/jovaynetwork/jovay-contracts/pull/21/files)._

### Unsafe ETH and Token Handling in the Bridge Contracts

The proper way to deposit ETH for bridging is by calling the [`deposit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol#L16-L27) function of the `L1ETHBridge` contract. This function calls [`L1Mailbox.sendMsg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L92-L127), which transfers the deposited ETH to the `L1Mailbox` contract, where it remains locked until it is used to cover future withdrawals from L2 back to L1. However, the `L1Mailbox` contract inherits a [`receive()`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L96) function from the `MailboxBase` contract, allowing users to send ETH directly to it. This behavior is error-prone and there are many incidents on other protocols where users without a proper understanding of the bridge logic, sent ETH directly to the contract, resulting in permanently lock funds. Similar issues exist in the ERC-20 version of the bridge.

On the L2 side, users may also send native tokens directly to the `L2Mailbox` contract instead of calling the [`withdraw`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L21-L31) function. While the `receive()` function cannot be removed entirely (since it is required for receiving freshly minted local ETH after deposits on the L1 side), it still creates confusion and risk for the users. In addition, the [`relayMsgWithProof`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1BridgeProof.sol#L8-L15) functions of `L1Bridge` and `L1Mailbox` are marked as `payable`, even though there is no need for the users to send ETH when calling them. The ETH required for withdrawal is already held within the `L1Mailbox` contract. As such, declaring these functions `payable` increases the risk of accidental ETH transfers that serve no purpose.

Consider removing the `receive()` function from the `L1Mailbox` or overriding it with explicit intended functionality, only declaring as `payable` functions that truly require ETH transfers, making the mechanism for sending newly minted local ETH to the `L2Mailbox` more explicit and, in the ERC-20 version of the bridge, allowing recovery of tokens sent directly to the contract.

_**Update:** Resolved in [pull request #20](https://github.com/jovaynetwork/jovay-contracts/pull/20) and [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Unsafe Token Mapping Updates Can Break Bridging

The bridge owner uses the [`setTokenMapping`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L21-L29) function to define which ERC-20 tokens are permitted for deposits on the L1 side of the bridge and their corresponding tokens on L2. The bridge will only function correctly if both sides maintain identical mappings at all times.

However, the `setTokenMapping` function can also be used to change the corresponding L2 token for an L1 token. This flexibility introduces a risk. If a deposit is initiated before a mapping update, but the relayer submits the message only after the update has been applied on both sides, the `finalizeDeposit` function will [validate against the new mapping](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L65-L66) instead of the original one. In such a scenario, the deposit cannot be finalized, leaving the bridging process stuck.

Consider either not allowing the `setTokenMapping` function to update existing token's counterpart or, if updates are required, designing a careful and explicit procedure for updates, such as pausing both sides of the bridge before applying any change.

_**Update:** Resolved in [pull request #20](https://github.com/jovaynetwork/jovay-contracts/pull/20). The Jovay team stated:_

> _The `relayMsg` mechanism on L2 ensures that L1 messages are executed on L2 in nonce order without causing disorder. So, this problem will not occur._

### Invalid Gas Limit Configuration Can Disable Deposits

In the `sendMsg` function of the `L1Mailbox` contract, the user-provided `gasLimit_` is required to be strictly less than the [`l2GasLimit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L105) and greater than or equal to [`l2FinalizeDepositGasUsed`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L106C30-L106C54). During [initialization](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L70-L71), as well as in the [`setL2GasLimit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L173-L180) and [`setL2FinalizeDepositGasUsed`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L185C14-L192) owner-only callable functions, the contract only checks that `l2GasLimit` is not strictly less than `l2FinalizeDepositGasUsed`. This means that it is acceptable for the owner to set these two values as equal. If such a configuration occurs, there will be no valid `gasLimit_` values that satisfy the conditions in `sendMsg`, which would effectively block all deposits from being executed.

Consider tightening the logic in the setter functions by enforcing that `l2GasLimit` is strictly greater than `l2FinalizeDepositGasUsed`.

_**Update:** Resolved in [pull request #36](https://github.com/jovaynetwork/jovay-contracts/pull/36)._

### Inconsistent Event Structures Between `L1Mailbox` and `L2Mailbox`

The `sendMsg` functions in both `L1Mailbox` and `L2Mailbox` are similar in logic and each emits a `SentMsg` event. However, the event arguments are not aligned between the two contracts. In the `L1Mailbox` contract, the fifth argument is [`data`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L116), whereas in the `L2Mailbox` contract, it is just [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L65). Similarly, the first argument in [`AppendMsg`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L230) emitted by `L1Mailbox` represents the next index, while in the [`L2Mailbox`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L130) contract, it represents the actual index where the message was appended. This inconsistency may cause confusion for users and protocols that integrate with the bridge contracts and will also complicate the relayers' job, as it requires different decoding logic for similar events.

Consider aligning the structure and semantics of events emitted by the two mailbox contracts to ensure consistency.

_**Update:** Resolved. The Jovay team stated:_

> _The messages on both sides serve different purposes: L1 requires data to serve as transaction information sent to L2, while the messages in the L2 mailbox are solely for message processing._

### Missing Upper Bound Check in `initialize` for `lastBatchByteLength`

The `L1GasOracle` contract relies on the relayer-provided `lastBatchByteLength` value to compute the L1 gas per byte. While both upper and lower bounds are enforced in [`setNewBatchBlobFeeAndTxFee`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L100C14-L121), the [`initialize`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) function only enforces the lower bound.

Consider adding an upper-bound check in `initialize`.

_**Update:** Resolved in [pull request #37](https://github.com/jovaynetwork/jovay-contracts/pull/37)._

### Floating Pragma

Pragma directives should be fixed to clearly identify the Solidity version with which the contracts will be compiled.

Throughout the codebase, multiple instances of floating pragma directives were identified:

*   `L1BridgeProof.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1BridgeProof.sol#L2)floating pragma directive.
*   `L1ERC20Bridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L2) floating pragma directive.
*   `L1ETHBridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol#L2) floating pragma directive.
*   `IL1BridgeProof.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/interfaces/IL1BridgeProof.sol#L2) floating pragma directive.
*   `IL1ERC20Bridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/interfaces/IL1ERC20Bridge.sol#L2) floating pragma directive.
*   `IL1ETHBridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/interfaces/IL1ETHBridge.sol#L2) floating pragma directive.
*   `L1Mailbox.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L2) floating pragma directive.
*   `Rollup.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L2) floating pragma directive.
*   `IL1MailQueue.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/interfaces/IL1MailQueue.sol#L2) floating pragma directive.
*   `IL1Mailbox.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/interfaces/IL1Mailbox.sol#L2) floating pragma directive.
*   `IRollup.sol` has the [`solidity ^0.8.16`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/interfaces/IRollup.sol#L3) floating pragma directive.
*   `BatchHeaderCodec.sol` has the [`solidity ^0.8.16`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/libraries/codec/BatchHeaderCodec.sol#L3) floating pragma directive.
*   `ITeeRollupVerifier.sol` has the [`solidity ^0.8.24`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/libraries/verifier/ITeeRollupVerifier.sol#L3) floating pragma directive.
*   `IZkRollupVerifier.sol` has the [`solidity ^0.8.24`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/libraries/verifier/IZkRollupVerifier.sol#L3) floating pragma directive.
*   `WithdrawTrieVerifier.sol` has the [`solidity ^0.8.24`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/libraries/verifier/WithdrawTrieVerifier.sol#L3) floating pragma directive.
*   `L2ERC20Bridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L2) floating pragma directive.
*   `L2ETHBridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L2) floating pragma directive.
*   `IL2ERC20Bridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/interfaces/IL2ERC20Bridge.sol#L2) floating pragma directive.
*   `IL2ETHBridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/interfaces/IL2ETHBridge.sol#L2) floating pragma directive.
*   `L1GasOracle.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L2) floating pragma directive.
*   `L2CoinBase.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L2) floating pragma directive.
*   `L2Mailbox.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L2) floating pragma directive.
*   `IClaimAmount.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/interfaces/IClaimAmount.sol#L2) floating pragma directive.
*   `IL2MailQueue.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/interfaces/IL2MailQueue.sol#L2) floating pragma directive.
*   `IL2Mailbox.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/interfaces/IL2Mailbox.sol#L2) floating pragma directive.
*   `AppendOnlyMerkleTree.sol` has the [`solidity ^0.8.24`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/libraries/common/AppendOnlyMerkleTree.sol#L3) floating pragma directive.
*   `BridgeBase.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/BridgeBase.sol#L2) floating pragma directive.
*   `ERC20Token.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L2) floating pragma directive.
*   `MailBoxBase.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L2) floating pragma directive.
*   `TokenBridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/TokenBridge.sol#L2) floating pragma directive.
*   `IBridgeBase.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/interfaces/IBridgeBase.sol#L2) floating pragma directive.
*   `IERC20Token.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/interfaces/IERC20Token.sol#L2) floating pragma directive.
*   `IGasPriceOracle.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/interfaces/IGasPriceOracle.sol#L2) floating pragma directive.
*   `IMailBoxBase.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/interfaces/IMailBoxBase.sol#L2) floating pragma directive.
*   `ITokenBridge.sol` has the [`solidity ^0.8.0`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/interfaces/ITokenBridge.sol#L2) floating pragma directive.

Consider using fixed pragma directives.

_**Update:** Resolved in [pull request #38](https://github.com/jovaynetwork/jovay-contracts/pull/38)._

For each ERC-20 deposited on L1, an equivalent amount of the bridged token must be minted on L2. Conversely, when the bridged token is withdrawn on L2, the corresponding amount of ERC-20 is released on L1. Preserving this one-to-one correspondence between the two sides is a critical invariant of the system.

For each ERC-20 token that is allowed to be deposited on L1, a mirror token is deployed on L2 ([`ERC20Token`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol) contract) with access-controlled [`mint`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L55-L57) and [`burn`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L69-L71) functions. The corresponding `L2ERC20Bridge` contract is expected to hold the `MINTER_ROLE` and `BURNER_ROLE`. However, the `ERC20Token` contract exposes multiple burn functions (a [`burn`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L62-L64) for burning tokens from the caller, a [`burn`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L69-L71) callable only by the `BURNER_ROLE`, that can burn tokens from any address without needing any approval, and a [`burnFrom`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L76-L78) function that allows the `MINTER_ROLE` to burn tokens from an address that has previously given approval). Only the second one is used by the `L2ERC20Bridge` contract.

If additional addresses are granted burner rights, they could burn tokens directly from user accounts. This would desynchronize balances between the L1 and L2 sides (breaking an important invariant) and also between the actual balance of the L2 token and its balance as it is tracked by the `L2ERC20Bridge` contract. This desynchronization will block bridging operations, because in `withdraw`, [it is checked that the two balances are equal](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L51).

Consider removing the extra `burn` and `burnFrom` functions and granting minter and burner roles exclusively to the `L2ERC20Bridge` contract.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46/commits) at commit [e5c60e3](https://github.com/jovaynetwork/jovay-contracts/pull/46/commits/e5c60e3ae0419bc2704fc993d931d36d95c90f9c)._

### Free-Memory Pointer is Moved to a Non-Word-Aligned Address

The Solidity ABI requires `0x40` (free-memory pointer) to remain 32-byte aligned. However, in the [`loadAndValidate`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/libraries/codec/BatchHeaderCodec.sol#L47-L56) function of the `BatchHeaderCodec` contract, after copying the header, the code updates the pointer with `mstore(0x40, add(batchPtr, length))`, but `length` is 105, resulting in a value that is _not_ divisible by 32. Further Solidity allocations will therefore start at an odd address and may unexpectedly clobber previously written data or lead to out-of-bounds reads, breaking compiler assumptions and potentially causing undefined behavior or reverts down the line.

Furthermore, each of the store functions of the contract writes directly to memory using inline assembly but does not update the free memory pointer. While their usage within `Rollup` is safe (since the free memory pointer [is adjusted in advance](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L161-L164)), relying on them in other contexts could lead to memory corruption.

Consider increasing the free memory pointer in `loadAndValidate` by 128 (the nearest multiple of 32 above 105) to maintain alignment with Solidity compiler expectation and avoid using the store functions outside the `Rollup` contract.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46) and [pull request #57](https://github.com/jovaynetwork/jovay-contracts/pull/57)._

### Missing Zero-Address Checks

When operations with `address` parameters are performed, it is crucial to ensure the address is not set to zero. Setting an address to zero is problematic because it has special burn/renounce semantics. This action should be handled by a separate function to prevent accidental loss of access during value or ownership transfers.

Throughout the codebase, multiple instances of missing zero-address checks were identified:

*   The [`target_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L147) operation within the contract `L1Mailbox` in `L1Mailbox.sol`
*   The [`target_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L156) operation within the contract `L1Mailbox` in `L1Mailbox.sol`
*   The [`_target`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L166) operation within the contract `L1Mailbox` in `L1Mailbox.sol`
*   The [`_l1_mail_box`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L107) operation within the contract `Rollup` in `Rollup.sol`
*   The [`l2Token_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L72) operation within the contract `L2ERC20Bridge` in `L2ERC20Bridge.sol`
*   The [`to_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L45) operation within the contract `L2ETHBridge` in `L2ETHBridge.sol`
*   The [`_l2EthBridge`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L21) operation within the contract `L2CoinBase` in `L2CoinBase.sol`
*   The [`refundAddress_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L117) operation within the contract `L2Mailbox` in `L2Mailbox.sol`
*   The [`admin`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L38) address in the contract `ERC20Token` in `ERC20Token.sol`

Consider always performing a zero-address check before assigning a state variable.

_**Update:** Resolved in [pull request #40](https://github.com/jovaynetwork/jovay-contracts/pull/40)._

### Inconsistent Handling of Empty Batches

When a relayer [commits](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L151-L184) a batch in the `Rollup` contract, its data hash is computed using the [`_getBlobDataHash`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L253-L271) function. This function iterates through all blobs and stops when it reaches a zero blob hash, which indicates that no further blobs are present. However, for the first blob, if it is empty, the function does not revert. Instead, it produces the `keccak256` hash of the empty string. Although relayers are expected to be honest and there is little incentive for submitting empty batches, it would be better to avoid it.

Consider modifying the implementation so that committing to empty batches reverts.

_**Update:** Resolved in [pull request #41](https://github.com/jovaynetwork/jovay-contracts/pull/41)._

Notes & Additional Information
------------------------------

### Incomplete Security Checks in Custom Merkle Tree Library

When a withdrawal is initiated on the L2 side, the relayer includes it in a batch that is later relayed to L1. To finalize the withdrawal on L1, the user must provide a [proof](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L139-L160) that their `finalizeWithdraw` message is indeed part of a batch. This verification relies on Merkle tree proofs, and a [custom library](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/libraries/verifier/WithdrawTrieVerifier.sol) has been developed for this purpose.

While the integration of this library with the bridge contracts is secure, the library itself lacks important safety checks typically expected in Merkle proof verification (e.g., ensuring that the provided proof length has the correct size for the given Merkle tree). Without such checks, it is possible to construct proofs for intermediate tree nodes rather than just for the leaves of the tree.

Consider documenting the limitations of the custom Merkle tree library and be aware that reusing it outside the current integration may introduce risks.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Modifier Applied Twice in `withdrawAll`

In the `L2CoinBase` contract, the [`withdrawAll`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L95-L97) function calls [`withdraw`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L85-L93) and both functions have an `onlyWithdrawer` modifier. As a result, the access-control check is applied twice during every call of `withdrawAll`.

Consider removing the modifier from `withdrawAll` to reduce gas consumption.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Parent Contracts are not Initialized

The `L2CoinBase` contract inherits from OpenZeppelin's `OwnableUpgradeable`, `PausableUpgradeable`, and `ReentrancyGuardUpgradeable` contracts. However, in its [`initialize`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L19-L22) function, it only calls `_Ownable_init` and does not initialize the other two parent contracts. As a result, the [`_status`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/2d081f24cac1a867f6f73d512f2022e1fa987854/contracts/security/ReentrancyGuardUpgradeable.sol#L38) variable of the `ReentrancyGuardUpgradeable` contract is left at its default value of 0 instead of being set to [`_NOT_ENTERED`](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/2d081f24cac1a867f6f73d512f2022e1fa987854/contracts/security/ReentrancyGuardUpgradeable.sol#L44-L46) (1), as intended. While this creates an inconsistency, it will not affect the contract in practice, and will be fixed after the first call of a function with a `nonReentrant` modifier.

Consider explicitly initializing all parent contracts to ensure consistent and predictable contract state.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Setter Truncates 64-bit `rollupTimeLimit` to 32 bits

Within [`Rollup.sol`, in line 355](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L355), the storage variable `rollupTimeLimit` is declared as `uint64`, but the setter accepts a `uint32` parameter:

`function  setRollupTimeLimit(uint32  _rollupTimeLimit)  external  onlyOwner  {
  rollupTimeLimit  =  _rollupTimeLimit;
}` 

Values above 4,294,967,295 cannot be provided, silently capping the configurable time-limit to 32 bits and creating an arbitrary, undocumented restriction.

Consider aligning the `uint` sizes for consistency.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

Within [`Rollup.sol`, in line 373](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L373), the parameter description says "The verifier address of tee." even though the function actually sets the **ZK** verifier address. This documentation error can mislead developers and reviewers.

Consider correcting this documentation error.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### ‘TRANSFER\_ROLE’ Role Declared but Never Used

Within [`ERC20Token.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/ERC20Token.sol#L20), `TRANSFER_ROLE` is defined alongside the other role constants, yet no function in the contract checks or assigns it.

Consider removing this role declaration.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Unused State Variables

Throughout the codebase, multiple instances of unused state variables were identified:

*   In `Rollup.sol`, the [`maxTxsInChunk` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L20)
*   In `Rollup.sol`, the [`maxBlockInChunk` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L23)
*   In `Rollup.sol`, the [`maxCallDataInChunk` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L26)
*   In `Rollup.sol`, the [`l1BlobNumberLimit` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L32)
*   In `Rollup.sol`, the [`rollupTimeLimit` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L35)

To improve the overall clarity and intent of the codebase, consider removing any unused state variables.

_**Update:** Resolved. The Jovay team stated:_

> _These `public` state variables are used by the relayer, so we cannot remove them._

### Unused Imports

Throughout the codebase, multiple instances of unused imports were identified:

*   The import [`import "./IL1BridgeProof.sol";`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/interfaces/IL1ERC20Bridge.sol#L4) in `IL1ERC20Bridge.sol`.
*   The import [`import "../../../common/interfaces/ITokenBridge.sol";`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/interfaces/IL1ERC20Bridge.sol#L5) in `IL1ERC20Bridge.sol`.
*   The import [`import "./IL1BridgeProof.sol";`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/interfaces/IL1ETHBridge.sol#L4) in `IL1ETHBridge.sol`.
*   The import [`import {L2Mailbox} from "../core/L2Mailbox.sol";`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L9) in `L2ETHBridge.sol`.

Consider removing unused imports to improve the overall clarity and readability of the codebase.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Non-Explicit Imports

The use of non-explicit imports in the codebase can decrease code clarity and may create naming conflicts between locally defined and imported variables. This is particularly relevant when multiple contracts exist within the same Solidity file or when inheritance chains are long.

Throughout the codebase, multiple instances of non-explicit imports were identified:

*   The [import "../../common/BridgeBase.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1BridgeProof.sol#L4) import in `L1BridgeProof.sol`
*   The [import "../../L2/bridge/interfaces/IL2ERC20Bridge.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L9) import in `L1ERC20Bridge.sol`
*   The [import "../../common/TokenBridge.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L10) import in `L1ERC20Bridge.sol`
*   The [import "../interfaces/IL1Mailbox.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol#L8) import in `L1ETHBridge.sol`
*   The [import "./L1BridgeProof.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol#L10) import in `L1ETHBridge.sol`
*   The [import "../interfaces/IRollup.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L5) import in `L1Mailbox.sol`
*   The [import "../../common/MailBoxBase.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L6) import in `L1Mailbox.sol`
*   The [import "../interfaces/IRollup.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L4) import in `Rollup.sol`
*   The [import "../libraries/verifier/IZkRollupVerifier.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L7) import in `Rollup.sol`
*   The [import "../../common/TokenBridge.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L6) import in `L2ERC20Bridge.sol`
*   The [import "../../common/interfaces/IERC20Token.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L7) import in `L2ERC20Bridge.sol`
*   The [import "./interfaces/IL2ETHBridge.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L7) import in `L2ETHBridge.sol`
*   The [import "../bridge/interfaces/IL2ETHBridge.sol";](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L4) import in `L2CoinBase.sol`

Following the principle that clearer code is better code, consider using the named import syntax _(`import {A, B, C} from "X"`)_ to explicitly declare which contracts are being imported.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Prefix Increment Operator (`++i`) Can Save Gas in Loops

Throughout the codebase, multiple opportunities where the subject optimization can be applied were identified:

*   The [i++](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/libraries/verifier/WithdrawTrieVerifier.sol#L22) increment in `WithdrawTrieVerifier.sol`
*   The [height++](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/libraries/common/AppendOnlyMerkleTree.sol#L26) increment in `AppendOnlyMerkleTree.sol`

Consider using the prefix-increment operator (`++i`) instead of the postfix-increment operator (`i++`) in order to save gas. This optimization skips storing the value before the incremental operation, as the return value of the expression is ignored.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Multiple Functions With Incorrect Order of Modifiers

Function modifiers should be ordered as follows: `visibility`, `mutability`, `virtual`, `override`, and `custom modifiers`.

Throughout the codebase, multiple instances of functions having an incorrect order of modifiers were identified:

*   The [`setTokenMapping`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L21-L29) function in `L1ERC20Bridge.sol`
*   The [`deposit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L31-L46) function in `L1ERC20Bridge.sol`
*   The [`setNewBatchBlobFeeAndTxFee`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L100-L121) function in `L1GasOracle.sol`
*   The [`setBlobBaseFeeScalaAndTxFeeScala`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L123-L130) function in `L1GasOracle.sol`
*   The [`setL1Profit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L132-L137) function in `L1GasOracle.sol`
*   The [`setTotalScala`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L139-L144) function in `L1GasOracle.sol`
*   The [`setMaxL1ExecGasUsedLimit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L146-L151) function in `L1GasOracle.sol`
*   The [`setMaxL1BlobGasUsedLimit`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L153-L158) function in `L1GasOracle.sol`
*   The [`addRelayer`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L160-L164) function in `L1GasOracle.sol`
*   The [`removeRelayer`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L166-L170) function in `L1GasOracle.sol`
*   The [`setL2EthBridge`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L56-L59) function in `L2CoinBase.sol`
*   The [`addWithdrawer`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L61-L65) function in `L2CoinBase.sol`
*   The [`removeWithdrawer`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L67-L71) function in `L2CoinBase.sol`
*   The [`addWhiteAddress`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L73-L77) function in `L2CoinBase.sol`
*   The [`removeWhiteAddress`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L79-L83) function in `L2CoinBase.sol`
*   The [`withdraw`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L85-L93) function in `L2CoinBase.sol`
*   The [`withdrawAll`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L95-L97) function in `L2CoinBase.sol`
*   The [`setL1MailBox`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L38-L41) function in `L2Mailbox.sol`
*   The [`setTokenMapping`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/interfaces/ITokenBridge.sol#L12) function in `ITokenBridge.sol`

To improve the project's overall legibility, consider reordering the modifier order of functions as recommended by the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#function-declaration).

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Redundant Getter Functions

When state variables use `public` visibility in a contract, a getter method for the variable is automatically included.

Throughout the codebase, multiple instances of redundant getter functions were identified:

*   Within the `L1Mailbox` contract in `L1Mailbox.sol`, the [`nextMsgIndex`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L197-L199) function is redundant because the `pendingQueueIndex` state variable already has a getter.
*   Within the `Rollup` contract in `Rollup.sol`, the [`getL2MsgRoot`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L249-L251) function is redundant because the `l2MsgRoots` state variable already has a getter.

To improve the overall clarity, intent, and readability of the codebase, consider removing the redundant getter functions.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46). The Jovay team stated:_

> _`getL2MsgRoot` is used by other components. So, while we will not remove it, we have added the relevant documentation._

### Missing Named Parameters in Mappings

Since [Solidity `0.8.18`](https://github.com/ethereum/solidity/releases/tag/v0.8.18), mappings can include named parameters to provide more clarity about their purpose. Named parameters allow mappings to be declared in the form `mapping(KeyType KeyName? => ValueType ValueName?)`. This feature enhances code readability and maintainability.

Throughout the codebase, multiple instances of mappings without named parameters were identified:

*   The [`committedBatches` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L50) in the `Rollup` contract
*   The [`finalizedStateRoots` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L53) in the `Rollup` contract
*   The [`l2MsgRoots` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L56) in the `Rollup` contract
*   The [`l1MsgCount` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L59) in the `Rollup` contract
*   The [`isRelayer` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L66) in the `Rollup` contract
*   The [`isRelayer` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L31) in the `L1GasOracle` contract
*   The [`isWithdrawer` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L25) in the `L2CoinBase` contract
*   The [`whiteListOnL1` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L28) in the `L2CoinBase` contract
*   The [`receiveMsgStatus` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L13) in the `L2Mailbox` contract
*   The [`sendMsgMap` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L27) in the `MailBoxBase` contract
*   The [`receiveMsgMap` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L29) in the `MailBoxBase` contract
*   The [`isBridge` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L34) in the `MailBoxBase` contract
*   The [`tokenMapping` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/TokenBridge.sol#L8) in the `TokenBridge` contract
*   The [`balanceOf` state variable](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/TokenBridge.sol#L10) in the `TokenBridge` contract

Consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Missing Security Contact

Providing a specific security contact (such as an email address or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Throughout the codebase, multiple instances of contracts not having a security contact were identified:

*   The [`L1ERC20Bridge` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol)
*   The [`L1ETHBridge` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol)
*   The [`L1GasOracle` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol)
*   The [`L1Mailbox` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol)
*   The [`Rollup` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol)
*   The [`L2ERC20Bridge` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol)
*   The [`L2ETHBridge` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol)
*   The [`L2CoinBase` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol)
*   The [`L2Mailbox` contract](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol)

Consider adding a NatSpec comment containing a security contact above each contract definition. Using the `@custom:security-contact` convention is recommended as it has been adopted by the [OpenZeppelin Wizard](https://wizard.openzeppelin.com/) and the [ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### Magic Numbers

Throughout the codebase, multiple instances of literal values with unexplained meanings were identified:

*   The [`1000000`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L28) literal number in `L1ERC20Bridge.sol`
*   The [`100`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L238) literal number in `Rollup.sol`
*   The [`1e6`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L59) literal number in `L1GasOracle.sol`
*   The [`6`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L60) literal number in `L1GasOracle.sol`
*   The [`128`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L60) literal number in `L1GasOracle.sol`
*   The [`1024`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L60) literal number in `L1GasOracle.sol`
*   The [`110`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L61) literal number in `L1GasOracle.sol`
*   The [`100`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L62) literal number in `L1GasOracle.sol`
*   The [`100`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L63) literal number in `L1GasOracle.sol`
*   The [`100`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L74) literal number in `L1GasOracle.sol`
*   The [`100`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L74) literal number in `L1GasOracle.sol`
*   The [`100`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L75) literal number in `L1GasOracle.sol`

Consider defining and using `constant` variables instead of using literals to improve the clarity and maintainability of the codebase.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### `public` Function or Variable Prefixed With Underscore

As per the Solidity style convention, `public` functions and variables should not be prefixed with an underscore.

In `AppendOnlyMerkleTree.sol`, the [`_branches`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/libraries/common/AppendOnlyMerkleTree.sol#L22) variable is `public` but has been prefixed with an underscore.

Consider removing the underscore prefix from the identifiers of `public` functions and variables.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

### File and Contract Name Mismatch

The [`IClaimAmount.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/interfaces/IClaimAmount.sol) file name does not match the `IClaim` contract name.

To make the codebase easier to understand for developers and reviewers, consider renaming the files to match the contract names.

_**Update:** Resolved. The Jovay team stated:_

> _We have removed this file as it was unused._

### Appending Before Merkle Tree Initialization Results in Permanent Root Inconsistency

Within [`AppendOnlyMerkleTree.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/libraries/common/AppendOnlyMerkleTree.sol#L33), the append routine can be invoked even if the zero-hash cache has not been pre-computed. The guard statement that should enforce initialization is currently [commented out](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/libraries/common/AppendOnlyMerkleTree.sol#L33). Therefore, a caller can execute `_appendMsgHash` with every value in `_zeroHashes` still equal to 0. While the function will seemingly work, every internal node that is computed will be mixed with a zero value instead of the canonical hash of zero.

Once the tree is later initialized, the cached zero values change, making all previously stored branches and the exposed `_msgRoot` mathematically incorrect. All subsequent consistency checks or proof verifications that rely on the Merkle root will fail permanently. Since the function has been declared as `internal`, the bug will surface in any inheriting contract that does not call `_initializeMerkleTree` first. In addition, [`_initializeMerkleTree`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/libraries/common/AppendOnlyMerkleTree.sol#L27) never explicitly assigns `_zeroHashes[0] = bytes32(0)`, instead relying on the default value. This omission reduces clarity and increases the likelihood of misuse.

Consider enforcing initialization by re-enabling the guard check and explicitly assigning `_zeroHashes[0] = bytes32(0)` during `_initializeMerkleTree` to avoid ambiguity and potential misuse.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

In the [`_transferERC20`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L59-L66) function of the `L1ERC20Bridge` contract, there is a [comment](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L62) suggesting that the design allows for the handling of fee-on-transfer tokens. The design flow is as follows:

1.  The contract attempts to pull the specified by the user `_amount` using `safeTransferFrom`. A fee-on-transfer token may deliver lass than `amount_` to the contract.
2.  The internal tracked balance is increased by the full `amount_`.
3.  The contract checks that the actual balance is at least equal to the tracked one.

However, for tokens with fees on transfer, the actual amount received will be less that `amount_`, and therefore the actual balance will be less that the tracked one. As a result, the [`require`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L65) statement enforcing the balance check will fail for such tokens, making them unsupported in practice.

Consider adjusting the implementation to correctly handle the reduced received amount for tokens with fees. Alternatively, consider removing the comment entirely if the protocol does not plan to support such tokens.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46). The Jovay team stated:_

> _We do not support fee-on-transfer tokens, currently._

### Duplicate Ownership Transfer in `Initialize` Emits Two `OwnershipTransferred` Events

Within [`BridgeBase.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/BridgeBase.sol#L32), `initialize` first calls `OwnableUpgradeable.__Ownable_init()`, which unconditionally sets the owner to `_msgSender()` (the account performing the initialization). A few lines later, the code executes [`_transferOwnership(owner)`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/BridgeBase.sol#L39) to hand over control to the `owner` argument supplied by the caller. This pattern produces **two `OwnershipTransferred` events in the same transaction**, which can confuse off-chain indexers and on-chain logic that relies on the _first_ event as the definitive owner.

A cleaner pattern would be to set the final owner only once. In fact, the reliance on outdated OpenZeppelin upgradeable libraries (v4.x) makes this clumsier than necessary: `__Ownable_init()` in v4.x always sets the owner to `msg.sender`, while OpenZeppelin v5.x introduces `__Ownable_init(address initialOwner)` to set the desired owner directly in a single step.

Consider upgrading the OpenZeppelin dependencies **across the codebase** to the latest version and using `__Ownable_init(address initialOwner)` in initializers to avoid the double ownership transfer.

_**Update:** Resolved in [pull request #59](https://github.com/jovaynetwork/jovay-contracts/pull/59)._

### Misleading and Missing Event Emissions

Throughout the codebase, there are several functions that either emit unnecessary events or fail to emit an event despite modifying important system parameters.

The [`removeRelayer`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L166-L170) of the `L1GasOracle` contract flips the mapping entry to `false` without checking that `_oldRelayer` is currently marked `true`. The owner can therefore "remove" any arbitrary address—including one that was never a relayer or the zero address—while still emitting `RemoveRelayer`. Off-chain indexers relying on events will record a state transition that never actually happened, causing data inconsistencies. Similar issues arise in [`MailboxBase::removeBridge`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L106-L108).

The following functions update the state without an event emission:

*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L65-L80) in `L1Mailbox.sol`
*   The [`setRollup` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L82-L85) in `L1Mailbox.sol`
*   The [`setWithdrawer` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L87-L90) in `L1Mailbox.sol`
*   The [`withdrawDepositFee` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L162-L168) in `L1Mailbox.sol`
*   The [`setLastQueueIndex` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L220-L222) in `L1Mailbox.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L88-L114) in `Rollup.sol`
*   The [`revertBatches` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L236-L247) in `Rollup.sol`
*   The [`revertBatches` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L236-L247) in `Rollup.sol`
*   The [`addRelayer` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L305-L311) in `Rollup.sol`
*   The [`removeRelayer` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L315-L317) in `Rollup.sol`
*   The [`setMaxTxsInChunk` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L331-L333) in `Rollup.sol`
*   The [`setMaxBlockInChunk` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L337-L339) in `Rollup.sol`
*   The [`setMaxCallDataInChunk` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L343-L345) in `Rollup.sol`
*   The [`setL1BlobNumberLimit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L349-L351) in `Rollup.sol`
*   The [`setRollupTimeLimit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L355-L357) in `Rollup.sol`
*   The [`setL2ChainId` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L361-L363) in `Rollup.sol`
*   The [`setTeeVerifierAddress` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L367-L370) in `Rollup.sol`
*   The [`setZkVerifierAddress` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L374-L377) in `Rollup.sol`
*   The [`withdraw` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L28-L52) in `L2ERC20Bridge.sol`
*   The [`withdraw` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L28-L52) in `L2ERC20Bridge.sol`
*   The [`finalizeDeposit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L63-L75) in `L2ERC20Bridge.sol`
*   The [`claimDeposit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L53-L60) in `L2ETHBridge.sol`
*   The [`claimDeposit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L62-L70) in `L2ETHBridge.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L55-L71) in `L1GasOracle.sol`
*   The [`CalcL1FeePerByte` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L73-L76) in `L1GasOracle.sol`
*   The [`setNewBatchBlobFeeAndTxFee` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L100-L121) in `L1GasOracle.sol`
*   The [`setBlobBaseFeeScalaAndTxFeeScala` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L123-L130) in `L1GasOracle.sol`
*   The [`setL1Profit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L132-L137) in `L1GasOracle.sol`
*   The [`setTotalScala` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L139-L144) in `L1GasOracle.sol`
*   The [`setMaxL1ExecGasUsedLimit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L146-L151) in `L1GasOracle.sol`
*   The [`setMaxL1BlobGasUsedLimit` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L153-L158) in `L1GasOracle.sol`
*   The [`addRelayer` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L160-L164) in `L1GasOracle.sol`
*   The [`removeRelayer` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L1GasOracle.sol#L166-L170) in `L1GasOracle.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L19-L22) in `L2CoinBase.sol`
*   The [`addWithdrawer` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L61-L65) in `L2CoinBase.sol`
*   The [`removeWithdrawer` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L67-L71) in `L2CoinBase.sol`
*   The [`addWhiteAddress` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L73-L77) in `L2CoinBase.sol`
*   The [`removeWhiteAddress` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L79-L83) in `L2CoinBase.sol`
*   The [`withdraw` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L85-L93) in `L2CoinBase.sol`
*   The [`withdrawAll` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2CoinBase.sol#L95-L97) in `L2CoinBase.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L25-L36) in `L2Mailbox.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L25-L36) in `L2Mailbox.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L25-L36) in `L2Mailbox.sol`
*   The [`setL1MailBox` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/jovay-contracts-24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/core/L2Mailbox.sol#L38-L41) in `L2Mailbox.sol`
*   The [`initialize` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/BridgeBase.sol#L31-L40) in `BridgeBase.sol`
*   The [`setMailBox` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/BridgeBase.sol#L42-L45) in `BridgeBase.sol`
*   The [`setToBridge` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/BridgeBase.sol#L47-L50) in `BridgeBase.sol`
*   The [`addBridge` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L100-L102) in `MailBoxBase.sol`
*   The [`removeBridge` function](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/common/MailBoxBase.sol#L106-L108) in `MailBoxBase.sol`

Consider emitting events whenever there are state changes and checking that the state has been actually changed before emitting an event. Doing so will help improve the clarity of the codebase and make it less error-prone.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

During development, having well described TODO/Fixme comments will make the process of tracking and solving them easier. However, left unaddressed, these comments might age and important information for the security of the system might be forgotten by the time it is released to production. As such, these comments should be tracked in the project's issue backlog and resolved before the system is deployed.

Throughout the codebase, multiple instances of TODO/Fixme comments were identified:

*   The TODO comment in [line 52 of `L1ERC20Bridge.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L52-L53)
*   The TODO comment in [line 38 of `L1ETHBridge.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol#L38-L39)
*   The TODO comment in [line 220 of `Rollup.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/Rollup.sol#L220-L221)
*   The TODO comment in [line 70 of `L2ERC20Bridge.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L70-L71)
*   The TODO comment in [line 47 of `L2ETHBridge.sol`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L47-L48).

Consider removing all instances of TODO/Fixme comments and instead tracking them in the issues backlog. Alternatively, consider linking each inline TODO/Fixme comment to the corresponding issues backlog entry.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46) and [pull request #53](https://github.com/jovaynetwork/jovay-contracts/pull/53)._

### Use `calldata` Instead of `memory`

When dealing with the parameters of `external` functions, it is more gas-efficient to read their arguments directly from `calldata` instead of storing them to `memory`. `calldata` is a read-only region of memory that contains the arguments of incoming `external` function calls. This makes using `calldata` as the data location for such parameters cheaper and more efficient compared to `memory`. Thus, using `calldata` in such situations will generally save gas and improve the performance of a smart contract.

Throughout the codebase, multiple instances where function parameters should use `calldata` instead of `memory` were identified:

*   In `L1BridgeProof.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1BridgeProof.sol#L11) parameter
*   In `L1BridgeProof.sol`, the [`proof_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1BridgeProof.sol#L12) parameter
*   In `L1ERC20Bridge.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L31) parameter
*   In `L1ERC20Bridge.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ERC20Bridge.sol#L48) parameter
*   In `L1ETHBridge.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol#L16) parameter
*   In `L1ETHBridge.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/bridge/L1ETHBridge.sol#L29) parameter
*   In `L1Mailbox.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L144) parameter
*   In `L1Mailbox.sol`, the [`proof_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L1/core/L1Mailbox.sol#L145) parameter
*   In `L2ERC20Bridge.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ERC20Bridge.sol#L28) parameter
*   In `L2ETHBridge.sol`, the [`msg_`](https://github.com/jovaynetwork/jovay-contracts/blob/24f525f379558eed27441f7233e5921591e0063d/rollup_contracts/contracts/L2/bridge/L2ETHBridge.sol#L21) parameter

Consider using `calldata` as the data location for the parameters of `external` functions to optimize gas usage.

_**Update:** Resolved in [pull request #46](https://github.com/jovaynetwork/jovay-contracts/pull/46)._

Conclusion
----------

The scope of this audit covered the Bridge contracts, which are designed for deployment on both the L1 and L2 networks. Two versions of these contracts were reviewed: one supporting ETH bridging and another for bridging ERC-20 tokens. The `Rollup` contract was also audited, which will be deployed on the L1 and is the contract where relayers will post batches of L2 transactions along with their proofs. Several complementary contracts used for verifying Merkle proofs, estimating L1 gas fees on the L2 side, and transferring the collected fees were also reviewed.

The review identified 2 high-severity, 7 medium-severity, and several lower-severity issues. These findings provide constructive insights that can help further strengthen the system’s robustness, consistency, and maintainability.

Two distinct proof systems are in the process of being implemented. This indicates that the design is still evolving and will benefit from a thorough follow-up audit as development progresses.

The Jovay team was highly responsive throughout the engagement, addressing questions promptly and showing a strong commitment to strengthening the security of their codebase. We would like to thank them for their close collaboration and constructive engagement.