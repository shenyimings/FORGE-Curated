// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract USDKG is IERC20 {

    string public name;
    string public symbol;
    uint256 public decimals;

    // ownable
    address public owner;
    address public compliance;

    // ERC20 Basic
    uint256 public _totalSupply;
    mapping(address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowed;

    uint256 public constant MAX_BASIS_POINTS = 20;
    uint256 public constant FEE_PRECISION = 10000;

    // variables to manage optional transaction fees, if such functionality is enabled in the future
    uint256 public basisPointsRate = 0;

    // pausable
    bool public paused = false;

    // blacklist
    mapping (address => bool) public isBlackListed;

    event Pause();
    event Unpause();
    event DestroyedBlackFunds(address _blackListedUser, uint256 _balance);
    event AddedBlackList(address _user);
    event RemovedBlackList(address _user);
    // called when new token are issued
    event Issue(uint256 amount);
    // called when tokens are redeemed
    event Redeem(uint256 amount);
    // called if contract ever adds fees
    event Params(uint256 feeBasisPoints);

    constructor (address _owner, address _compliance) {
        owner = _owner;
        compliance = _compliance;
        _totalSupply = 0;
        name = "USDKG";
        symbol = "USDKG";
        decimals = 6;
    }

    /**
      * @dev Throws if called by any account other than the owner.
      */
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /**
      * @dev Throws if called by any account other than the owner.
      */
    modifier onlyCompliance() {
        require(msg.sender == compliance, "not compliance");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused, "not paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when sender is not blacklisted.
     */
    modifier notBlackListed(address sender) {
        require(!isBlackListed[sender], "user blacklisted");
        _;
    }

    ////////////////////////
    // PUBLIC FUNCTIONS
    ////////////////////////

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to
    * @param _value The amount to be transferred
    */
    function transfer(address _to, uint256 _value) public whenNotPaused notBlackListed(msg.sender) returns (bool) {
        uint256 fee = _value * basisPointsRate / FEE_PRECISION;
        uint256 sendAmount = _value - fee;
        balances[msg.sender] = balances[msg.sender] - _value;
        balances[_to] = balances[_to] + sendAmount;
        if (fee > 0) {
            balances[owner] = balances[owner] + fee;
            emit Transfer(msg.sender, owner, fee);
        }
        emit Transfer(msg.sender, _to, sendAmount);
        return true;
    }

    /**
    * @dev transfer tokens from one address to another
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint256 the amount of tokens to be transferred
    */
    function transferFrom(address _from, address _to, uint256 _value) public whenNotPaused notBlackListed(_from) returns (bool) {
        uint256 _allowance = allowed[_from][msg.sender];

        // check is not needed because sub(_allowance, _value) will already throw if this condition is not met
        // if (_value > _allowance) throw;

        uint256 fee = _value * basisPointsRate / FEE_PRECISION;
        if (_allowance < type(uint256).max) {
            allowed[_from][msg.sender] = _allowance - _value;
        }
        uint256 sendAmount = _value - fee;
        balances[_from] = balances[_from] - _value;
        balances[_to] = balances[_to] + sendAmount;
        if (fee > 0) {
            balances[owner] = balances[owner] + fee;
            emit Transfer(_from, owner, fee);
        }
        emit Transfer(_from, _to, sendAmount);
        return true;
    }

    /**
    * @dev approve the passed address to spend the specified amount of tokens on behalf of msg.sender
    * @param _spender the address which will spend the funds
    * @param _value the amount of tokens to be spent
    */
    function approve(address _spender, uint256 _value) public returns (bool) {
        require(msg.sender != address(0), "caller can't be zero address");
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    ////////////////////////
    // SERVICE FUNCTIONS
    ////////////////////////

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() onlyOwner whenNotPaused public {
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() onlyOwner whenPaused public {
        paused = false;
        emit Unpause();
    }

    function addBlackList (address _evilUser) public onlyCompliance {
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    function removeBlackList (address _clearedUser) public onlyCompliance {
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }

    function destroyBlackFunds (address _blackListedUser) public onlyCompliance {
        require(isBlackListed[_blackListedUser], "user should be blacklisted");
        uint256 dirtyFunds = balanceOf(_blackListedUser);
        balances[_blackListedUser] = 0;
        _totalSupply -= dirtyFunds;
        emit DestroyedBlackFunds(_blackListedUser, dirtyFunds);
    }

    // issue a new amount of tokens
    // @param _amount number of tokens to be issued
    // @param _to address of tokens receiver
    function issue(address _to, uint256 amount) public onlyOwner {
        balances[_to] += amount;
        _totalSupply += amount;
        emit Issue(amount);
    }

    // redeem tokens
    // these tokens are withdrawn from the owner address
    // if the balance must be enough to cover the redeem
    // or the call will fail
    // @param _amount number of tokens to be burnt
    function redeem(uint256 amount) public onlyOwner {
        require(_totalSupply >= amount, "not enough tokens to redeem");
        require(balances[owner] >= amount, "not enough tokens to redeem");

        _totalSupply -= amount;
        balances[owner] -= amount;
        emit Redeem(amount);
    }

    function setParams(uint256 newBasisPoints) public onlyOwner {
        // ensure transparency by hardcoding limit beyond which fees can never be added
        require(newBasisPoints < MAX_BASIS_POINTS, "basis points should be less then MAX_BASIS_POINTS");

        basisPointsRate = newBasisPoints;

        emit Params(basisPointsRate);
    }

    ////////////////////////
    // VIEW FUNCTIONS
    ////////////////////////

    /**
    * @dev gets the balance of the specified address
    * @param _owner the address to query the the balance of
    * @return balance An uint256 representing the amount owned by the passed address
    */
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    /**
    * @dev function to check the amount of tokens than an owner allowed to a spender
    * @param _owner address the address which owns the funds
    * @param _spender address the address which will spend the funds
    * @return remaining a uint256 specifying the amount of tokens still available for the spender
    */
    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    // getters to allow the same blacklist to be used also by other contracts (including upgraded Tether)
    function getBlackListStatus(address _maker) external view returns (bool) {
        return isBlackListed[_maker];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
}