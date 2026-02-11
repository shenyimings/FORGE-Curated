import { expect } from "chai";
import { readdirSync, readFileSync } from "fs";
import { describe } from "mocha";
import { join } from "path";

import { JSONParserLibTest, JSONParserLibTest__factory } from "../typechain-types";
import { create2, ethersStaticSalt, getWallet, LOCAL_RICH_WALLETS } from "./utils";

const SKIPPED = [
  "n_string_unescaped_ctrl_char.json",
  "n_string_unescaped_newline.json",
  "n_string_unescaped_tab.json",
];

describe("JSONParserLib tests", function () {
  let jsonLibTester: JSONParserLibTest;
  const wallet = getWallet(LOCAL_RICH_WALLETS[0].privateKey);

  async function deployParser(): Promise<JSONParserLibTest> {
    const jsonLib = await create2("JSONParserLibTest", wallet, ethersStaticSalt, []);
    return JSONParserLibTest__factory.connect(await jsonLib.getAddress(), wallet);
  }

  describe("file parsing", () => {
    const jsonDir = join("test", "json-files");

    before(async () => {
      jsonLibTester = await deployParser();
    });

    function generateTestCase(filename: string) {
      return async () => {
        const testFile = readFileSync(join(jsonDir, filename), "utf-8");

        if (filename.startsWith("y_")) {
          await expect(jsonLibTester.parse(testFile)).to.not.be.reverted;
        } else if (filename.startsWith("n_")) {
          await expect(jsonLibTester.parse(testFile)).to.be.reverted;
        } else {
          expect(false, `File ${filename} should start with 'y_' or 'n_'`);
        }
      };
    }

    const jsonFiles = readdirSync(jsonDir);
    jsonFiles.forEach((filename) => {
      (SKIPPED.includes(filename) ? it.skip : it)(filename, generateTestCase(filename));
    });
  });
});
