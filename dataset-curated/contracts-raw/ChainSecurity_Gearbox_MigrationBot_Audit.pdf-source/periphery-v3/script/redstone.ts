import { DataServiceWrapper } from "@redstone-finance/evm-connector/dist/src/wrappers/DataServiceWrapper";
import { ethers } from "ethers";
import { arrayify } from "ethers/lib/utils";
import { RedstonePayloadParser } from "redstone-protocol/dist/src/redstone-payload/RedstonePayloadParser";

async function getRedstonePayloadForManualUsage(
  dataServiceId: string,
  dataFeed: string,
  signersCount: number,
): Promise<string> {
  // REDSTONE_GATEWAYS env variable can be used to provide local caching proxies that prevent rate limiting
  // it's passed when attach tests are executed on testnets
  const gateways = process.env.REDSTONE_GATEWAYS
    ? process.env.REDSTONE_GATEWAYS.split(",")
    : undefined;
  const dataPayload = await new DataServiceWrapper({
    dataServiceId,
    dataFeeds: [dataFeed === "STETH" ? "stETH" : dataFeed],
    uniqueSignersCount: signersCount,
    urls: gateways,
  }).prepareRedstonePayload(true);

  const parser = new RedstonePayloadParser(arrayify(`0x${dataPayload}`));
  const { signedDataPackages } = parser.parse();

  let dataPackageIndex = 0;
  let ts = 0;
  for (const signedDataPackage of signedDataPackages) {
    const newTimestamp =
      signedDataPackage.dataPackage.timestampMilliseconds / 1000;

    if (dataPackageIndex === 0) {
      ts = newTimestamp;
    } else if (ts !== newTimestamp) {
      throw new Error("Timestamps are not equal");
    }

    ++dataPackageIndex;
  }

  const result = ethers.utils.defaultAbiCoder.encode(
    ["uint256", "bytes"],
    [ts, arrayify(`0x${dataPayload}`)],
  );

  return result;
}

if (process.argv.length !== 5) {
  console.error(
    "Usage: npx node redstone.ts  <data-service-id> <data-feed-id> <num-signers>",
  );
  process.exit(1);
}

getRedstonePayloadForManualUsage(
  process.argv[2],
  process.argv[3],
  Number(process.argv[4]),
)
  .then(payload => {
    console.log(`${payload}`);
  })
  .catch(error => {
    console.error(error);
  });
