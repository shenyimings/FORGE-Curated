\- April 10, 2025

![](https://www.openzeppelin.com/hs-fs/hubfs/oz-profile-1.png?width=22&height=22&name=oz-profile-1.png)

Summary
-------

Type

Timeline

From 2025-03-03

To 2025-03-19

Languages

Solidity

Total Issues

18 (6 resolved)

Critical Severity Issues

3 (2 resolved)

High Severity Issues

1 (1 resolved)

Medium Severity Issues

2 (2 resolved)

Low Severity Issues

4 (1 resolved)

Notes & Additional Information

8 (0 resolved)

Scope
-----

We audited the[0xFFoundation/fchain-contracts](https://github.com/0xFFoundation/fchain-contracts/)repository at commit[11ffd45](https://github.com/0xFFoundation/fchain-contracts/tree/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2).

In scope were the following files:

`fchain-contracts/  
└── src/  
    ├── StakeManager.sol  
    └── ValidatorRegistry.sol  
`

System Overview
---------------

The audited codebase manages the validator set for F Foundation's "FCHAIN", a subnet following the[ACP-77](https://github.com/avalanche-foundation/ACPs/blob/main/ACPs/77-reinventing-subnets/README.md)specification in the Avalanche ecosystem. The contracts in scope are a fork of[Ava Lab's ICM contracts](https://github.com/ava-labs/icm-contracts/tree/v1.0.8). The codebase utilizes the Warp Messenger, a standard that uses precompiles to send messages across a subnet and the Avalanche P-chain. Messages can be signed by P-chain validators to manage the official validator set of ACP-77 subnets, like the FCHAIN.

The setup of the validation scheme involves "licenses", which are NFTs that will be sold or distributed when the FCHAIN is first launched. These licenses will give a user the ability to become a validator on the FCHAIN. In order to do this, the user will need to lock up their license NFT. Once this is done, the validator can begin earning rewards for each "epoch" in which they have sufficient uptime. Rewards will be paid out in the native token for the FCHAIN and automatically re-staked. Delegators can also stake on validators, earning some rewards for both themselves and the validator, in exchange for not having to do the work of validating. Staking for both validators and delegators requires at least one staked license, but rewards can be increased by staking additional licenses or native tokens.

To prevent manipulation of the validator scheme, there is a time delay for joining and exiting the validator or delegator set. This gives P-chain validators the time to sign any changes to the FCHAIN validator set and prevents validators from receiving rewards for partial epochs. This is implemented generally by having "initialize" and "complete" functions for most state transitions, where, between the two phases, the P-chain generates a signed message verifying the transition.

In addition, to stabilize the system, there is a 1-year period during which delegators cannot withdraw their stakes. This period is the same for everyone and ends 1 year after the beginning of the FCHAIN. Notably, this period is not applicable to validators, allowing them to remove their stakes as soon as they stop validating. While delegators cannot withdraw, they are allowed to change their selected validator during this time and deposit more stakes.

Security Model and Trust Assumptions
------------------------------------

During the audit, the following trust assumptions were made:

*   It is assumed that the Warp messenger precompiles and Warp messaging protocol function as stated in the[ACP-77 specification](https://github.com/avalanche-foundation/ACPs/blob/main/ACPs/77-reinventing-subnets/README.md).
*   It is assumed that the`updateBalances`or`updateMultipleBalances`functions will be called after the grace period of every epoch, but before the epoch ends, for every`stakeID`actively validating the system.
*   It is assumed that uptime proofs will be signed by the P-chain validators for each`stakeID`during the grace period for each epoch. It is similarly assumed that`submitUptimeProof`or`submitMultipleUptimeProofs`will be called during the grace period for each epoch, for every`stakeID`that is registered.
*   It is assumed that P-chain validators will sign Warp messages in a timely manner as described by ACP-77.

While the uptime and rewards accrual scheme is fragile, it has been incentivized to function properly. The functions for tabulating uptime and for accruing rewards are openly callable, capable of being called for more than one epoch at a time, and may not be called for every validator or delegator for every epoch. However, we understand that the F Foundation team intends to automate calls to the applicable functions. As such, we make the following assumptions as part of our security assessment:

*   It is assumed that an automated service will submit uptime proofs for all validators, for all epochs, before the end of the grace period for that epoch.
*   It is assumed that uptime proofs will only be created once per epoch, per validator.
*   It is assumed that balance updates will be submitted after the grace period of each epoch and before the beginning of the next epoch, for each validator and for each delegator, once per epoch.
*   The P-chain Validator set has the ability to send Warp messages, which can be used to affect the validator and delegator set of the FCHAIN. It is further assumed that the P-chain Validators will only sign Warp messages which are valid, and that they will check the state of the FCHAIN before signing messages pertaining to it.

### Privileged Roles

Throughout the codebase, the following privileged roles were identified:

*   Within the`StakeManager`contract, only the`DEFAULT_ADMIN_ROLE`is authorized to upgrade the contract.
*   Within the`ValidatorRegistry`contract, the`VALIDATOR_ADMIN_ROLE`can:
    *   initialize validator registration.
    *   complete validator registration.
    *   initialize end validation.
    *   complete end validation.
    *   mint native tokens.
    *   set validator weight.
*   Within the`ValidatorRegistry`contract, the`DEFAULT_ADMIN_ROLE`can grant or revoke`VALIDATOR_ADMIN_ROLE`role.

ICM Contracts Under Development
-------------------------------

It should be noted that the[ICM contracts](https://github.com/ava-labs/icm-contracts/tree/v1.0.8), which the audited codebase has been forked from, are still under active development. Thus, it is recommended that the F Foundation team keep an eye on new developments in the ICM contracts codebase, and review any changes for integration into the audited codebase. The F Foundation team should inspect new releases of the ICM contracts and their associated discussions. Moreover, they should monitor the discussions associated with[ACP-77](https://github.com/avalanche-foundation/ACPs/tree/main/ACPs/77-reinventing-subnets)and[ACP-99](https://github.com/avalanche-foundation/ACPs/tree/main/ACPs/99-validatorsetmanager-contract).

Critical Severity
-----------------

### Locked-In Licenses Can Be Transferred

Possession of an[`FNode`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/FNodes.sol)license is a[requirement to become a validator](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L194-L196)on FCHAIN. Validators must[lock](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L209)their ERC-721-compliant`FNode`tokens into the`StakeManager`contract to be recognized as active validators and receive incentives, while delegators can also[lock](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L268)and delegate their`FNode`tokens to active validators to earn rewards.

Within the`StakeManager`contract, both validators and delegators lock their`FNode`licenses by invoking the`internal`[`_lockLicenses`function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L858)during the initiation phases of validator registration, delegator registration, or when adding new stakes. This function confirms that the[caller (`_msgSender`) is the owner of the ERC-721 token](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L879-L881)and then “locks” the token by[updating](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L889)the`tokenLockedBy[tokenID]`mapping. Notably, only the`internal`mapping is modified the token itself is not transferred to the contract.

This allows the owner of the`FNode`token to be able to transfer ownership of their "locked" license by invoking the`transferFrom`or`safeTransferFrom`functions of the`IERC721`interface, which effectively cancels their eligibility as a network validator. Nevertheless, the original stake in`StakeManager`continues to earn rewards since the license remains counted in the validator’s overall weight. In addition, the new owner of the license[cannot restake](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L884-L886)the token because it is already recorded in the`tokenLockedBy`mapping.

Consider transferring the`FNode`token to the`StakeManager`contract during the locking process and returning it to the validator or delegator upon unlocking. Alternatively, consider making the`FNode`tokens non-transferrable as long as they are part of an active validator's weight.

_**Update:**Acknowledged, will resolve. The team stated:_

> _NFTs are going to be non-transferable for a year, so we are not going to change this part at the moment._

### Deposited Stakes Can Be Locked in`StakeManager`if the Validator Is Inactive

The[`initializeDeposit`function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L303)is designed to accept licenses and staking amounts as stakes for a validating node within the system. This function can be called by the validators to increase their own weight or by delegators to increase the weight of their delegated validator. However, the function does not validate the active status of a validator before proceeding with the deposit, allowing the stakers to inadvertently deposit resources into validators that are inactive. The function then[locks](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L314)the deposited licenses and value within the`StakeManager`contract,[adds the newly added weight to the validator's existing weight](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L316-L317), and[sends the corresponding set weight message to the P-Chain](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L319-L320). It also[creates an entry](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L322-L323)in the`pendingDeposits`mapping such that when`completeDeposit`function is called, these[stakes are added](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L350-L356)to the`nextEpochDeposit`mapping, which is[processed](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L984-L991)when the staker's balances are updated.

Given that the validator is already inactive, the P-Chain will reject the message to add weight and there will be no corresponding`messageIndex`available to call the[`completeDeposit`function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L328). Therefore,`pendingDeposits`are never counted as part of the staker's balances. Furthermore, given that the locked stakes are not a part of staker's balance, the staker will not be able to withdraw these stakes due to the[revert](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L395-L402)in the`createWithdrawalRequest`function, thereby locking these stakes inevitably within the`StakeManager`contract.

Consider checking that the validator is active in the`initializeDeposit`function before accepting deposits.

_**Update:**Resolved in[pull request #46](https://github.com/0xFFoundation/fchain-contracts/pull/46). The`initializeDeposit`function correctly checks if the validator is active before accepting stakes. Additionally, a`cancelDeposit`function has been introduced that allows users to withdraw any deposited stakes if the validator becomes inactive before the deposit is complete._

### Validators Can Skip`createEndRequest`and Quickly Re-Register

[Within the ACP-77 specification](https://github.com/avalanche-foundation/ACPs/blob/main/ACPs/77-reinventing-subnets/README.md#registerl1validatortx), it is identified that a validator can only be registered once:

> _When it is known that a given validationID is not and never will be registered, the P-Chain must be willing to sign an L1ValidatorRegistrationMessage for the validationID with registered set to false. This could be the case if the expiry time of the message has passed prior to the message being delivered in a RegisterL1ValidatorTx, or if the validator was successfully registered and then later removed_

However, it is possible for validators to re-register only on the FCHAIN, which creates a discrepancy between the validator sets recorded on the FCHAIN and those on the P-chain. This is because once a validator is de-registered, the P-chain is obligated to refuse to register it again.

To do this, a validator must first call[`initializeValidatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L190). Once the[`L1ValidatorRegistrationMessage`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L333-L334)is received from the P-chain, the validator can call[`completeValidatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L218). After this, the validator can quickly call[`initializeEndValidation`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L446)and[`completeEndValidation`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L467), then once again call[`initializeValidatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L190)and[`completeValidatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L218), using the same[`messageIndex`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L333-L334)as the original registration. This must be performed without calling[`_updateBalances`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1293)for that validator before`initializeEndValidation`is called, as doing so will affect the stake's[`fNodesTokenIDs`mapping](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L455-L457).

Additionally, this must all be done before the[`registrationExpiry`time](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L245)is reached. After this has occurred, the validator's[`isValidationEnded`boolean will be set to`true`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L471). This will have the effect of[preventing that validator's ending permanently](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L459-L461), preventing the[processing of uptime proofs](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L612-L633), and resulting in a mismatch between the validator sets recorded on the P-chain and on the FCHAIN. Note that another property of this vulnerability is validators are able to skip calling[`createEndRequest`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L415)entirely. This is clearly not the intended functionality.

Consider checking`isValidationEnded`[within the validator registration flow](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L259). Also, consider enforcing that in all cases,[`_updateBalances`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1293)is called at least once before a validator can initialize the ending validation. It may be possible to enforce this by flagging any new validators as "needing balance updates", or by checking the[`startEpoch`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L226)and[`nextEpochDeposit`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L230)values for that validator.

_**Update:**Resolved in[pull request #43](https://github.com/0xFFoundation/fchain-contracts/pull/43)._

High Severity
-------------

### Insufficient Checks on Warp Messages

Within the[`completeValidatorChange`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L755)and[`completeDelegatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L276)functions, Warp messages are ingested and utilized to validate logic. However, these Warp messages are insufficiently checked.

In[`completeValidatorChange`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L755), any value can be specified for[`oldNonceTarget`and`newNonceTarget`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L759-L760), but these values are[only used once](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L772-L778), for checks against[`oldNonceMessage`and`newNonceMessage`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L763-L770). Because of this, any message indices can be specified, allowing the function to easily execute without having the expected Warp messages. This may allow some delegator to quickly change their validator without having the approval of the P-chain. This can also be leveraged to trigger changes for validators that the caller does not control, potentially affecting other users' rewards.

In[`completeDelegatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L276), the only value in the Warp message that is used is the[`validationID`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L280-L282). Thus, any incorrect message with that same`validationID`may be used to make the function execute successfully. This may allow any delegator to register with a validator without having the approval of the P-chain.

In both cases, the amount of rewards accrued by this delegator can be easily manipulated. Thus, consider recording nonces for validator changes within[`initiateValidatorChange`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L694)and using these in`completeValidatorChange`to ensure that the messages used are newer than the initial request. This may also be used to prevent users from changing the validator of delegators that they do not know. Similarly, consider storing the[`nonce`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L255)obtained in`initializeDelegatorRegistration`and recording the`nonce`obtained from the Warp message[parsed in`completeDelegatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L280-L282). These values should be compared with each other to ensure that the P-Chain Warp message is newer than the request to initialize delegation.

_**Update:**Resolved in[pull request #45](https://github.com/0xFFoundation/fchain-contracts/pull/45)._

Medium Severity
---------------

### Potential Stake Lock and Inconsistency Due to Validator State Transitions

The`StakeManager`contract facilitates the[registration process for delegators](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L238)to stake on active validators. It also includes a[`createEndRequest`function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L415), enabling validators to initiate their withdrawal from the network. A problem arises when a delegator initiates staking on a validator that has begun the exit process through`createEndRequest`but has not yet updated their balance, leaving their`isValidationActive`flag set to`true`. This flag is only set to[`false`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1087)upon a balance update after the creation of the validation end request.

During this period, a delegator can execute the`initializeDelegatorRegistration`function, which[adds the weight of the stake to the validator](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L252-L253),[broadcasts the message to P-Chain](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L255-L256), and[locks the stakes](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L268)within the contract through the`_lockStakesAndLicensesSetTotalStats``internal`function. These stakes are then supposed to be reflected in the staker's balance upon calling`completeDelegatorRegistration`in the subsequent epoch, following a balance update.

However, if the validator proceeds to update their balances and initiate the end of their validation before the delegator completes their registration, the validator's weight could be reduced to zero. This sequence of actions introduces two significant issues:

*   If the weight update message from`initializeDelegatorRegistration`is processed after the validator's exit due to delayed pickup from the relayer or out-of-order processing by the P-Chain, it may be rejected if the validator is marked inactive on the P-Chain. This means that there will be no`messageIndex`for completing the delegator's registration, effectively locking the staked funds in the`StakeManager`contract without recourse.
*   In cases where the`initializeDelegatorRegistration`message is processed in time, providing a valid`messageIndex`, but the validator exits before`completeDelegatorRegistration`is executed, the system may still finalize the stake registration. This creates a discrepancy as the validator's weight is zero, yet the system acknowledges a stake registration. Consequently, delegators are unable to earn rewards due to the inability to verify the validator's uptime, nor can they unlock their tokens unless the`delegationLockDeadline`has elapsed, forcing them to reallocate their delegation.

This vulnerability extends to the[`initializeDeposit`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L303)and[`completeDeposit`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L328)functions, presenting a broader attack vector within the staking mechanism.

Consider adding a`PendingRemoved`status state for validators undergoing an exit and implementing a conditional check in the`completeDelegatorRegistration`and`completeDeposit`functions to release stakes if a validator is in this transitional state. Doing this would help safeguard against unintended stake lock and ensure consistency in validator and delegator states.

_**Update:**Resolved in[pull request #47](https://github.com/0xFFoundation/fchain-contracts/pull/47)._

### Resending Failed Set Weight Message Functionality is Needed

It is possible for Warp messages sent to the P-chain to be considered invalid[if they are not signed by at least 67% of the FCHAIN validators](https://github.com/avalanche-foundation/ACPs/blob/main/ACPs/77-reinventing-subnets/README.md#p-chain-warp-message-payloads). Many flows exist in[`StakeManager`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol)that depend on`L1ValidatorWeightMessage`. However, if these messages are dropped by the P-chain, such flows could be frozen, causing problems for users. For example, the[`completeWithdrawal`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L558-L561)function may be unusable if an`L1ValidatorWeightMessage`is never sent, leaving tokens locked in the`StakeManager`contract.

Consider creating a function similar to[`resendRegisterValidatorMessage`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L309)and[`resendEndValidatorMessage`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L419), but for the[`L1ValidatorWeightMessage`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L526-L528). This will allow action to be taken in the case where an important validator weight message is dropped by the P-chain.

_**Update:**Resolved in[pull request #44](https://github.com/0xFFoundation/fchain-contracts/pull/44)._

Low Severity
------------

### Incomplete Docstrings

Throughout the codebase, multiple instances of incomplete docstrings were identified:

*   In`StakeManager.sol`, in the[`createWithdrawalRequest`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L366-L413)function docstring, the`stakeID`,`amount`,`fNodesTokenIDs`parameters are not documented.
    
*   In`ValidatorRegistry.sol`, in the[`addValidatorAdmin`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorRegistry.sol#L89-L93)function docstring, the`account`parameter is not documented.
    
*   In`ValidatorRegistry.sol`, in the[`removeValidatorAdmin`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorRegistry.sol#L99-L103)function docstring, the`account`parameter is not documented.
    

Consider thoroughly documenting all functions/events (and their parameters or return values) that are part of a contract's public API. When writing docstrings, consider following the[Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html)(NatSpec).

_**Update:**Acknowledged, will resolve._

### Insufficient Validation in`initializeDeposit`

The[`initializeDeposit`function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L303-L306)allows deposits of both native tokens and lockups for licenses. However, in the case where[`fNodesTokenIDs`is empty](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L305)and`msg.value == 0`, the function will execute successfully without making any changes to the validator or delegator's stake, thereby, causing unnecessary gas consumption.

Following the "fail early and loudly" principle, consider adding a check for the length of`fNodesTokenIDs`and`msg.value`, reverting with a descriptive error if both of these values are 0.

_**Update:**Resolved in[pull request #48](https://github.com/0xFFoundation/fchain-contracts/pull/48)._

### Lack of In-line Documentation

The`StakeManager`and`ValidatorRegistry`contracts are observed to have a significant deficiency in in-line documentation, particularly the absence of docstrings across numerous functions and their input variables. This shortfall not only hampers the readability and maintainability of the codebase but also poses substantial challenges in ensuring its security and functionality.

Consider adding in-line documentation throughout the codebase to ensure that all functions, especially those that are public or external, are accompanied by detailed docstrings. These should include descriptions of the function's purpose, parameters, return values, emitted events, and any side effects or important notes regarding its behavior. When writing docstrings, consider following the[Ethereum Natural Specification Format](https://solidity.readthedocs.io/en/latest/natspec-format.html)(NatSpec).

_**Update:**Acknowledged, will resolve._

### Update`initialize...`Function Names to`initiate...`

Within the[`StakeManager`contract](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol), there are 5 functions that follow the naming convention of`initialize...`, such as:

*   [`initializeValidatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L190)
*   [`initializeDelegatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L238)
*   [`initializeDeposit`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L303)
*   [`initializeEndValidation`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L446)
*   [`initializeWithdraw`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L475)

These functions all have corresponding`complete...`functions. However, there is also a function with a similar naming that does not follow this convention:[`initiateValidatorChange`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L694), and it has a similar[`complete...`function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L755).

Consider changing the names of these 5 identified functions to`initiate...`. This will help keep the codebase consistent and easier to understand. Moreover, doing this will help separate these functions from the[`initialize`function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L148)and any associated functions related to initialization. Finally, it will help match the[most recent version of`icm-contracts``ValidatorManager.sol`](https://github.com/ava-labs/icm-contracts/blob/c6fd9ee655f4fb5bdaaa4f9e0bfe86cb16e94919/contracts/validator-manager/ValidatorManager.sol#L274)which has made the same change.

_**Update:**Acknowledged, will resolve._

Notes & Additional Information
------------------------------

During development, having well-described TODO comments will make the process of tracking and solving them easier. However, left unaddressed, these comments might age and important information for the security of the system might be forgotten by the time it is released to production. Thus, TODO comments should be tracked in the project's issue backlog and resolved before the system is deployed.

A TODO comment was identified in[line 543 of`StakeManager.sol`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L543).

Consider addressing all instances of TODO comments and tracking them in the issues backlog.

_**Update:**Acknowledged, will resolve._

### Inconsistent Function Ordering

The[`StakeManager`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol)and[`ValidatorRegistry`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorRegistry.sol)contracts deviate from the Solidity Style Guide due to having an inconsistent ordering of functions. For instance, in the`StakeManager`contract, the[`submitUptimeProof`external function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L636)is placed after the[`_processUptimeProof`internal function](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L603).

To improve the project's overall legibility, consider standardizing ordering throughout the codebase as recommended by the[Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-layout)([Order of Functions](https://docs.soliditylang.org/en/latest/style-guide.html#order-of-functions)).

_**Update:**Acknowledged, will resolve._

### Missing Named Parameters in Mappings

Since[Solidity 0.8.18](https://github.com/ethereum/solidity/releases/tag/v0.8.18), developers can utilize named parameters in mappings. This means mappings can take the form of`mapping(KeyType KeyName? => ValueType ValueName?)`. This updated syntax provides a more transparent representation of a mapping's purpose.

Within`StakeManager.sol`, the[`tokenExists`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L980)mapping does not have named parameters.

Consider adding named parameters to mappings in order to improve the readability and maintainability of the codebase.

_**Update:**Acknowledged, will resolve._

### Unused Named Return Variables

Named return variables are a way to declare variables that are meant to be used within a function's body for the purpose of being returned as that function's output. They are an alternative to explicit in-line`return`statements.

Within`StakeManager.sol`, multiple instances of unused named return variables were identified:

*   The[`validationID`return variable](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L931)of the`_processPendingValidatorChange`function
*   The[`result`return variable](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1255)of the`_getEpochRewardForDelegator`function

Consider either using or removing any unused named return variables.

_**Update:**Acknowledged, will resolve._

### Lack of Security Contact

Providing a specific security contact (such as an email or ENS name) within a smart contract significantly simplifies the process for individuals to communicate if they identify a vulnerability in the code. This practice is quite beneficial as it permits the code owners to dictate the communication channel for vulnerability disclosure, eliminating the risk of miscommunication or failure to report due to a lack of knowledge on how to do so. In addition, if the contract incorporates third-party libraries and a bug surfaces in those, it becomes easier for their maintainers to contact the appropriate person about the problem and provide mitigation instructions.

Both the[`StakeManager`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol)and the[`ValidatorRegistry`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorRegistry.sol)contracts do not have a security contact. In addition, the`ValidatorManager`contract currently[specifies](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorManager.sol#L28)a security contact for`ava-labs/icm-contracts`instead of specifying one for`0xFFoundation/fchain-contracts`.

Consider adding a NatSpec comment containing the correct security contact above each contract definition. Using the`@custom:security-contact`convention is recommended as it has been adopted by the[OpenZeppelin Wizard](https://wizard.openzeppelin.com/)and the[ethereum-lists](https://github.com/ethereum-lists/contracts#tracking-new-deployments).

_**Update:**Acknowledged, will resolve._

### Typographical Errors

Throughout the`StakeManager`contract, multiple instances of typographical errors were identified:

*   In[line 1301](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1301), "calalble" should be "callable".
*   In[line 1095](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1095), "decays by 82.5%" should be "decays by 17.5%".

Consider correcting any instances of typographical errors to improve the clarity and readability of the codebase.

_**Update:**Acknowledged, will resolve._

### `_disableInitializers`Not Being Called From Initializable Contract Constructors

An implementation contract in a proxy pattern allows anyone to call its`initialize`function. While not a direct security concern, preventing the implementation contract from being initialized is important, as this could allow an attacker to take over the contract. This would not affect the proxy contract's functionality, as only the implementation contract's storage would be affected.

Throughout the codebase, multiple instances of initializable contracts, where`_disableInitializers()`is not called in the constructors, were identified:

*   The initializable contract[`StakeManager`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L33-L1386)within the`StakeManager.sol`file
*   The initializable contract[`ValidatorRegistry`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorRegistry.sol#L20-L127)within the`ValidatorRegistry.sol`file

Consider calling`_disableInitializers()`inside the constructors of initializable contracts to prevent malicious actors from front-running initialization.

_**Update:**Acknowledged, will resolve._

### Function Visibility Overly Permissive

Within the codebase, there are various functions with unnecessarily permissive visibility:

*   The[`_validateEpoch`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L584-L601)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_processUptimeProof`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L603-L634)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_hasGracePeriodPassed`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L672-L676)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_getEpochEndTime`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L683-L687)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_getPChainWarpMessage`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L793-L811)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_getWeight`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L813-L822)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_getWeightSetLosses`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L824-L834)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_lockStakesAndLicensesSetTotalStats`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L836-L851)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_lock`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L853-L856)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_lockLicenses`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L858-L893)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_validateStakeAmount`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L895-L913)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_unlock`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L915-L917)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_unlockLicenses`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L919-L926)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_processPendingValidatorChange`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L928-L968)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_processPendingBalanceChanges`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L971-L1090)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_getEpochReward`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1151-L1170)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_getEpochRewardForValidator`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1185-L1240)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_getEpochRewardForDelegator`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1252-L1290)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_updateBalances`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1293-L1344)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`_revertIfDeadlineNotPassed`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/StakeManager.sol#L1373-L1377)function in`StakeManager.sol`with`internal`visibility could be limited to`private`.
    
*   The[`completeValidatorRegistration`](https://github.com/0xFFoundation/fchain-contracts/blob/11ffd45bc95747b8d2432a2e8bb120d4a1dc19a2/src/ValidatorRegistry.sol#L111-L120)function in`ValidatorRegistry.sol`with`public`visibility could be limited to`external`.
    

To better convey the intended use of functions and to potentially realize some additional gas savings, consider changing a function's visibility to be only as permissive as required.

_**Update:**Acknowledged, will resolve._

Conclusion
----------

The audited codebase manages the validator set for F Foundation's FCHAIN, a subnet operating under the ACP-77 specification in the Avalanche ecosystem. The audited code interacts with a fork of Ava Lab's ICM contracts`ValidatorManager`contract, which was out of scope of this audit.

Several critical and high-severity issues were identified, primarily related to the validation of key parameters used for registering validators and delegators. While some documentation is available in the docs folder of the audited codebase, adding more in-line documentation within the contracts could further enhance clarity. Since the ICM contracts are still under active development by Ava Labs, we encourage the F Foundation team to stay informed about any updates that may impact this codebase and to integrate relevant changes as needed.

The client was very responsive during the audit, addressed doubts promptly, and helped triage potential issues.