// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

enum MsgType {
  //=========== NOTE: Asset ===========//
  MsgInitializeAsset,
  MsgDeposit,
  MsgDepositWithSupplyVLF,
  __Deprecated_MsgDepositWithSupplyEOL,
  MsgWithdraw,
  //=========== NOTE: VLF ===========//
  MsgInitializeVLF,
  MsgAllocateVLF,
  MsgDeallocateVLF,
  MsgSettleVLFYield,
  MsgSettleVLFLoss,
  MsgSettleVLFExtraRewards,
  __Deprecated_MsgInitializeEOL,
  //=========== NOTE: MITOGovernance ===========//
  MsgDispatchGovernanceExecution
}

// hub -> branch
struct MsgInitializeAsset {
  bytes32 asset;
}

// branch -> hub
struct MsgDeposit {
  bytes32 asset;
  bytes32 to;
  uint256 amount;
}

// branch -> hub
struct MsgDepositWithSupplyVLF {
  bytes32 asset;
  bytes32 to;
  bytes32 vlfVault;
  uint256 amount;
}

// hub -> branch
struct MsgWithdraw {
  bytes32 asset;
  bytes32 to;
  uint256 amount;
}

// hub -> branch
struct MsgInitializeVLF {
  bytes32 vlfVault;
  bytes32 asset;
}

// hub -> branch
struct MsgAllocateVLF {
  bytes32 vlfVault;
  uint256 amount;
}

// branch -> hub
struct MsgDeallocateVLF {
  bytes32 vlfVault;
  uint256 amount;
}

// branch -> hub
struct MsgSettleVLFYield {
  bytes32 vlfVault;
  uint256 amount;
}

// branch -> hub
struct MsgSettleVLFLoss {
  bytes32 vlfVault;
  uint256 amount;
}

// branch -> hub
struct MsgSettleVLFExtraRewards {
  bytes32 vlfVault;
  bytes32 reward;
  uint256 amount;
}

// hub -> branch
struct MsgDispatchGovernanceExecution {
  bytes32[] targets;
  uint256[] values;
  bytes[] data;
  bytes32 predecessor;
  bytes32 salt;
}

library Message {
  error Message__InvalidMsgType(MsgType actual, MsgType expected);
  error Message__InvalidMsgLength(uint256 actual, uint256 expected);

  uint256 public constant LEN_MSG_INITIALIZE_ASSET = 33;
  uint256 public constant LEN_MSG_DEPOSIT = 97;
  uint256 public constant LEN_MSG_DEPOSIT_WITH_SUPPLY_VLF = 129;
  uint256 public constant LEN_MSG_WITHDRAW = 97;
  uint256 public constant LEN_MSG_INITIALIZE_VLF = 65;
  uint256 public constant LEN_MSG_ALLOCATE_VLF = 65;
  uint256 public constant LEN_MSG_DEALLOCATE_VLF = 65;
  uint256 public constant LEN_MSG_SETTLE_VLF_YIELD = 65;
  uint256 public constant LEN_MSG_SETTLE_VLF_LOSS = 65;
  uint256 public constant LEN_MSG_SETTLE_VLF_EXTRA_REWARDS = 97;

  function msgType(bytes calldata msg_) internal pure returns (MsgType) {
    return MsgType(uint8(msg_[0]));
  }

  function assertMsg(bytes calldata msg_, MsgType expectedType, uint256 expectedLen) internal pure {
    require(msgType(msg_) == expectedType, Message__InvalidMsgType(msgType(msg_), expectedType));
    require(msg_.length == expectedLen, Message__InvalidMsgLength(msg_.length, expectedLen));
  }

  function encode(MsgInitializeAsset memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgInitializeAsset), msg_.asset);
  }

  function decodeInitializeAsset(bytes calldata msg_) internal pure returns (MsgInitializeAsset memory decoded) {
    assertMsg(msg_, MsgType.MsgInitializeAsset, LEN_MSG_INITIALIZE_ASSET);

    decoded.asset = bytes32(msg_[1:]);
  }

  function encode(MsgDeposit memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgDeposit), msg_.asset, msg_.to, msg_.amount);
  }

  function decodeDeposit(bytes calldata msg_) internal pure returns (MsgDeposit memory decoded) {
    assertMsg(msg_, MsgType.MsgDeposit, LEN_MSG_DEPOSIT);

    decoded.asset = bytes32(msg_[1:33]);
    decoded.to = bytes32(msg_[33:65]);
    decoded.amount = uint256(bytes32(msg_[65:]));
  }

  function encode(MsgDepositWithSupplyVLF memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgDepositWithSupplyVLF), msg_.asset, msg_.to, msg_.vlfVault, msg_.amount);
  }

  function decodeDepositWithSupplyVLF(bytes calldata msg_)
    internal
    pure
    returns (MsgDepositWithSupplyVLF memory decoded)
  {
    assertMsg(msg_, MsgType.MsgDepositWithSupplyVLF, LEN_MSG_DEPOSIT_WITH_SUPPLY_VLF);

    decoded.asset = bytes32(msg_[1:33]);
    decoded.to = bytes32(msg_[33:65]);
    decoded.vlfVault = bytes32(msg_[65:97]);
    decoded.amount = uint256(bytes32(msg_[97:]));
  }

  function encode(MsgWithdraw memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgWithdraw), msg_.asset, msg_.to, msg_.amount);
  }

  function decodeWithdraw(bytes calldata msg_) internal pure returns (MsgWithdraw memory decoded) {
    assertMsg(msg_, MsgType.MsgWithdraw, LEN_MSG_WITHDRAW);

    decoded.asset = bytes32(msg_[1:33]);
    decoded.to = bytes32(msg_[33:65]);
    decoded.amount = uint256(bytes32(msg_[65:]));
  }

  function encode(MsgInitializeVLF memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgInitializeVLF), msg_.vlfVault, msg_.asset);
  }

  function decodeInitializeVLF(bytes calldata msg_) internal pure returns (MsgInitializeVLF memory decoded) {
    assertMsg(msg_, MsgType.MsgInitializeVLF, LEN_MSG_INITIALIZE_VLF);

    decoded.vlfVault = bytes32(msg_[1:33]);
    decoded.asset = bytes32(msg_[33:]);
  }

  function encode(MsgAllocateVLF memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgAllocateVLF), msg_.vlfVault, msg_.amount);
  }

  function decodeAllocateVLF(bytes calldata msg_) internal pure returns (MsgAllocateVLF memory decoded) {
    assertMsg(msg_, MsgType.MsgAllocateVLF, LEN_MSG_ALLOCATE_VLF);

    decoded.vlfVault = bytes32(msg_[1:33]);
    decoded.amount = uint256(bytes32(msg_[33:]));
  }

  function encode(MsgDeallocateVLF memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgDeallocateVLF), msg_.vlfVault, msg_.amount);
  }

  function decodeDeallocateVLF(bytes calldata msg_) internal pure returns (MsgDeallocateVLF memory decoded) {
    assertMsg(msg_, MsgType.MsgDeallocateVLF, LEN_MSG_DEALLOCATE_VLF);

    decoded.vlfVault = bytes32(msg_[1:33]);
    decoded.amount = uint256(bytes32(msg_[33:]));
  }

  function encode(MsgSettleVLFYield memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgSettleVLFYield), msg_.vlfVault, msg_.amount);
  }

  function decodeSettleVLFYield(bytes calldata msg_) internal pure returns (MsgSettleVLFYield memory decoded) {
    assertMsg(msg_, MsgType.MsgSettleVLFYield, LEN_MSG_SETTLE_VLF_YIELD);

    decoded.vlfVault = bytes32(msg_[1:33]);
    decoded.amount = uint256(bytes32(msg_[33:]));
  }

  function encode(MsgSettleVLFLoss memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgSettleVLFLoss), msg_.vlfVault, msg_.amount);
  }

  function decodeSettleVLFLoss(bytes calldata msg_) internal pure returns (MsgSettleVLFLoss memory decoded) {
    assertMsg(msg_, MsgType.MsgSettleVLFLoss, LEN_MSG_SETTLE_VLF_LOSS);

    decoded.vlfVault = bytes32(msg_[1:33]);
    decoded.amount = uint256(bytes32(msg_[33:]));
  }

  function encode(MsgSettleVLFExtraRewards memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgSettleVLFExtraRewards), msg_.vlfVault, msg_.reward, msg_.amount);
  }

  function decodeSettleVLFExtraRewards(bytes calldata msg_)
    internal
    pure
    returns (MsgSettleVLFExtraRewards memory decoded)
  {
    assertMsg(msg_, MsgType.MsgSettleVLFExtraRewards, LEN_MSG_SETTLE_VLF_EXTRA_REWARDS);

    decoded.vlfVault = bytes32(msg_[1:33]);
    decoded.reward = bytes32(msg_[33:65]);
    decoded.amount = uint256(bytes32(msg_[65:]));
  }

  function encode(MsgDispatchGovernanceExecution memory msg_) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(MsgType.MsgDispatchGovernanceExecution), (abi.encode(msg_)));
  }

  function decodeDispatchGovernanceExecution(bytes calldata msg_)
    internal
    pure
    returns (MsgDispatchGovernanceExecution memory decoded)
  {
    require(
      msgType(msg_) == MsgType.MsgDispatchGovernanceExecution,
      Message__InvalidMsgType(msgType(msg_), MsgType.MsgDispatchGovernanceExecution)
    );
    decoded = abi.decode(msg_[1:], (MsgDispatchGovernanceExecution));
  }
}
