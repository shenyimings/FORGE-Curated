# Nitro contracts 1.2.1 upgrade
These scripts empower `NitroContracts1Point2Point1UpgradeAction` action contract which performs upgrade to [1.2.1 release](https://github.com/OffchainLabs/nitro-contracts/releases/tag/v1.2.1) of Nitro contracts for existing Orbit chains. Predeployed instances of the upgrade action exists on the chains listed in the following section with vanilla ArbOS20 wasm module root set. If you have a custom nitro machine, you will need to deploy the upgrade action yourself.

NitroContracts1Point2Point1UpgradeAction will perform the following action:
1. Upgrade SequencerInbox to v1.2.1
2. Upgrade ChallengeManager to v1.2.1
3. Upgrade OneStepProof to v1.2.1
4. Set the wasm module root to the new version

Note that contracts without code changes are not upgraded. It is normal to have some contracts still in the old version after the upgrade as they are equivalent to the new version. After the contract upgrade, you would need to schedule an ArbOS upgrade to ArbOS20 to enable the new features.

## Requirements
This upgrade only support upgrading from the following [nitro-contract release](https://github.com/OffchainLabs/nitro-contracts/releases):
- Inbox: v1.1.0 - v1.2.1 inclusive
- Outbox: v1.1.0 - v1.2.1 inclusive
- SequencerInbox: v1.1.0 or v1.1.1
- Bridge: v1.1.0 - v1.2.1 inclusive
- RollupProxy: v1.1.0 - v1.2.1 inclusive
- RollupAdminLogic: v1.1.0 - v1.2.1 inclusive
- RollupUserLogic: v1.1.0 - v1.2.1 inclusive
- ChallengeManager: v1.1.0 - v1.2.1 inclusive

Please refers to the top [README](../../README.md) `Check Version and Upgrade Path` on how to determine your current nitro contracts version.

## Deployed instances

- L1 mainnet (eth fee token): 0xC159A3a21aFb34Dbc601a7A42aCD2eCa019393F7
- L1 mainnet (custom fee token): 0x2e0c12e2478a0dEc2EF6C2CCC2ED8d4fEd3597d1
- L2 Arb1 (eth fee token): 0x606Bb75B1f910F82086557aa14eD2Dc0bEB85D6B
- L2 Arb1 (custom fee token): 0xb28c89b6997F025BD35205b99a7968C264cCe353
- L1 Sepolia (eth fee token): 0xBC1e0ca800781F58F3a2f73dA4D895FdD61B0Cb5
- L1 Sepolia (custom fee token): 0xEFf65644557573e3E781B0B586fD7488a26c8E46
- L2 ArbSepolia (eth fee token): 0xe9F95d0975e87e8E633fceCDF17fFc0f646cCfb8
- L2 ArbSepolia (custom fee token): 0x86AdeeAcF16fdbCAEe615b12E56e064a665fCF47

## How to use it

1. Setup .env according to the example files, make sure you have everything correctly defined. The script do some sanity checks but not everything can be checked.

> [!CAUTION]
> The .env file must be in project root.

2. (Skip this step if you can use the deployed instances of action contract) 
`DeployNitroContracts1Point2Point1UpgradeAction.s.sol` script deploys OSPs and ChallengeManager templates, blob reader and SequencerInbox template, and finally the upgrade action itself. It can be executed in this directory like this:
```bash
forge script --sender $DEPLOYER --rpc-url $PARENT_CHAIN_RPC --broadcast --slow ./DeployNitroContracts1Point2Point1UpgradeAction.s.sol -vvv --verify --skip-simulation
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```
As a result, all templates and upgrade action are deployed. Note the last deployed address - that's the upgrade action.

3. `ExecuteNitroContracts1Point2Point1Upgrade.s.sol` script uses previously deployed upgrade action to execute the upgrade. It makes following assumptions - L1UpgradeExecutor is the rollup owner, and there is an EOA which has executor rights on the L1UpgradeExecutor. Proceed with upgrade using the owner account (the one with executor rights on L1UpgradeExecutor):
```bash
forge script --sender $EXECUTOR --rpc-url $PARENT_CHAIN_RPC --broadcast ./ExecuteNitroContracts1Point2Point1Upgrade.s.sol -vvv
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```
If you have a multisig as executor, you can still run the above command without broadcasting to get the payload for the multisig transaction.

4. That's it, upgrade has been performed. You can make sure it has successfully executed by checking wasm module root:
```bash
cast call --rpc-url $PARENT_CHAIN_RPC $ROLLUP "wasmModuleRoot()"
```
