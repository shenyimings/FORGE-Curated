// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ClaimVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable ZBT;
    uint256 public immutable startClaimTimestamp;
    address public signer;

    mapping(address user => uint256 nonce) public userNonce;

    uint256 public epochDuration = 1 hours;
    uint256 public globalCapPerEpoch = 100_000 ether;
    uint256 public userCapPerEpoch = 50_000 ether;

    mapping(uint256 epochDuration => mapping(uint256 epochId => uint256 claimedAmount))
        public claimedByEpoch;
    mapping(uint256 epochDuration => mapping(address user => mapping(uint256 epochId => uint256 claimedAmount)))
        public userClaimedByEpoch;

    event Claimed(
        address indexed user,
        uint256 indexed amount,
        uint256 indexed epochId,
        uint256 currentEpochDuration,
        uint256 userNonce
    );
    event EmergencyWithdrawal(
        address indexed _token,
        address indexed _receiver
    );
    event UpdateSigner(address indexed oldSigner, address indexed newSigner);
    event UpdateEpochConfig(
        uint256 indexed epochDuration,
        uint256 globalCapPerEpoch,
        uint256 userCapPerEpoch
    );

    constructor(address _ZBT, address _signer) Ownable(msg.sender) {
        ZBT = IERC20(_ZBT);
        signer = _signer;
        startClaimTimestamp = block.timestamp;
    }

    function Claim(
        address user,
        uint256 claimAmount,
        uint256 expiry,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        require(claimAmount != 0, "Zero ZBT number");
        require(user == msg.sender, "Invalid sender");
        require(expiry > block.timestamp, "Signature expired");

        uint256 currentUserNonce = userNonce[msg.sender];

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        bytes32 claimDigestHash = calculateClaimZBTHash(
            msg.sender,
            claimAmount,
            currentUserNonce,
            chainId,
            expiry
        );

        require(
            _checkSignature(claimDigestHash, signature),
            "Invalid signature"
        );
        unchecked {
            userNonce[msg.sender] = currentUserNonce + 1;
        }

        uint256 epochId = currentEpochId();

        uint256 globalUsed = claimedByEpoch[epochDuration][epochId];
        require(
            globalUsed + claimAmount <= globalCapPerEpoch,
            "Global cap exceeded"
        );

        uint256 userUsed = userClaimedByEpoch[epochDuration][msg.sender][
            epochId
        ];
        require(userUsed + claimAmount <= userCapPerEpoch, "User cap exceeded");

        require(
            ZBT.balanceOf(address(this)) >= claimAmount,
            "Insufficient Balance"
        );

        unchecked {
            claimedByEpoch[epochDuration][epochId] = globalUsed + claimAmount;
            userClaimedByEpoch[epochDuration][msg.sender][epochId] =
                userUsed +
                claimAmount;
        }

        ZBT.safeTransfer(msg.sender, claimAmount);
        emit Claimed(msg.sender, claimAmount, epochId, epochDuration , currentUserNonce);
    }

    function currentEpochId() public view returns (uint256) {
        return (block.timestamp - startClaimTimestamp) / epochDuration;
    }

    function calculateClaimZBTHash(
        address _user,
        uint256 _claimAmount,
        uint256 _userNonce,
        uint256 _chainid,
        uint256 _expiry
    ) public pure returns (bytes32) {
        bytes32 userClaimZBTStructHash = keccak256(
            abi.encode(_user, _claimAmount, _userNonce, _chainid, _expiry)
        );
        return MessageHashUtils.toEthSignedMessageHash(userClaimZBTStructHash);
    }

    function _checkSignature(
        bytes32 digestHash,
        bytes memory signature
    ) internal view returns (bool result) {
        address recovered = ECDSA.recover(digestHash, signature);
        result = recovered == signer;
    }

    function emergencyWithdraw(
        address _token,
        address _receiver
    ) external onlyOwner {
        require(_token != address(0), "Token must not be zero");
        require(_receiver != address(0), "Receiver must not be zero");

        IERC20(_token).safeTransfer(
            _receiver,
            IERC20(_token).balanceOf(address(this))
        );
        emit EmergencyWithdrawal(_token, _receiver);
    }

    function setSigner(address _newSigner) external onlyOwner {
        require(_newSigner != address(0), "Signer must not be zero");
        address oldSigner = signer;
        signer = _newSigner;
        emit UpdateSigner(oldSigner, _newSigner);
    }

    function setEpochConfig(
        uint256 _epochDuration,
        uint256 _globalCapPerEpoch,
        uint256 _userCapPerEpoch
    ) external onlyOwner {
        require(_epochDuration > 0, "epochDuration can not be zero");
        require(
            _globalCapPerEpoch > 0,
            "globalCapPerEpoch must greater than zero"
        );
        require(
            _userCapPerEpoch > 0 && _userCapPerEpoch <= _globalCapPerEpoch,
            "_userCapPerEpoch must greater than zero and less than _globalCapPerEpoch"
        );
        epochDuration = _epochDuration;
        globalCapPerEpoch = _globalCapPerEpoch;
        userCapPerEpoch = _userCapPerEpoch;
        emit UpdateEpochConfig(
            _epochDuration,
            _globalCapPerEpoch,
            _userCapPerEpoch
        );
    }

    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }
}
