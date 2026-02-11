// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Bridge is OwnableUpgradeable, ReentrancyGuardUpgradeable, EIP712Upgradeable {

    bytes32 public constant UNLOCK_HASH = keccak256(
        "UNLOCK(address token,uint256 amount,address user,string hash,uint256 fee)"
    );

    address public minter;
    mapping(address => bool) public whitelistTokens;
    mapping(string => bool) public unlockHash;
    uint256 public maxAmount;
    uint256 public minAmount;
    uint256 public threshold;
    mapping(address => bool) public validators;

    event Lock(address locker, string receipt, address token, uint256 amount, string tokenName);
    event Unlock(address user, address token, uint256 amount, string hash, uint256 fee);
    event ChangeMinter(address minter);
    event ChangeMinAmount(uint256 minAmount);
    event ChangeThreshold(uint256 newThreshold);
    event ChangeMaxAmount(uint256 maxAmount);
    event SetWhitelistToken(address token, bool whitelist);

    modifier onlyMinter() {
        require(minter == msg.sender, "Bridge: Only Minter");
        _;
    }

    function initialize(
        address _minter,
        uint256 _minAmount,
        uint256 _maxAmount,
        address[] memory _validators,
        uint256 _threshold
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __EIP712_init("MinaBridge", "1.0.0");
        minter = _minter;
        minAmount = _minAmount;
        maxAmount = _maxAmount;
        for (uint256 i = 0; i < _validators.length; ++i) {
            validators[_validators[i]] = true;
        }
        threshold = _threshold;
        whitelistTokens[address(0)] = true;
        emit ChangeMinter(minter);
    }

    function isValidThreshold(uint256 totalSig) public view returns (bool) {
        if (totalSig  >= threshold) {
            return true;
        }
        return false;
    }

    function _getSigner(bytes32 _digest, bytes memory _signature) public view returns (address) {
        return ECDSA.recover(_digest, _signature);
    }

    function getUnlockHash(
        address token,
        uint256 amount,
        address user,
        string memory hash,
        uint256 fee
    ) public view returns (bytes32 _unlockHash) {
        _unlockHash = _hashTypedDataV4(keccak256(abi.encode(UNLOCK_HASH, token, amount, user, keccak256(abi.encodePacked(hash)), fee)));
    }

    function _addListValidator(address[] memory _validators) internal {
        require(_validators.length > 0, "Invalid length");
        for (uint256 i = 0; i < _validators.length; i++) {
            validators[_validators[i]] = true;
        }
    }

    function lock(address token, string memory receipt, uint256 amount) public payable {
        require(whitelistTokens[token], "Bridge: token must be in whitelist");
        require(amount <= maxAmount && amount >= minAmount, "Bridge: invalid amount");
        string memory name = "ETH";
        if (token == address(0)) {
            require(msg.value == amount, "Bridge: invalid amount");
        } else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
            name = IERC20(token).name();
        }
        emit Lock(msg.sender, receipt, token, amount, name);
    }


    function unlock(address token, uint256 amount, address user, string memory hash, uint256 fee, bytes[] memory _signatures) public onlyMinter nonReentrant {
        require(whitelistTokens[token], "Bridge: token must be in whitelist");
        require(!unlockHash[hash], "Bridge: Unlocked before");
        require(isValidThreshold(_signatures.length), "Signature: Invalid Length");

        bytes32 _unlockHash = getUnlockHash(token, amount, user, hash, fee);

        address[1000] memory listValidatorsSigned;
        for (uint256 i = 0; i < _signatures.length; i++) {
            bytes memory _signature = _signatures[i];
            address signer = _getSigner(_unlockHash, _signature);
            require(validators[signer], "Invalid signature");
            for (uint256 j = 0; j < listValidatorsSigned.length; j++) {
                if (listValidatorsSigned[j] == signer) {
                    require(false, "Invalid Signature Length");
                }
            }
            listValidatorsSigned[i] = signer;
        }

        unlockHash[hash] = true;
        if (token == address(0)) {
            require(address(this).balance >= amount, "Bridge: invalid amount");
            payable(user).transfer(amount - fee);
            payable(owner()).transfer(fee);

        } else {
            require(IERC20(token).balanceOf(address(this)) >= amount, "Bridge: Invalid amount");
            IERC20(token).transfer(user, amount - fee);
            IERC20(token).transfer(owner(), fee);

        }
        emit Unlock(user, token, amount - fee, hash, fee);
    }

//    ------------ADMIN FUNCTIONS--------------------------------
    function changeMinter(address _minter) public onlyOwner {
        minter = _minter;
        emit ChangeMinter(minter);
    }

    function setWhitelistToken(address token, bool whitelist) public onlyOwner {
        whitelistTokens[token] = whitelist;
        emit SetWhitelistToken(token, whitelist);
    }

    function setMinAmount(uint256 min) public onlyOwner {
        require(min <= maxAmount, "Invalid minAmount");
        minAmount = min;
        emit ChangeMinAmount(minAmount);
    }

    function setMaxAmount(uint256 max) public onlyOwner {
        require(max >= minAmount, "Invalid minAmount");
        maxAmount = max;
        emit ChangeMaxAmount(maxAmount);
    }

    function setMinMaxAmount(uint256 min, uint256 max) public onlyOwner {
        require(max >= min, "Invalid minAmount");
        maxAmount = max;
        minAmount = min;
    }

    function withdrawETH(uint256 amount) public onlyOwner {
        require(address(this).balance >= amount, "Bridge: insufficient balance");
        payable(msg.sender).transfer(amount);
    }

    function changeThreshold(uint256 _newThreshold) external onlyOwner() {
        threshold = _newThreshold;
        emit ChangeThreshold(_newThreshold);
    }

    function addListValidator(address[] memory _validators) external onlyOwner {
        _addListValidator(_validators);
    }
}
