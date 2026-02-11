import { BytesLike, ethers } from "ethers";
import web3 from "web3";
import { ethers as hardhat } from "hardhat";
import { Wallet } from "ethers";

const CHAIN_ID = 31337;
export const SIGNER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;

export const sleep = async (milisec: number): Promise<void> => {
  return new Promise(resolve => setTimeout(resolve, milisec));
};

export const wei = ethers.utils.parseEther;

// UNLOCK(address token,uint256 amount,address user,string hash,uint256 fee)
export const mintProof = async (
  wallet: Wallet,
  contractAddress: string,
  token: string,
  amount: ethers.BigNumber,
  user: string,
  hash: string,
  fee: ethers.BigNumber,
): Promise<string> => {
  const signature = await wallet._signTypedData(
    // Domain
    {
      name: "MinaBridge",
      version: "1.0.0",
      chainId: CHAIN_ID,
      verifyingContract: contractAddress,
    },
    {
      UNLOCK: [
        { name: "token", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "user", type: "address" },
        { name: "hash", type: "string" },
        { name: "fee", type: "uint256" },
      ],
    },
    {
     token,
     amount,
     user,
     hash,
     fee,
    },
  );

  return signature;
};
