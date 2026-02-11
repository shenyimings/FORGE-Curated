# Orbit Action Contracts

A set of contracts that are similar to Arbitrum [gov-action-contracts](https://github.com/ArbitrumFoundation/governance/tree/main/src/gov-action-contracts), but are designed to be used with the Orbit chains.

## Requirments

[yarn](https://classic.yarnpkg.com/lang/en/docs/install/) and [foundry](https://book.getfoundry.sh/getting-started/installation) are required to run the scripts

Most of the action contracts only support the following ownership setup:

- Rollup Contract on Parent Chain owned by a `ParentUpgradeExecutor`
- Rollup ProxyAdmin on Parent Chain owned by a `ParentUpgradeExecutor`
- Arb Owner on the Child Orbit Chain is granted to alias of `ParentUpgradeExecutor`
- Arb Owner on the Child Orbit Chain is granted to `ChildUpgradeExecutor`

For token bridge related operations, these are the additional requirements:

- Token Bridge ProxyAdmin on Parent Chain owned by `ParentUpgradeExecutor`
- Token Bridge ProxyAdmin on Child Orbit Chain owned by `ChildUpgradeExecutor`
- Parent Chain Gateway Router and Custom Gateway owned by `ParentUpgradeExecutor`

## Setup

```
yarn install
```

## Check Version and Upgrade Path

Run the follow command to check the version of Nitro contracts deployed on the parent chain of your Orbit chain.

```
$ INBOX_ADDRESS=0xaE21fDA3de92dE2FDAF606233b2863782Ba046F9 yarn orbit:contracts:version --network arb1
Get the version of Orbit chain's nitro contracts (inbox 0xaE21fDA3de92dE2FDAF606233b2863782Ba046F9), hosted on chain 42161
Version of deployed Inbox: v1.1.1
Version of deployed Outbox: v1.1.1
Version of deployed SequencerInbox: v1.1.1
Version of deployed Bridge: v1.1.1
Version of deployed RollupProxy: v1.1.1
Version of deployed RollupAdminLogic: v1.1.1
Version of deployed RollupUserLogic: v1.1.1
This deployment can be upgraded to v1.2.1 using NitroContracts1Point2Point1UpgradeAction
```

For other networks, replace `arb1` with the network name and configure INFURA_KEY or the rpc in hardhat.config.ts

## Nitro Contracts Upgrades

_This section is also referenced in the documentation on ["How to upgrade ArbOS on your Orbit chain"](https://docs.arbitrum.io/launch-orbit-chain/how-tos/arbos-upgrade)_ as Step 2 and Step 3.

For ArbOS upgrades, a common pre-requisite is to deploy new Nitro contracts to the parent chain of your Orbit chain before scheduling the ArbOS upgrade. These contracts include the rollup logic, fraud proof contracts, and interfaces for interacting with Nitro precompiles. The scripts and instructions in this repository are meant for Orbit chain owners to upgrade the aforementioned contracts, set the new WASM module root, and then schedule the ArbOS upgrade.

### Nitro contracts 3.0.0 (for [BoLD](https://docs.arbitrum.io/how-arbitrum-works/bold/gentle-introduction))

The [`nitro-contracts 3.0.0` upgrade guide](scripts/foundry/contract-upgrades/3.0.0) will use the [BOLDUpgradeAction](https://github.com/OffchainLabs/nitro-contracts/blob/main/src/rollup/BOLDUpgradeAction.sol) from the [nitro-contract](https://github.com/OffchainLabs/nitro-contracts) repo. There are no associated ArbOS upgrade for BoLD. 

### Nitro contracts 2.1.2

The [`nitro-contracts 2.1.2` upgrade guide](scripts/foundry/contract-upgrades/2.1.2) will patch the `ERC20Bridge` with a storage layout fix.

This upgrade is only required if:

1. The chain has a custom native token; AND
1. The chain was originally deployed before `v2.0.0`; AND
1. The chain wishes to upgrade to `v3.0.0`

Do not perform this upgrade if the above requirements aren't met.

### Nitro contracts 2.1.0 (for [ArbOS 32 Bianca](https://docs.arbitrum.io/run-arbitrum-node/arbos-releases/arbos32))

The [`nitro-contracts 2.1.0` upgrade action](scripts/foundry/contract-upgrades/2.1.0) will deploy `nitro-contracts v2.1.0` contracts to your Orbit's parent chain. Note that this action will only work for chains with `nitro-contracts v1.2.1` or `nitro-contracts v1.3.0`.

Note: nitro contracts upgrade brings support for AnyTrust fast confirmations and Stylus. However, Stylus will be enabled only when `ArbOS 32 Bianca` upgrade takes place, once it will be officially supported for Orbit chains.

### Nitro contracts 1.2.1 (for [ArbOS 20 Atlas](https://docs.arbitrum.io/run-arbitrum-node/arbos-releases/arbos20))

The [`nitro-contracts 1.2.1` upgrade action](scripts/foundry/contract-upgrades/1.2.1) will deploy `nitro-contracts v1.2.1` contracts to your Orbit's parent chain. Note that this action will only work for chains with `nitro-contracts v1.1.0` or `nitro-contracts v.1.1.1`. ArbOS 20 Atlas, shipped via [Nitro v2.3.0](https://github.com/OffchainLabs/nitro/releases/tag/v2.3.0), requires [**`nitro-contracts v1.2.1`**](https://github.com/OffchainLabs/nitro-contracts/releases/tag/v1.2.1) or higher.

## Scheduling the ArbOS upgrade

_This section is also referenced in the documentation on ["How to upgrade ArbOS on your Orbit chain"](https://docs.arbitrum.io/launch-orbit-chain/how-tos/arbos-upgrade)_

Next, you will need to schedule the actual upgrade using the [ArbOS upgrade at timestamp action](scripts/foundry/arbos-upgrades/at-timestamp).

This action schedule an upgrade of the ArbOS to a specific version at a specific timestamp.

## Common upgrade paths

Here is a list of common upgrade paths that can be used to upgrade the Orbit chains. These instructions are duplicated from the docs on [How to upgrade ArbOS on your Orbit chain](https://docs.arbitrum.io/launch-orbit-chain/how-tos/arbos-upgrade), specifically Steps 1 through 3. Step 4 is mentioned below under "Other Actions".

### [ArbOS 32 Bianca](https://docs.arbitrum.io/run-arbitrum-node/arbos-releases/arbos32)

1. Upgrade your Nitro node(s) to [Nitro v3.3.1](https://github.com/OffchainLabs/nitro/releases/tag/v3.3.1)
1. Upgrade `nitro-contracts` to `2.1.0` using [nitro-contract 2.1.0 upgrade action](scripts/foundry/contract-upgrades/2.1.0)
1. Schedule the ArbOS 32 Bianca upgrade using [ArbOS upgrade at timestamp action](scripts/foundry/arbos-upgrades/at-timestamp)

### [ArbOS 20 Atlas](https://docs.arbitrum.io/run-arbitrum-node/arbos-releases/arbos20)

1. Upgrade your Nitro node(s) to [Nitro v2.3.1](https://github.com/OffchainLabs/nitro/releases/tag/v2.3.1)
1. Upgrade `nitro-contracts` to `v1.2.1` using [nitro-contract 1.2.1 upgrade action](scripts/foundry/contract-upgrades/1.2.1)
1. Schedule the ArbOS 20 Atlas upgrade using [ArbOS upgrade at timestamp action](scripts/foundry/arbos-upgrades/at-timestamp)

# Other Actions

Below are additional on-chain actions that Orbit chain owners and maintainers can take as part of [Step 4: Enable ArbOS specific configurations or feature flags](https://docs.arbitrum.io/launch-orbit-chain/how-tos/arbos-upgrade#step-4-enable-arbos-specific-configurations-or-feature-flags-not-always-required).

## Enable Fast Confirmation

See [EnableFastConfirmAction](scripts/foundry/fast-confirm).

## Enable Stylus Cache Manager

See [setCacheManager](scripts/foundry/stylus/setCacheManager). 
