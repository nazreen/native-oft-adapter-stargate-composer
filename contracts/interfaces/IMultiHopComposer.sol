// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";

import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

struct FailedMessage {
    address oft;
    SendParam sendParam;
    address refundOFT;
    SendParam refundSendParam;
    uint256 msgValue;
}

/// @dev Second-hop parameters packed in composeMsg. Fee is quoted off-chain to avoid
/// @dev calling quoteSend() in receive path; if price deviates, send reverts early and can be retried.
struct HopParams {
    SendParam sendParam;
    MessagingFee hopQuote;
}

interface IMultiHopComposer is IOAppComposer {
    /// ========================== EVENTS =====================================
    event DecodeFailed(bytes32 indexed guid, address indexed oft, bytes message);
    event Sent(bytes32 indexed guid, address indexed oft);
    event SendFailed(bytes32 indexed guid, address indexed oft);
    event Refunded(bytes32 indexed guid, address indexed oft);
    event Retried(bytes32 indexed guid, address indexed oft);

    /// ========================== ERRORS =====================================
    error OnlyEndpoint(address caller);
    error OnlySelf(address caller);
    error OnlyOFT(address oft);
    error InvalidSendParam(SendParam sendParam);

    /// ========================== GETTERS =====================================
    function ENDPOINT() external view returns (address);
    function EXECUTOR() external view returns (address);

    /// ========================== FUNCTIONS =====================================
    function refund(bytes32 guid, MessagingFee calldata fee) external payable;
    function retry(bytes32 guid, MessagingFee calldata fee) external payable;
    function send(address oft, SendParam memory sendParam, MessagingFee memory fee) external payable;

    receive() external payable;
}
