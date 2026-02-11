# Enable Fast Confirmation
These scripts empower `EnableFastConfirmAction` contract which enable fast confirmation for existing AnyTrust chains.

This action performs the following steps:

1. Validate fast confirmation has not been enabled yet
1. Create a Safe contract for the fast confirmation committee
1. Set the Safe contract as the fast confirmer on the rollup
1. Set the Safe contract as a validator on the rollup
1. Set setMinimumAssertionPeriod to 1 block to allow more frequent assertion

The fast confirmation committee should align with the DAS committee to maintain the trust model of the chain. All members of the fast confirmation committee must be validators, the Safe contract would initially be deployed as a N-of-N multisig regardless of the AnyTrust threshold.

## Requirements

This upgrade only support upgrading from the following [nitro-contract release](https://github.com/OffchainLabs/nitro-contracts/releases):

- RollupAdminLogic: v2.1.0 or higher
- RollupUserLogic: v2.1.0 or higher

Please refer to the top [README](../../README.md) `Check Version and Upgrade Path` on how to determine your current nitro contracts version.

## Deployed instances

### Mainnets
- L1 Mainnet: 0xE102B527075b028B6bc6F4d4F11292D2F8a6673D
- L2 Arb1: 0xf1D831AA5b0b3032cF2c58CDF7BD58F598202320
- L2 Nova: 0x88B1f445e0048809789af7CF6f227Dc0f4febCFd
- L2 Base: 0xABFE646C3205A2d93Ec8C6e41eA67BC07e1275df

### Testnets
- L1 Sepolia: 0x618e44fd8a7639386256880ef8100e09a8bcd4f3
- L1 Holesky: 0x087F2f584B1CE7c938e2F4df088EbBCB784920AF.
- L2 ArbSepolia: 0x618e44Fd8a7639386256880Ef8100e09A8BcD4F3
- L2 BaseSepolia: 0xe0560Dc64Acd8acC2dBE1E642Fd80A45c9Da1cBE.

## How to use it
1. Setup .env according to the example files, make sure your fast confirm committee is secure (it should match your DAS committee). See the previous section for predeployed instances of the action contract. If you need to deploy the action contract yourself, follow the steps below.

> [!CAUTION]
> The .env file must be in project root.

`DeployEnableFastConfirmAction.s.s.sol` script deploys `EnableFastConfirmAction` contract. It can be executed in this directory like this:
```bash
forge script --sender $DEPLOYER --rpc-url $PARENT_CHAIN_RPC --broadcast --slow DeployEnableFastConfirmAction -vvv --verify
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```
This would deploy the EnableFastConfirmAction. Update your .env file with the address of the upgrade action.

2. Next step is to execute the action. Upgrade can be executed using `cast` CLI command (part of Foundry installation), using the owner account (the one with executor rights on parent chain UpgradeExecutor) to send the transaction:
```bash
(export $(cat .env | xargs) && cast send $PARENT_UPGRADE_EXECUTOR_ADDRESS "execute(address, bytes)" $UPGRADE_ACTION_ADDRESS $(cast calldata "perform(address, address[], uint256, uint256)" $ROLLUP \[$FAST_CONFIRM_COMMITTEE\] $THRESHOLD $SALT) --rpc-url $PARENT_CHAIN_RPC --account EXECUTOR)
# use --account XXX / --private-key XXX / --interactive / --ledger to set the account to send the transaction from
```

If you have a multisig as executor, you will can use the following command to create the payload for calling into the PARENT_UPGRADE_EXECUTOR:
```bash
(export $(cat .env | xargs) && cast calldata "execute(address, bytes)" $UPGRADE_ACTION_ADDRESS $(cast calldata "perform(address, address[], uint256, uint256)" $ROLLUP \[$FAST_CONFIRM_COMMITTEE\] $THRESHOLD $SALT))
```

3. That's it, the Fast Confirmation has been enabled. Make sure all the committee members are enabling fast confirmation on their nodes and the AnyTrust chain will start using fast confirmation.
