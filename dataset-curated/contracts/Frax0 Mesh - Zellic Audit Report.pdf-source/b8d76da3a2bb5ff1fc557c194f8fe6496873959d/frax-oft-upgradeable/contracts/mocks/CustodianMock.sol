pragma solidity ^0.8.22;

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @dev used in conjunction with `scripts/ops/MoveLegacyLiquidity/1_DeployMockOFTs.s.sol`
contract CustodianMock is Ownable, Initializable {
    
    uint32 public constant dstEid = 30101; // Ethereum

    address public constant ethComptroller = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;
    // Copied from L0Constants.sol
    address public constant ethFrxEthLockbox = 0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6;
    address public constant ethSFrxEthLockbox = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960;
    address public constant ethFxsLockbox = 0xC6F59a4fD50cAc677B51558489E03138Ac1784EC;

    address public mockFrxUsdOft;
    address public mockSfrxUsdOft;
    address public mockFrxEthOft;
    address public mockSfrxEthOft;
    address public mockFxsOft;

    receive() external payable {}

    constructor() {}

    function initialize(
        address _mockFrxUsdOft,
        address _mockSfrxUsdOft,
        address _mockFrxEthOft,
        address _mockSfrxEthOft,
        address _mockFxsOft,
        address _initialOwner
    ) external initializer onlyOwner {
        require(
            _mockFrxUsdOft != address(0) &&
            _mockSfrxUsdOft != address(0) &&
            _mockFrxEthOft != address(0) &&
            _mockSfrxEthOft != address(0) &&
            _mockFxsOft != address(0) &&
            _initialOwner != address(0),
            "CustodianMock: zero address"
        );

        mockFrxUsdOft = _mockFrxUsdOft;
        mockSfrxUsdOft = _mockSfrxUsdOft;
        mockFrxEthOft = _mockFrxEthOft;
        mockSfrxEthOft = _mockSfrxEthOft;
        mockFxsOft = _mockFxsOft;

        _transferOwnership(_initialOwner);
    }

    function initialSend() external payable onlyOwner reinitializer(2) {
        // send 1 frxUSD, 1 sfrxUSD, 0.001 frxETH, 0.001 sfrxETH, 1 FXS
        _send(mockFrxUsdOft, ethComptroller, 1e18);
        _send(mockSfrxUsdOft, ethComptroller, 1e18);
        _send(mockFrxEthOft, ethFrxEthLockbox, 0.001e18);
        _send(mockSfrxEthOft, ethSFrxEthLockbox, 0.001e18);
        _send(mockFxsOft, ethFxsLockbox, 1e18);
    }

    function fullSend() external onlyOwner reinitializer(3){
        _send(mockFrxUsdOft, ethComptroller, IERC20(mockFrxUsdOft).balanceOf(address(this)));
        _send(mockSfrxUsdOft, ethComptroller, IERC20(mockSfrxUsdOft).balanceOf(address(this)));
        _send(mockFrxEthOft, ethFrxEthLockbox, IERC20(mockFrxEthOft).balanceOf(address(this)));
        _send(mockSfrxEthOft, ethSFrxEthLockbox, IERC20(mockSfrxEthOft).balanceOf(address(this)));
        _send(mockFxsOft, ethFxsLockbox, IERC20(mockFxsOft).balanceOf(address(this)));

        // withdraw any remaining ETH
        (bool success, ) = payable(owner()).call{value:address(this).balance}("");
        require(success);
    }

    function _send(address _oft, address _to, uint256 amount) internal {
        require(amount > 0, "CustodianMock: zero amount");

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(_to))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: '',
            oftCmd: ''
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        IOFT(_oft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(owner())
        );
    }
}