import { GearboxSDK } from "@gearbox-protocol/sdk";
import addresses from "../addresses.json";

// Constants
const RPC_URL = "http://localhost:8545";
const ADDRESS_PROVIDER = addresses.addressProvider;
// You'll need to provide the market configurator address
const MARKET_CONFIGURATOR =  "0x67b900f24357e3e0b7b481b2852170955ff52221";

async function main() {
  try {
    const sdk = await GearboxSDK.attach({
      rpcURLs: [RPC_URL],
      addressProvider: ADDRESS_PROVIDER as `0x${string}`,
      marketConfigurators: [MARKET_CONFIGURATOR],
    });

    console.log(sdk.stateHuman);
  } catch (error) {
    console.error("Error:", error);
  }
}

// Execute the main function
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
