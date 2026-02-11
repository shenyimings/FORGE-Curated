pragma solidity ^0.8.22;

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @dev used in conjunction with `scripts/ops/MoveLegacyLiquidity/2_DeployMockFXS.s.sol`
contract FXSCustodianMock is Ownable, Initializable {
    
    uint32 public constant dstEid = 30101; // Ethereum

    address public constant ethComptroller = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;
    address public mockFxsOft;

    receive() external payable {}

    constructor() {}

    function initialize(
        address _mockFxsOft,
        address _initialOwner
    ) external initializer onlyOwner {
        require(
            _mockFxsOft != address(0) &&
            _initialOwner != address(0),
            "CustodianMock: zero address"
        );

        mockFxsOft = _mockFxsOft;

        _transferOwnership(_initialOwner);
    }

    function initialSend() external payable onlyOwner reinitializer(2) {
        // send 1 FXS
        _send(mockFxsOft, 1e18);
    }

    function fullSend() external onlyOwner reinitializer(3) {
        _send(mockFxsOft, IERC20(mockFxsOft).balanceOf(address(this)));

        // withdraw any remaining FRAX
        (bool success, ) = payable(owner()).call{value:address(this).balance}("");
        require(success);
    }

    function _send(address _oft, uint256 amount) internal {
        require(amount > 0, "CustodianMock: zero amount");

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(ethComptroller))),
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