// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

struct Call {
    address target;
    bytes callData;
}

struct CrossChainCall {
    uint256 chainId; // 0 means to be executed on all chains
    address target;
    bytes callData;
}

struct SignedProposal {
    string name;
    bytes32 prevHash;
    CrossChainCall[] calls;
    bytes[] signatures;
}

struct DeployParams {
    bytes32 postfix;
    bytes32 salt;
    bytes constructorParams;
}

struct DeployResult {
    address newContract;
    Call[] onInstallOps;
}

struct MarketFactories {
    address poolFactory;
    address priceOracleFactory;
    address interestRateModelFactory;
    address rateKeeperFactory;
    address lossPolicyFactory;
}

struct PriceFeedInfo {
    address author;
    uint32 stalenessPeriod;
    bytes32 priceFeedType;
    uint256 version;
}

// The `BytecodeInfoMeta` struct holds metadata about a bytecode in BytecodeRepository
//
// - `author`: A person who first upload smart-contract to BCR
// - `contractType`: A bytes32 identifier representing the type of the contract.
// - `version`: A uint256 indicating the version of the contract.
// - `sources`: An array of `Source` structs, each containing a comment and a link related to the contract's source.
// - `auditors`: An array of addresses representing the auditors who have reviewed the contract.
// - `reports`: An array of `SecurityReport` structs, each containing information about security audits conducted on the contract.
struct Bytecode {
    bytes32 contractType;
    uint256 version;
    bytes initCode;
    address author;
    string source;
    bytes authorSignature;
}

struct BytecodePointer {
    bytes32 contractType;
    uint256 version;
    address initCodePointer;
    address author;
    string source;
    bytes authorSignature;
}

struct AuditorSignature {
    string reportUrl;
    address auditor;
    bytes signature;
}

struct Split {
    bool initialized;
    address[] receivers;
    uint16[] proportions;
}

struct TwoAdminProposal {
    bytes callData;
    bool confirmedByAdmin;
    bool confirmedByTreasuryProxy;
}
