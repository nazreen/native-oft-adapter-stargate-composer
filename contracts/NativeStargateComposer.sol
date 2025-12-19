// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";

import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IMultiHopComposer, FailedMessage } from "./interfaces/IMultiHopComposer.sol";

/// @notice Multi-hop composer between:
/// @notice - NativeOFTAdapter (native ETH, e.g. Arbitrum), and
/// @notice - StargatePoolNative (Stargate, used as a routing hub to any dstEid).
contract NativeStargateComposer is IMultiHopComposer, ReentrancyGuard {
    using OFTComposeMsgCodec for bytes;

    /// @dev NativeOFTAdapter address (native mesh).
    address public immutable NATIVE_OFT;
    /// @dev StargatePoolNative address (IOFT-based Stargate pool on this chain).
    address public immutable STARGATE_POOL;
    /// @dev LayerZero endpoint for this OApp (from NativeOFTAdapter).
    address public immutable ENDPOINT;

    /// @dev Address that receives cached msg.value refunds when calling refund().
    address public immutable EXECUTOR;

    mapping(bytes32 guid => FailedMessage) public failedMessages;

    error InvalidNativeOFT();
    error InvalidStargatePool();
    error InvalidExecutor();
    error OnlyEndpoint(address caller);
    error OnlyOFT(address unexpected);
    error OnlySelf(address caller);
    error OnlyExecutor(address caller);
    error InvalidSendParam(SendParam sendParam);
    error InsufficientValue(uint256 required, uint256 available);
    error WithdrawFailed();

    event DecodeFailed(bytes32 guid, address targetOFT, bytes encodedSendParam);
    event Sent(bytes32 guid, address targetOFT);
    event SendFailed(bytes32 guid, address targetOFT);
    event Refunded(bytes32 guid, address refundOFT);
    event Retried(bytes32 guid, address targetOFT);

    constructor(address _nativeOFT, address _stargatePool, address _executor) {
        if (_nativeOFT == address(0)) revert InvalidNativeOFT();
        if (_stargatePool == address(0)) revert InvalidStargatePool();
        if (_executor == address(0)) revert InvalidExecutor();

        NATIVE_OFT = _nativeOFT;
        STARGATE_POOL = _stargatePool;
        EXECUTOR = _executor;

        ENDPOINT = address(IOAppCore(_nativeOFT).endpoint());

        // NativeOFTAdapter: no approvals, underlying is native (address(0)).
        if (IOFT(_nativeOFT).approvalRequired()) revert InvalidNativeOFT();
        if (IOFT(_nativeOFT).token() != address(0)) revert InvalidNativeOFT();

        // StargatePoolNative: IOFT over native ETH (token() == address(0)).
        if (IOFT(_stargatePool).token() != address(0)) revert InvalidStargatePool();
    }

    function lzCompose(
        address _refundOFT,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) external payable override {
        if (msg.sender != ENDPOINT) revert OnlyEndpoint(msg.sender);
        if (_refundOFT != NATIVE_OFT && _refundOFT != STARGATE_POOL) revert OnlyOFT(_refundOFT);

        // Route: if funds came from NativeOFT mesh, send to StargatePool; otherwise back to NativeOFT.
        address oft = _refundOFT == NATIVE_OFT ? STARGATE_POOL : NATIVE_OFT;

        uint32 srcEid = OFTComposeMsgCodec.srcEid(_message);
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        bytes32 srcSender = OFTComposeMsgCodec.composeFrom(_message);
        bytes memory sendParamEncoded = OFTComposeMsgCodec.composeMsg(_message);

        // Refund path back to source mesh.
        SendParam memory refundSendParam;
        refundSendParam.dstEid = srcEid;
        refundSendParam.to = srcSender;
        refundSendParam.amountLD = amount;

        SendParam memory sendParam;

        // Decode second-hop SendParam from composeMsg.
        try this.decodeSendParam(sendParamEncoded) returns (SendParam memory sendParamDecoded) {
            sendParam = sendParamDecoded;

            // Guard against draining old locked funds: cap to actual amount received.
            sendParam.amountLD = amount;

            // Let the target IOFT handle slippage / conversions; we set slippage floor to zero here.
            sendParam.minAmountLD = 0;
        } catch {
            // Decode failed: only refund back to source mesh is possible.
            failedMessages[_guid] = FailedMessage({
                oft: address(0),
                sendParam: sendParam,
                refundOFT: _refundOFT,
                refundSendParam: refundSendParam,
                msgValue: msg.value
            });

            emit DecodeFailed(_guid, oft, sendParamEncoded);
            return;
        }

        // Try the second-hop send (NativeOFT <-> StargatePool).
        try this.send{ value: msg.value }(oft, sendParam) {
            emit Sent(_guid, oft);
        } catch {
            // Store failure for refund or retry.
            failedMessages[_guid] = FailedMessage({
                oft: oft,
                sendParam: sendParam,
                refundOFT: _refundOFT,
                refundSendParam: refundSendParam,
                msgValue: msg.value
            });

            emit SendFailed(_guid, oft);
            return;
        }
    }

    function decodeSendParam(bytes calldata sendParamBytes)
        external
        pure
        returns (SendParam memory sendParam)
    {
        sendParam = abi.decode(sendParamBytes, (SendParam));
    }

    function send(address _oft, SendParam memory _sendParam)
        external
        payable
        nonReentrant
    {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        _send(_oft, _sendParam, 0, tx.origin);
    }

    function refund(bytes32 _guid) external payable nonReentrant {
        FailedMessage memory failedMessage = failedMessages[_guid];
        if (failedMessage.refundOFT == address(0)) {
            revert InvalidSendParam(failedMessage.refundSendParam);
        }

        delete failedMessages[_guid];

        _send(
            failedMessage.refundOFT,
            failedMessage.refundSendParam,
            failedMessage.msgValue,
            EXECUTOR
        );

        emit Refunded(_guid, failedMessage.refundOFT);
    }

    function retry(bytes32 _guid) external payable nonReentrant {
        FailedMessage memory failedMessage = failedMessages[_guid];
        if (failedMessage.oft == address(0)) {
            revert InvalidSendParam(failedMessage.sendParam);
        }

        delete failedMessages[_guid];

        _send(
            failedMessage.oft,
            failedMessage.sendParam,
            failedMessage.msgValue,
            tx.origin
        );

        emit Retried(_guid, failedMessage.oft);
    }

    function _send(
        address _oft,
        SendParam memory _sendParam,
        uint256 _prePaidValue,
        address _refundTo
    ) internal {
        uint256 msgValue = msg.value + _prePaidValue;

        // Quote the actual fee from the OFT
        MessagingFee memory fee = IOFT(_oft).quoteSend(_sendParam, false);

        uint256 required = _sendParam.amountLD + fee.nativeFee;
        if (msgValue < required) revert InsufficientValue(required, msgValue);

        IOFT(_oft).send{ value: required }( // Send exactly what's needed, not excess, as sending excess would trigger a revert for NativeOFTAdapter
            _sendParam,
            fee,
            _refundTo
        );
    }

    /// @notice Allows EXECUTOR to withdraw excess ETH accumulated from the difference between second hop's fee and composeOptions.value
    function withdraw() external {
        if (msg.sender != EXECUTOR) revert OnlyExecutor(msg.sender);
        uint256 balance = address(this).balance;
        (bool success, ) = payable(EXECUTOR).call{value: balance}("");
        if (!success) revert WithdrawFailed();
    }

    receive() external payable {}
}
