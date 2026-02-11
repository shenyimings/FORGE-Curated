// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {IWETH} from "./interfaces/IWETH.sol";

import {IAxelarGasService} from "lib/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {AxelarExecutableUpgradeable} from "./AxelarExecutableUpgradeable.sol";

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {ISwapRouter02} from "./interfaces/ISwapRouter02.sol";
import {SkipSwapRouter} from "./libraries/SkipSwapRouter.sol";

/// @title AxelarHandler
/// @notice allows to send and receive tokens to/from other chains through axelar gateway while wrapping the native tokens.
/// @author Skip Protocol.
contract AxelarHandler is AxelarExecutableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    error EmptySymbol();
    error NativeSentDoesNotMatchAmounts();
    error TokenNotSupported();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroGasAmount();
    error ZeroNativeSent();
    error NonNativeCannotBeUnwrapped();
    error NativePaymentFailed();
    error WrappingNotEnabled();
    error SwapFailed();
    error InsufficientSwapOutput();
    error InsufficientNativeToken();
    error ETHSendFailed();
    error Reentrancy();
    error FunctionCodeNotSupported();

    event SwapSuccess(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event SwapFailed();

    enum Commands {
        SendToken,
        SendNative,
        Swap,
        MultiSwap
    }

    bytes32 private _wETHSymbolHash;

    string public wETHSymbol;
    IAxelarGasService public gasService;

    mapping(address => bool) public approved;

    bytes32 public constant DISABLED_SYMBOL = keccak256(abi.encodePacked("DISABLED"));

    ISwapRouter02 public swapRouter;

    bool internal reentrant;

    modifier nonReentrant() {
        if (reentrant) revert Reentrancy();
        reentrant = true;
        _;
        reentrant = false;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address axGateway, address axGasService, string memory wethSymbol) external initializer {
        if (axGasService == address(0)) revert ZeroAddress();
        if (bytes(wethSymbol).length == 0) revert EmptySymbol();

        __AxelarExecutable_init(axGateway);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        gasService = IAxelarGasService(axGasService);
        wETHSymbol = wethSymbol;
        _wETHSymbolHash = keccak256(abi.encodePacked(wethSymbol));
    }

    function setWETHSybol(string memory wethSymbol) external onlyOwner {
        if (bytes(wethSymbol).length == 0) revert EmptySymbol();

        wETHSymbol = wethSymbol;
        _wETHSymbolHash = keccak256(abi.encodePacked(wethSymbol));
    }

    function setSwapRouter(address _swapRouter) external onlyOwner {
        if (_swapRouter == address(0)) revert ZeroAddress();

        swapRouter = ISwapRouter02(_swapRouter);
    }

    /// @notice Sends native currency to other chains through the axelar gateway.
    /// @param destinationChain name of the destination chain.
    /// @param destinationAddress address of the destination wallet in string form.
    function sendNativeToken(string memory destinationChain, string memory destinationAddress) external payable {
        if (_wETHSymbolHash == DISABLED_SYMBOL) revert WrappingNotEnabled();
        if (msg.value == 0) revert ZeroNativeSent();

        // Get the token address from the gateway.
        address token = _getTokenAddress(wETHSymbol);

        // Wrap the sent ether.
        IWETH(token).deposit{value: msg.value}();

        // Call Axelar Gateway to transfer the WETH.
        gateway.sendToken(destinationChain, destinationAddress, wETHSymbol, msg.value);
    }

    /// @notice Sends a ERC20 token to other chains through the axelar gateway.
    /// @param destinationChain name of the destination chain.
    /// @param destinationAddress address of the destination wallet in string form.
    /// @param symbol the symbol of the ERC20 token to be sent.
    /// @param amount amount of tokens to be sent.
    function sendERC20Token(
        string memory destinationChain,
        string memory destinationAddress,
        string memory symbol,
        uint256 amount
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (bytes(symbol).length == 0) revert EmptySymbol();

        IERC20 token = IERC20(_getTokenAddress(symbol));

        token.safeTransferFrom(msg.sender, address(this), amount);

        gateway.sendToken(destinationChain, destinationAddress, symbol, amount);
    }

    /// @notice Sends native tokens to other chain while calling a contract in the destination chain.
    /// @param destinationChain name of the destination chain.
    /// @param contractAddress address of the contract that will be called in the destination chain.
    /// @param payload the payload that will be sent to the contract in the destination chain.
    /// @param amount amount of tokens to be sent.
    /// @param gasPaymentAmount the amount of native currency that will be used for paying gas.
    /// @dev The amount of native currency sent (msg.value) must be equal to amount + gasPaymentAmount.
    function gmpTransferNativeToken(
        string memory destinationChain, // argument passed to both child contract calls
        string memory contractAddress, // argument passed to both child contract calls
        bytes memory payload, // argument passed to both child contract calls
        uint256 amount, // argument passed to both child contract calls
        uint256 gasPaymentAmount
    ) external payable {
        if (_wETHSymbolHash == DISABLED_SYMBOL) revert WrappingNotEnabled();
        if (amount == 0) revert ZeroAmount();
        if (gasPaymentAmount == 0) revert ZeroGasAmount();
        if (msg.value != amount + gasPaymentAmount) {
            revert NativeSentDoesNotMatchAmounts();
        }

        // Wrap the ether to be sent into the gateway.
        IWETH(_getTokenAddress(wETHSymbol)).deposit{value: amount}();

        gasService.payNativeGasForContractCallWithToken{value: gasPaymentAmount}(
            address(this), destinationChain, contractAddress, payload, wETHSymbol, amount, msg.sender
        );

        gateway.callContractWithToken(destinationChain, contractAddress, payload, wETHSymbol, amount);
    }

    /// @notice Sends ERC20 to other chain while calling a contract in the destination chain and paying gas with native token.
    /// @param destinationChain name of the destination chain.
    /// @param contractAddress address of the contract that will be called in the destination chain.
    /// @param payload the payload that will be sent to the contract in the destination chain.
    /// @param symbol the symbol of the ERC20 token to be sent.
    /// @param amount amount of tokens to be sent.
    /// @param gasPaymentAmount the amount of native currency that will be used for paying gas.
    /// @dev The amount of native currency sent (msg.value) must be equal to gasPaymentAmount.
    function gmpTransferERC20Token(
        string memory destinationChain, // argument passed to both child contract calls
        string memory contractAddress, // argument passed to both child contract calls
        bytes memory payload, // argument passed to both child contract calls
        string memory symbol, // argument passed to both child contract calls
        uint256 amount, // argument passed to both child contract calls
        uint256 gasPaymentAmount // amount to send with gas payment call
    ) public payable {
        if (amount == 0) revert ZeroAmount();
        if (gasPaymentAmount == 0) revert ZeroGasAmount();
        if (msg.value != gasPaymentAmount) {
            revert NativeSentDoesNotMatchAmounts();
        }
        if (bytes(symbol).length == 0) revert EmptySymbol();

        // Get the token address.
        IERC20 token = IERC20(_getTokenAddress(symbol));

        // Transfer the amount from the msg.sender.
        token.safeTransferFrom(msg.sender, address(this), amount);

        gasService.payNativeGasForContractCallWithToken{value: gasPaymentAmount}(
            address(this), destinationChain, contractAddress, payload, symbol, amount, msg.sender
        );

        require(token.balanceOf(address(this)) >= amount, "NOT ENOUGH BALANCE");

        gateway.callContractWithToken(destinationChain, contractAddress, payload, symbol, amount);
    }

    /// @notice Swap the input token to a axelar supported token before doing a GMP Transfer.
    /// @param inputToken address of the ERC20 token to be swapped.
    /// @param amount the amount of either input tokens or native currency to be swapped.
    /// @param destinationChain name of the destination chain.
    /// @param contractAddress address of the contract that will be called in the destination chain.
    /// @param payload the payload that will be sent to the contract in the destination chain.
    /// @param symbol the symbol of the ERC20 token to be sent.
    /// @param gasPaymentAmount the amount of native currency that will be used for paying gas.
    /// @dev The amount of native currency sent (msg.value) must be equal to gasPaymentAmount.
    function swapAndGmpTransferERC20Token(
        address inputToken,
        uint256 amount,
        bytes memory swapCalldata,
        string memory destinationChain,
        string memory contractAddress,
        bytes memory payload,
        string memory symbol,
        uint256 gasPaymentAmount
    ) external payable nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (gasPaymentAmount == 0) revert ZeroGasAmount();
        if (bytes(symbol).length == 0) revert EmptySymbol();

        // Get the address of the output token based on the symbol provided
        IERC20 outputToken = IERC20(_getTokenAddress(symbol));

        uint256 outputAmount;
        if (inputToken == address(0)) {
            // Native Token
            if (amount + gasPaymentAmount != msg.value) revert InsufficientNativeToken();

            // Get the contract's balances previous to the swap
            uint256 preInputBalance = address(this).balance - msg.value;
            uint256 preOutputBalance = outputToken.balanceOf(address(this));

            // Call the swap router and perform the swap
            (bool success,) = address(swapRouter).call{value: amount}(swapCalldata);
            if (!success) revert SwapFailed();

            // Get the contract's balances after the swap
            uint256 postInputBalance = address(this).balance;
            uint256 postOutputBalance = outputToken.balanceOf(address(this));

            // Check that the contract's native token balance has increased
            if (preOutputBalance >= postOutputBalance) revert InsufficientSwapOutput();
            outputAmount = postOutputBalance - preOutputBalance;

            // Refund the remaining ETH
            uint256 dust = postInputBalance - preInputBalance - gasPaymentAmount;
            if (dust != 0) {
                (bool ethSuccess,) = msg.sender.call{value: dust}("");
                if (!ethSuccess) revert ETHSendFailed();
            }

            emit SwapSuccess(inputToken, address(outputToken), amount, outputAmount);
        } else {
            // ERC20 Token
            if (gasPaymentAmount != msg.value) revert();

            // Transfer input ERC20 tokens to the contract
            IERC20 token = IERC20(inputToken);
            token.safeTransferFrom(msg.sender, address(this), amount);

            // Approve the swap router to spend the input tokens
            token.safeApprove(address(swapRouter), amount);

            // Get the contract's balances previous to the swap
            uint256 preInputBalance = token.balanceOf(address(this));
            uint256 preOutputBalance = outputToken.balanceOf(address(this));

            // Call the swap router and perform the swap
            (bool success,) = address(swapRouter).call(swapCalldata);
            if (!success) revert SwapFailed();

            // Get the contract's balances after the swap
            uint256 dust = token.balanceOf(address(this)) + amount - preInputBalance;
            uint256 postOutputBalance = outputToken.balanceOf(address(this));

            // Check that the contract's output token balance has increased
            if (preOutputBalance >= postOutputBalance) revert InsufficientSwapOutput();
            outputAmount = postOutputBalance - preOutputBalance;

            // Refund the remaining amount
            if (dust != 0) {
                token.safeTransfer(msg.sender, dust);

                // Revoke approval
                token.safeApprove(address(swapRouter), 0);
            }

            emit SwapSuccess(inputToken, address(outputToken), amount, outputAmount);
        }

        // Pay the gas for the GMP transfer
        gasService.payNativeGasForContractCallWithToken{value: gasPaymentAmount}(
            address(this), destinationChain, contractAddress, payload, symbol, outputAmount, msg.sender
        );

        // Perform the GMP transfer
        gateway.callContractWithToken(destinationChain, contractAddress, payload, symbol, outputAmount);
    }

    /// @notice Sends ERC20 to other chain while calling a contract in the destination chain and paying gas with destination token.
    /// @param destinationChain name of the destination chain.
    /// @param contractAddress address of the contract that will be called in the destination chain.
    /// @param payload the payload that will be sent to the contract in the destination chain.
    /// @param symbol the symbol of the ERC20 token to be sent.
    /// @param amount amount of tokens to be sent.
    /// @param gasPaymentAmount the amount of native currency that will be used for paying gas.
    /// @dev The amount of native currency sent (msg.value) must be equal to gasPaymentAmount.
    function gmpTransferERC20TokenGasTokenPayment(
        string memory destinationChain, // argument passed to both child contract calls
        string memory contractAddress, // argument passed to both child contract calls
        bytes memory payload, // argument passed to both child contract calls
        string memory symbol, // argument passed to both child contract calls
        uint256 amount, // argument passed to both child contract calls
        uint256 gasPaymentAmount // amount to send with gas payment call
    ) external {
        if (amount == 0) revert ZeroAmount();
        if (gasPaymentAmount == 0) revert ZeroGasAmount();
        if (bytes(symbol).length == 0) revert EmptySymbol();

        // Get the token address.
        IERC20 token = IERC20(_getTokenAddress(symbol));

        // Transfer the amount and gas payment amount from the msg.sender.
        token.safeTransferFrom(msg.sender, address(this), amount + gasPaymentAmount);

        gasService.payGasForContractCallWithToken(
            address(this),
            destinationChain,
            contractAddress,
            payload,
            symbol,
            amount,
            address(token),
            gasPaymentAmount,
            msg.sender
        );

        gateway.callContractWithToken(destinationChain, contractAddress, payload, symbol, amount);
    }

    receive() external payable {}

    fallback() external payable {}

    /// @notice Ensures a token is supported by the axelar gateway, and returns it's address.
    /// @param symbol the symbol of the ERC20 token to be checked.
    function _getTokenAddress(string memory symbol) internal returns (address token) {
        token = gateway.tokenAddresses(symbol);
        if (token == address(0)) revert TokenNotSupported();

        if (!approved[token]) {
            IERC20(token).safeApprove(address(gateway), type(uint256).max);
            IERC20(token).safeApprove(address(gasService), type(uint256).max);
            approved[token] = true;
        }
    }

    /// @notice Internal function called by the AxelarExecutor when a GMP call is made to this contract.
    /// @notice Receives the tokens and unwraps them if it's wrapped native currency.
    /// @param payload the payload that was sent along with the GMP message.
    /// @param tokenSymbol the symbol of the tokens received.
    /// @param amount the amount of tokens received.
    function _executeWithToken(
        string calldata, // sourceChain
        string calldata, // sourceAddress
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal override {
        address token = _getTokenAddress(tokenSymbol);
        IERC20 tokenIn = IERC20(token);

        (Commands command, bytes memory data) = abi.decode(payload, (Commands, bytes));
        if (command == Commands.SendToken) {
            address destination = abi.decode(data, (address));
            _sendToken(token, amount, destination);
        } else if (command == Commands.SendNative) {
            address destination = abi.decode(data, (address));

            _sendNative(token, amount, destination);
        } else if (command == Commands.Swap) {
            (address destination, bool unwrapOut, bytes memory swap) = abi.decode(data, (address, bool, bytes));

            try SkipSwapRouter.swap(swapRouter, destination, tokenIn, amount, swap) returns (
                IERC20 tokenOut, uint256 amountOut
            ) {
                if (unwrapOut) {
                    _sendNative(address(tokenOut), amountOut, destination);
                    emit SwapSuccess(address(tokenIn), address(0), amount, amountOut);
                } else {
                    _sendToken(address(tokenOut), amountOut, destination);
                    emit SwapSuccess(address(tokenIn), address(tokenOut), amount, amountOut);
                }
            } catch {
                _sendToken(token, amount, destination);
                emit SwapFailed();
            }
        } else if (command == Commands.MultiSwap) {
            (address destination, bool unwrapOut, bytes[] memory swaps) = abi.decode(data, (address, bool, bytes[]));

            try SkipSwapRouter.multiSwap(swapRouter, destination, tokenIn, amount, swaps) returns (
                IERC20 tokenOut, uint256 amountOut
            ) {
                if (unwrapOut) {
                    _sendNative(address(tokenOut), amountOut, destination);
                    emit SwapSuccess(address(tokenIn), address(0), amount, amountOut);
                } else {
                    _sendToken(address(tokenOut), amountOut, destination);
                    emit SwapSuccess(address(tokenIn), address(tokenOut), amount, amountOut);
                }
            } catch {
                _sendToken(token, amount, destination);
                emit SwapFailed();
            }
        } else {
            revert FunctionCodeNotSupported();
        }
    }

    function _sendToken(address token, uint256 amount, address destination) internal {
        IERC20(token).safeTransfer(destination, amount);
    }

    function _sendNative(address token, uint256 amount, address destination) internal {
        try SkipSwapRouter.sendNative(token, amount, destination) {}
        catch {
            _sendToken(token, amount, destination);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
