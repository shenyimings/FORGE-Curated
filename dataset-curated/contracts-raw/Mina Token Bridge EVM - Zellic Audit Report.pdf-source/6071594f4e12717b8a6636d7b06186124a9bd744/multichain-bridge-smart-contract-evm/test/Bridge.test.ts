import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Bridge } from "../typechain/Bridge";

import * as BridgeJSON from "../artifacts/contracts/Bridge.sol/Bridge.json";
import { deployContract } from "ethereum-waffle";
import { mintProof } from "./utils/utils";
import { Wallet } from "ethers";

const { loadFixture } = hre.waffle;

describe("Unit tests", () => {
  let admin: Wallet;
  let minter: Wallet;
  let validator1: Wallet;
  let validator2: Wallet;
  let validator3: Wallet;
  let bridge: Bridge;
  let validator4: Wallet;
  const MIN_AMOUNT = ethers.utils.parseEther("0.0001");
  const MAX_AMOUNT = ethers.utils.parseEther("1000000");
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  before(async () => {
    const signers = await (ethers as any).getSigners();
    admin = signers[0];
    minter = signers[1];
    validator1 = signers[2];
    validator2 = signers[3];
    validator3 = signers[4];
    validator4 = signers[5];
  });

  describe("Bridge", () => {
    const fixture = async () => {
      const Bridge = await hre.ethers.getContractFactory("Bridge");
      const bridgeSc = (await deployContract(admin as any, BridgeJSON, [])) as unknown as Bridge;
      await bridgeSc.initialize(
        minter.address,
        MIN_AMOUNT,
        MAX_AMOUNT,
        [validator1.address, validator2.address, validator3.address],
        2
      );
      const newMin = ethers.utils.parseEther("0.00001");
      const newMinMax = ethers.utils.parseEther("10000000");
      await bridgeSc.connect(admin).setMinMaxAmount(newMin, newMinMax);
      await bridgeSc.connect(admin).setWhitelistToken(ZERO_ADDRESS, true);
      return bridgeSc;
    };

    beforeEach(async () => {
      bridge = await loadFixture(fixture);
      console.log("🚀 ~ beforeEach ~ bridge:", bridge.address)
    });

    it("cannot init again", async () => {
      await expect(
        bridge.connect(admin).initialize(
          minter.address,
          MIN_AMOUNT,
          MAX_AMOUNT,
          [validator1.address, validator2.address, validator3.address],
          2
        )
      ).to.be.revertedWith("VM Exception while processing transaction: reverted with reason string 'Initializable: contract is already initialized'");
      
    });
    
    it("can set threshold from admin wallet", async () => {
      const newThreshold = 3;
      await bridge.connect(admin).changeThreshold(newThreshold);
      expect(await bridge.threshold()).to.equal(newThreshold);
    });

    it("cannot set threshold from minter wallet", async () => {
      const newThreshold = 3;
      await expect(
        bridge.connect(minter).changeThreshold(newThreshold)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("can set min and max amount", async () => {
      const newMin = ethers.utils.parseEther("0.00001");
      const newMinMax = ethers.utils.parseEther("10000000");
      await bridge.connect(admin).setMinMaxAmount(newMin, newMinMax);
      expect(await bridge.minAmount()).to.equal(newMin);
      expect(await bridge.maxAmount()).to.equal(newMinMax);
    });

    it("cannot set min and max amount from minter wallet", async () => {
      const newMin = ethers.utils.parseEther("0.00001");
      const newMax = ethers.utils.parseEther("10000000");
      await expect(
        bridge.connect(minter).setMinMaxAmount(newMin, newMax)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("can add validator from admin wallet", async () => {
      const newValidator = validator4.address;
      await bridge.connect(admin).addListValidator([newValidator]);
      expect(await bridge.validators(newValidator)).to.equal(true);
    });

    it("cannot add validator from minter wallet", async () => {
      const newValidator = validator4.address;
      await expect(
        bridge.connect(minter).addListValidator([newValidator])
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("can lock in contract", async () => {
      const lockAmount = ethers.utils.parseEther("1");
      await bridge.connect(admin).lock(ZERO_ADDRESS, admin.address, lockAmount, {value: lockAmount});
      const bridgeBalance = await ethers.provider.getBalance(bridge.address);
      expect(lockAmount).to.equal(bridgeBalance);
    })

    it("cannot lock in contract when not pass value", async () => {
      const lockAmount = ethers.utils.parseEther("1");
      await expect(
        bridge.connect(admin).lock(ZERO_ADDRESS, admin.address, lockAmount)
      ).to.be.revertedWith("VM Exception while processing transaction: reverted with reason string 'Bridge: invalid amount'");
    })

    it("can unlock in contract with validator signature", async () => {
      const token = ZERO_ADDRESS; // Assuming ZERO_ADDRESS is a valid token for this test
      const amount = ethers.utils.parseEther("0.1");
      const user = admin.address;
      const hash = "0x123"; // Assuming this is a valid hash for this test
      const fee = ethers.utils.parseEther("0.01");

      const lockAmount = ethers.utils.parseEther("1");
      await bridge.connect(admin).lock(ZERO_ADDRESS, admin.address, lockAmount, {value: lockAmount});
      const sig1 = await mintProof(
        validator1,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )

      const sig2 = await mintProof(
        validator2,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )

      const sig3 = await mintProof(
        validator3,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )
      const signatures = [sig1, sig2, sig3]; // Assuming validator1 has signed the hash

      await bridge.connect(minter).unlock(token, amount, user, hash, fee, signatures);
      expect(await bridge.unlockHash(hash)).to.equal(true);
    });

    it("cannot unlock in contract with validator signature", async () => {
      const token = ZERO_ADDRESS; // Assuming ZERO_ADDRESS is a valid token for this test
      const amount = ethers.utils.parseEther("0.1");
      const user = admin.address;
      const hash = "0x123"; // Assuming this is a valid hash for this test
      const fee = ethers.utils.parseEther("0.01");

      const lockAmount = ethers.utils.parseEther("1");
      await bridge.connect(admin).lock(ZERO_ADDRESS, admin.address, lockAmount, {value: lockAmount});
      const sig1 = await mintProof(
        validator1,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )

      const sig2 = await mintProof(
        validator2,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )

      const sig3 = await mintProof(
        validator3,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )
      const signatures = [sig1]; // Assuming validator1 has signed the hash

      // await bridge.connect(minter).unlock(token, amount, user, hash, fee, signatures);
      // expect(await bridge.unlockHash(hash)).to.equal(true);

      await expect(
        bridge.connect(minter).unlock(token, amount, user, hash, fee, signatures)
      ).to.be.revertedWith("VM Exception while processing transaction: reverted with reason string 'Signature: Invalid Length'");
    });

    it("cannot unlock in contract with invalid signature", async () => {
      const token = ZERO_ADDRESS; // Assuming ZERO_ADDRESS is a valid token for this test
      const amount = ethers.utils.parseEther("0.1");
      const user = admin.address;
      const hash = "0x123"; // Assuming this is a valid hash for this test
      const hash1 = "0x1234"
      const fee = ethers.utils.parseEther("0.01");

      const lockAmount = ethers.utils.parseEther("1");
      await bridge.connect(admin).lock(ZERO_ADDRESS, admin.address, lockAmount, {value: lockAmount});
      const sig1 = await mintProof(
        validator1,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )

      const sig2 = await mintProof(
        validator2,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )

      const sig3 = await mintProof(
        validator3,
        bridge.address,
        token,
        amount,
        user,
        hash,
        fee
      )
      const signatures = [sig1, sig2, sig3]; // Assuming validator1 has signed the hash

      // await bridge.connect(minter).unlock(token, amount, user, hash, fee, signatures);
      // expect(await bridge.unlockHash(hash)).to.equal(true);

      await expect(
        bridge.connect(minter).unlock(token, amount, user, hash1, fee, signatures)
      ).to.be.revertedWith("VM Exception while processing transaction: reverted with reason string 'Invalid signature'");
    });


  });
});
