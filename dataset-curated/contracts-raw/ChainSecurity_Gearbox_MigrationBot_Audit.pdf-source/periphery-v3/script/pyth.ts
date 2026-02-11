import axios from "axios";
import { ethers } from "ethers";
import { arrayify } from "ethers/lib/utils";

async function getPythPayloadForManualUsage(
  priceFeedId: string,
): Promise<string> {
  const hermes = axios.create({
    baseURL: "https://hermes.pyth.network",
    headers: { accept: "application/json" },
  });

  const feedData = (
    await hermes.get(`v2/updates/price/latest?ids[]=${priceFeedId}`)
  ).data;

  const ts = feedData.parsed[0].price.publish_time;
  const payload = feedData.binary.data;

  const result = ethers.utils.defaultAbiCoder.encode(
    ["uint256", "bytes[]"],
    [ts, [arrayify(`0x${payload}`)]],
  );

  return result;
}

if (process.argv.length !== 3) {
  console.error("Usage: npx node pyth.ts <price-feed-id>");
  process.exit(1);
}

getPythPayloadForManualUsage(process.argv[2])
  .then(payload => {
    console.log(`${payload}`);
  })
  .catch(error => {
    console.error(error);
  });
