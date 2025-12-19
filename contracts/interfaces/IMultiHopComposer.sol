// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

struct FailedMessage {
    address oft;
    SendParam sendParam;
    address refundOFT;
    SendParam refundSendParam;
    uint256 msgValue;
}

interface IMultiHopComposer {
    function lzCompose(
        address _refundOFT,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}

