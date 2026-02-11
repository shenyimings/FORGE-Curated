// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "./interfaces/IVesting.sol";

/// @title ZEN official ERC-20 smart contract
/// @notice Minting role is granted in the constructor to the Vault Contracts, responsible for
///         restoring EON and Zend balances.

contract ZenToken is ERC20Capped {
    // Simple mapping to track authorized minters
    mapping(address => bool) public minters;

    uint256 internal constant TOTAL_ZEN_SUPPLY = 21_000_000;
    uint256 internal constant TOKEN_SIZE = 10 ** 18;

    address public immutable horizenFoundationVested;
    address public immutable horizenDaoVested;

    uint8 private numOfMinters;

    uint256 public constant DAO_SUPPLY_PERCENTAGE = 60;
    uint256 public constant INITIAL_SUPPLY_PERCENTAGE = 25;

    error AddressParameterCantBeZero(string paramName);
    error CallerNotMinter(address caller);

    modifier canMint() {
        // Checks that the calling account has the minter role
        if (!minters[msg.sender]) {
            revert CallerNotMinter(msg.sender);
        }
        _;
    }

    /// @notice Smart contract constructor
    /// @param tokenName Name of the token
    /// @param tokenSymbol Ticker of the token
    /// @param _eonBackupContract Address of EON Vault contract
    /// @param _zendBackupContract Address of ZEND Vault contract
    /// @param _horizenFoundationVested Address who will receive the remaining portion of Zen reserved to the Foundation (with locking period)
    /// @param _horizenDaoVested Address who will receive the remaining portion of Zen reserved to the DAO (with locking period)
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        address _eonBackupContract,
        address _zendBackupContract,
        address _horizenFoundationVested,
        address _horizenDaoVested
    ) ERC20(tokenName, tokenSymbol) ERC20Capped(TOTAL_ZEN_SUPPLY * TOKEN_SIZE) {
        if (_eonBackupContract == address(0))
            revert AddressParameterCantBeZero("_eonBackupContract");
        if (_zendBackupContract == address(0))
            revert AddressParameterCantBeZero("_zendBackupContract");
        if (_horizenFoundationVested == address(0))
            revert AddressParameterCantBeZero("_horizenFoundationVested");
        if (_horizenDaoVested == address(0))
            revert AddressParameterCantBeZero("_horizenDaoVested");

        // Grant the minter role to a specified account
        minters[_eonBackupContract] = true;
        minters[_zendBackupContract] = true;

        numOfMinters = 2;
        
        horizenFoundationVested = _horizenFoundationVested;
        horizenDaoVested = _horizenDaoVested;
    }

    function mint(address to, uint256 amount) public canMint {
        _mint(to, amount);
    }

    function notifyMintingDone() public canMint {
        minters[msg.sender] = false;
        unchecked {
            --numOfMinters;
        }
        if (numOfMinters == 0) {
            uint256 remainingSupply = cap() - totalSupply();
            //Horizen DAO is eligible of 60% of the remaining supply. The rest is for the Foundation.
            uint256 daoSupply = (remainingSupply * DAO_SUPPLY_PERCENTAGE) / 100;
            uint256 foundationSupply = remainingSupply - daoSupply;

            uint256 daoInitialSupply = (daoSupply * INITIAL_SUPPLY_PERCENTAGE) / 100;
            uint256 foundationInitialSupply = (foundationSupply * INITIAL_SUPPLY_PERCENTAGE) / 100;
            _mint(
                IVesting(horizenFoundationVested).beneficiary(),
                foundationInitialSupply
            );
            _mint(
                horizenFoundationVested,
                foundationSupply - foundationInitialSupply
            );
            _mint(
                IVesting(horizenDaoVested).beneficiary(),
                daoInitialSupply
            );
            _mint(horizenDaoVested, daoSupply - daoInitialSupply);

            IVesting(horizenFoundationVested).startVesting();
            IVesting(horizenDaoVested).startVesting();
        }
    }
}
