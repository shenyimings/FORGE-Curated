// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../automators/bases/RCHAutomatorBase.sol";

contract RCHAutomatorFactory is Ownable {
    address public referral;
    address public feeCollector;
    address public immutable automator;
    mapping(address => bool) public vaults;
    mapping(address => bool) public makers;

    address[] public automators;
    mapping(address => uint256) public credits;
    mapping(address => mapping(address => address)) public getAutomator;

    event ReferralSet(address oldReferral, address newReferral);
    event FeeCollectorSet(address oldFeeCollector, address newFeeCollector);
    event AutomatorCreated(address indexed creator, address indexed collateral, address automator, uint256 feeRate, uint256 maxPeriod);
    event VaultsEnabled(address[] vaults);
    event VaultsDisabled(address[] vaults);
    event MakersEnabled(address[] makers);
    event MakersDisabled(address[] makers);
    event CreditsTopUp(address indexed user, uint256 amount);

    constructor(address referral_, address feeCollector_, address zenRCH_) {
        referral = referral_;
        feeCollector = feeCollector_;
        automator = address(new RCHAutomatorBase(zenRCH_));
    }

    function createAutomator(
        uint256 feeRate,
        uint256 maxPeriod,
        address collateral
    ) external returns (address) {
        require(credits[_msgSender()] > 0, "AutomatorFactory: insufficient credits");
        credits[_msgSender()] -= 1;
        bytes32 salt = keccak256(abi.encodePacked(_msgSender(), collateral));
        address _automator = Clones.cloneDeterministic(automator, salt);
        RCHAutomatorBase(_automator).initialize(_msgSender(), collateral, feeRate, maxPeriod);
        require(getAutomator[_msgSender()][collateral] == address(0), "AutomatorFactory: automator already exists");
        getAutomator[_msgSender()][collateral] = _automator;
        automators.push(_automator);
        emit AutomatorCreated(_msgSender(), collateral, _automator, feeRate, maxPeriod);
        return _automator;
    }

    function automatorsLength() external view returns (uint256) {
        return automators.length;
    }

    function setReferral(address referral_) external onlyOwner {
        require(referral_ != address(0), "AutomatorFactory: referral is the zero address");
        emit ReferralSet(referral, referral_);
        referral = referral_;
    }

    function setFeeCollector(address feeCollector_) external onlyOwner {
        require(feeCollector_ != address(0), "AutomatorFactory: feeCollector is the zero address");
        emit FeeCollectorSet(feeCollector, feeCollector_);
        feeCollector = feeCollector_;
    }

    function topUp(address user, uint256 amount) external onlyOwner {
        credits[user] += amount;
        emit CreditsTopUp(user, amount);
    }

    function enableVaults(address[] calldata vaults_) external onlyOwner {
        for (uint256 i = 0; i < vaults_.length; i++) {
            vaults[vaults_[i]] = true;
        }
        emit VaultsEnabled(vaults_);
    }

    function disableVaults(address[] calldata vaults_) external onlyOwner {
        for (uint256 i = 0; i < vaults_.length; i++) {
            vaults[vaults_[i]] = false;
        }
        emit VaultsDisabled(vaults_);
    }

    function enableMakers(address[] calldata makers_) external onlyOwner {
        for (uint256 i = 0; i < makers_.length; i++) {
            makers[makers_[i]] = true;
        }
        emit MakersEnabled(makers_);
    }

    function disableMakers(address[] calldata makers_) external onlyOwner {
        for (uint256 i = 0; i < makers_.length; i++) {
            makers[makers_[i]] = false;
        }
        emit MakersDisabled(makers_);
    }
}
