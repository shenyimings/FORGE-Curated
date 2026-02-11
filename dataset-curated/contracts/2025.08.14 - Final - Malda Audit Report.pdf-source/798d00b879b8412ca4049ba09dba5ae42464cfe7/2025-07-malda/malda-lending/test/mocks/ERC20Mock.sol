// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IPohVerifier} from "src/interfaces/external/poh/IPohVerifier.sol";

contract ERC20Mock is ERC20 {
    uint8 private _d;

    address public admin;
    address public pohVerify;
    bool public onlyVerified;
    mapping(address => uint256) public minted;

    uint256 public mintLimit;

    error ERC20Mock_AlreadyMinted();
    error ERC20Mock_NotAuthorized();
    error ERC20Mock_OnlyVerified();
    error ERC20Mock_PohFailed();
    error ERC20Mock_TooMuch();

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _owner,
        address _pohVerify,
        uint256 _limit
    ) ERC20(_name, _symbol) {
        _d = _decimals;
        admin = _owner;
        pohVerify = _pohVerify;

        mintLimit = _limit == 0 ? 1000 * (10 ** _d) : _limit;
    }

    /// @dev onlyAdmin
    function setOnlyVerify(bool status) external {
        require(msg.sender == admin, ERC20Mock_NotAuthorized());
        onlyVerified = status;
    }

    function setMintLimit(uint256 _limit) external {
        require(msg.sender == admin, ERC20Mock_NotAuthorized());
        mintLimit = _limit;
    }

    /// @dev view
    function decimals() public view override returns (uint8) {
        return _d;
    }

    /// @dev mint up to `mintLimit` using a proof of humanity verification
    function mint(address _to, uint256 _amount, bytes memory signature) external {
        require(minted[_to] + _amount < mintLimit, ERC20Mock_AlreadyMinted());
        bool verified = IPohVerifier(pohVerify).verify(signature, msg.sender);
        require(verified, ERC20Mock_PohFailed());
        minted[_to] += _amount;
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    /// @dev public
    /// @dev mint up to `mintLimit` when `onlyVerified == false`
    function mint(address _to, uint256 _amount) external {
        require(!onlyVerified, ERC20Mock_OnlyVerified());
        require(minted[_to] + _amount < mintLimit, ERC20Mock_AlreadyMinted());
        minted[_to] += _amount;
        _mint(_to, _amount);
    }

    /// @dev public
    /// @dev burn does not reset `minted`
    function burn(uint256 _amount) external {
        require(minted[msg.sender] >= _amount, ERC20Mock_TooMuch());
        //minted[msg.sender] -= _amount;
        _burn(msg.sender, _amount);
    }

    /// @dev public
    /// @dev burn does not reset `minted`
    function burn(address _from, uint256 _amount) external {
        require(msg.sender == admin, ERC20Mock_NotAuthorized());
        require(minted[_from] >= _amount, ERC20Mock_TooMuch());
        //minted[_from] -= _amount;
        _burn(_from, _amount);
    }
}
