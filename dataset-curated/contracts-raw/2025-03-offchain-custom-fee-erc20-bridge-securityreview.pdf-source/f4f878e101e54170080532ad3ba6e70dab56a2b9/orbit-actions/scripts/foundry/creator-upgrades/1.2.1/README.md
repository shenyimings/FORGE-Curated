# RollupCreator templates upgrade to 1.2.1
This script is used to deploy new 1.2.1 templates (if not already deployed) and then update RollupCreator and Bridge creator to use the new templates.

## How to use it

1. Setup .env according to the example files, make sure you have everything correctly defined. The script do some sanity checks but not everything can be checked. Template addresses should be set to address zero if they're supposed to be deployed. If templates are already deployed, provide the respective addresses.

> [!CAUTION]
> The .env file must be in project root.

2. 
`UpgradeCreatorTemplatesScript.s.sol` script deploys templates if necessary and updates the creators if possible. RollupCreator and BridgeCreator will be updated if `CREATOR_OWNER_IS_MULTISIG` is set to false and wallet running the script is the owner, otherwise the update calldatas will be generated and stored in `${root}/scripts/foundry/creator-upgrades1.2.1/output/${chainId}.json`.

Script can be executed in this directory like this:
```bash
forge script --sender $DEPLOYER --rpc-url $PARENT_CHAIN_RPC --broadcast --slow ./UpgradeCreatorTemplatesScript.s.sol -vvv --verify --skip-simulation
```
