// Copyright 2025 cbe
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// hardhat.config.js or a separate script
import fs from "fs";
import { task } from "hardhat/config";
import path from "path";

const ABI_SUFFIX = "Abi";

function toAbiName(contractName: string) {
  return `${contractName}${ABI_SUFFIX}`;
}

function writeAbiToTs(abi: string, contractName: string, destPath: string) {
  const tsData = `export const ${toAbiName(contractName)} = ${JSON.stringify(abi, null, 2)} as const;`;
  const tsPath = path.join(destPath, `${contractName}.ts`);
  fs.writeFileSync(tsPath, tsData);
}

function getAbi(contractPath: string, contractName: string) {
  const contractFilePath = path.join(__dirname, "..", "artifacts-zk", `src${contractPath}`, `${contractName}.sol`, `${contractName}.json`);
  const contract = JSON.parse(fs.readFileSync(contractFilePath).toString());
  return contract.abi;
}

function copyContractAbiToTsPath(contractPath: string, contractName: string, destPath: string) {
  const factoryAbi = getAbi(contractPath, contractName);
  writeAbiToTs(factoryAbi, contractName, destPath);
  return contractName;
}

function createIndex(destPath: string, contractNames: string[]) {
  const exportLines = contractNames.map((contractName) => `export { ${toAbiName(contractName)} } from "./${contractName}.js";`);
  fs.writeFileSync(path.join(destPath, "index.ts"), exportLines.join("\n") + "\n");
}

task("publish", "copies abi to a typescript file")
  .addPositionalParam("destPath", "where to write the abi files (relative to the contract project root)")
  .setAction(async (cmd) => {
    createIndex(cmd.destPath, [
      copyContractAbiToTsPath("", "AAFactory", cmd.destPath),
      copyContractAbiToTsPath("/validators", "SessionKeyValidator", cmd.destPath),
      copyContractAbiToTsPath("/validators", "WebAuthValidator", cmd.destPath),
    ]);
  });
