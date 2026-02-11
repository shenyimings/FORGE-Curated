// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Contracts
import { Ownable2Step } from "@openzeppelin/access/Ownable2Step.sol";
/* solhint-disable no-unused-import */
import { Ownable } from "@openzeppelin/access/Ownable.sol";
/* solhint-enable no-unused-import */
import { Tea } from "./Tea.sol";

/// @title MintManager
/// @notice Set as `owner` of the governance token and responsible for the token inflation
///         schedule. Contract acts as the token "mint manager" with permission to the `mint`
///         function only. Currently permitted to mint once per year of up to 2% of the total
///         token supply. Upgradable to allow changes in the inflation schedule.
/// @notice forked from
///         https://github.com/ethereum-optimism/optimism/blob/d356d92a33aa623e30e1e11435ec0c02da69d718/packages/contracts-bedrock/src/governance/MintManager.sol
///         Modifications include Ownable2Step, no minting within first year, and using the TeaToken interface.
contract MintManager is Ownable2Step {
    /// @notice The TeaToken that the MintManager can mint tokens
    Tea public immutable tea;

    /// @notice The amount of tokens that can be minted per year.
    ///         The value is a fixed point number with 3 decimals.
    uint256 public constant MINT_CAP = 20; // 2%

    /// @notice The number of decimals for the MINT_CAP.
    uint256 public constant DENOMINATOR = 1000;

    /// @notice The amount of time that must pass before the MINT_CAP number of tokens can
    ///         be minted again.
    uint256 public constant MINT_PERIOD = 365 days;

    /// @notice Tracks the time of last mint.
    uint256 public mintPermittedAfter;

    /// @notice Constructs the MintManager contract.
    /// @param _owner        The owner of this contract.
    /// @param _governanceToken The governance token this contract can mint tokens of.
    constructor(address _owner, address payable _governanceToken) Ownable(_owner) {
        tea = Tea(payable(_governanceToken));

        // No minting within first year.
        mintPermittedAfter = block.timestamp + MINT_PERIOD;

        tea.acceptOwnership();
    }

    /// @notice Only the token owner is allowed to mint a certain amount of the
    ///         governance token per year.
    /// @param _account The account receiving minted tokens.
    /// @param _amount  The amount of tokens to mint.
    function mintTo(address _account, uint256 _amount) external onlyOwner {
        require(mintPermittedAfter <= block.timestamp, "MintManager: minting not permitted yet");
        require(_amount <= (tea.totalSupply() * MINT_CAP) / DENOMINATOR, "MintManager: mint amount exceeds cap");

        mintPermittedAfter = block.timestamp + MINT_PERIOD;
        tea.mintTo(_account, _amount);
    }

    /// @notice Upgrade the owner of the governance token to a new MintManager.
    /// @param _newMintManager The MintManager to upgrade to.
    function upgrade(address _newMintManager) external onlyOwner {
        require(_newMintManager != address(0), "MintManager: mint manager cannot be the zero address");

        tea.transferOwnership(_newMintManager);
    }
}
