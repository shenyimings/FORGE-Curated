import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ABI } from "./abi";

const impersonateAddress = async (address: string, hre: HardhatRuntimeEnvironment) => {
  const { ethers } = hre;
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  const signer = await ethers.getSigner(address);
  // signer.address = signer._address;
  return signer;
};
// Function to increase time in mainnet fork
async function increaseTime(value: any, hre: HardhatRuntimeEnvironment) {
  const { ethers } = hre;
  if (!ethers.BigNumber.isBigNumber(value)) {
    value = ethers.BigNumber.from(value);
  }
  await ethers.provider.send("evm_increaseTime", [value.toNumber()]);
  await ethers.provider.send("evm_mine", []);
}

task("test-fork", "Test fork hardhat", async function (_taskArgs, _hre) {
  const { ethers } = _hre;
  const contractAddress = "0xe2e17b2CBbf48211FA7eB8A875360e5e39bA2602";
  const address = "0xE39997154b574Ce35cb2c61410a0549261D8829d";
  const receiverAddress = "0xE39997154b574Ce35cb2c61410a0549261D8829d";
  const strikeAddress = "0x74232704659ef37c08995e386A2E26cc27a8d7B1";
  const faker = await impersonateAddress(address, _hre);
  const rich = await impersonateAddress("0xCFFAd3200574698b78f32232aa9D63eABD290703", _hre);

  const txTransfer = {
    to: faker.address,
    // Convert currency unit from ether to wei
    value: ethers.utils.parseEther("10"),
  };
  // Send a transaction
  const txEx = await rich.sendTransaction(txTransfer);
  await txEx.wait();

  const contract = await new ethers.Contract(contractAddress, ABI, faker);
  const updateRwTx = await contract.updateContributorRewards(receiverAddress);
  await updateRwTx.wait();
  const claimTx = await contract.claimStrike(receiverAddress);
  await claimTx.wait();

  const ercABI = [
    // Read-Only Functions
    "function balanceOf(address owner) view returns (uint256)",
  ];

  const strikeToken = await new ethers.Contract(strikeAddress, ercABI, faker);
  const balance = await strikeToken.balanceOf(faker.address);
  console.log(balance.toString());

  console.log("\x1b[36m%s\x1b[0m", "done");
});
