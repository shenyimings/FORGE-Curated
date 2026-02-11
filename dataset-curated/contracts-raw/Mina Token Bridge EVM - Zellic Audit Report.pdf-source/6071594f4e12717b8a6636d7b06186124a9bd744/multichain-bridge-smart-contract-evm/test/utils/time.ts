import { ethers } from "hardhat";
import { BigNumber } from "ethers";
async function advanceBlock(): Promise<string> {
  return ethers.provider.send("evm_mine", []);
}
async function advanceBlocks(count: number): Promise<void> {
  const promises = [];
  for (let i = 0; i < count; i++) {
    promises.push(advanceBlock());
  }
  await Promise.all(promises);
}
async function advanceBlockTo(blockNumber: number): Promise<void> {
  for (let i = await ethers.provider.getBlockNumber(); i < blockNumber; i++) {
    await advanceBlock();
  }
}
async function increase(value: BigNumber): Promise<void> {
  await ethers.provider.send("evm_increaseTime", [value.toNumber()]);
  await advanceBlock();
}

async function increaseTo(target: BigNumber): Promise<void> {
  const now = await latest();

  if (target.lt(now))
    throw Error(
      `Cannot increase current time (${now}) to a moment in the past (${target})`,
    );
  const diff = target.sub(now);
  return increase(diff);
}

async function latest(): Promise<BigNumber> {
  const block = await ethers.provider.getBlock("latest");
  return BigNumber.from(block.timestamp);
}
const duration = {
  seconds: function (val: number | string): BigNumber {
    return BigNumber.from(val);
  },
  minutes: function (val: number | string): BigNumber {
    return BigNumber.from(val).mul(this.seconds("60"));
  },
  hours: function (val: number | string): BigNumber {
    return BigNumber.from(val).mul(this.minutes("60"));
  },
  days: function (val: number | string): BigNumber {
    return BigNumber.from(val).mul(this.hours("24"));
  },
  weeks: function (val: number | string): BigNumber {
    return BigNumber.from(val).mul(this.days("7"));
  },
  years: function (val: number | string): BigNumber {
    return BigNumber.from(val).mul(this.days("365"));
  },
};
export {
  advanceBlock,
  advanceBlocks,
  advanceBlockTo,
  increase,
  increaseTo,
  latest,
  duration,
};
