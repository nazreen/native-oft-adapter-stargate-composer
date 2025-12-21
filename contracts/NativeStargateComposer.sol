// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";

import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { IMultiHopComposer, FailedMessage, HopParams } from "./interfaces/IMultiHopComposer.sol";

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
    error OnlyExecutor(address caller);
    error InsufficientValue(uint256 required, uint256 available);
    error WithdrawFailed();

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
        bytes memory hopParamsEncoded = OFTComposeMsgCodec.composeMsg(_message);

        // Refund path back to source mesh.
        SendParam memory refundSendParam;
        refundSendParam.dstEid = srcEid;
        refundSendParam.to = srcSender;
        refundSendParam.amountLD = amount;

        HopParams memory hopParams;

        // Decode second-hop HopParams (SendParam + pre-quoted fee) from composeMsg.
        try this.decodeHopParams(hopParamsEncoded) returns (HopParams memory decoded) {
            hopParams = decoded;

            // Guard against draining old locked funds: cap to actual amount received.
            hopParams.sendParam.amountLD = amount;

            // Let the target IOFT handle slippage / conversions; we set slippage floor to zero here.
            hopParams.sendParam.minAmountLD = 0;
        } catch {
            // Decode failed: only refund back to source mesh is possible.
            failedMessages[_guid] = FailedMessage({
                oft: address(0),
                sendParam: hopParams.sendParam,
                refundOFT: _refundOFT,
                refundSendParam: refundSendParam,
                msgValue: msg.value
            });

            emit DecodeFailed(_guid, oft, hopParamsEncoded);
            return;
        }

        // Try the second-hop send using pre-quoted fee (NativeOFT <-> StargatePool).
        try this.send{ value: msg.value }(oft, hopParams.sendParam, hopParams.hopQuote) {
            emit Sent(_guid, oft);
        } catch {
            // Store failure for refund or retry.
            failedMessages[_guid] = FailedMessage({
                oft: oft,
                sendParam: hopParams.sendParam,
                refundOFT: _refundOFT,
                refundSendParam: refundSendParam,
                msgValue: msg.value
            });

            emit SendFailed(_guid, oft);
            return;
        }
    }

    function decodeHopParams(bytes calldata hopParamsBytes)
        external
        pure
        returns (HopParams memory hopParams)
    {
        hopParams = abi.decode(hopParamsBytes, (HopParams));
    }

    function send(address _oft, SendParam memory _sendParam, MessagingFee memory _fee)
        external
        payable
        nonReentrant
    {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        _send(_oft, _sendParam, _fee, 0, tx.origin);
    }

    /// @notice Refund failed message back to source. Caller must quote fee off-chain before calling.
    function refund(bytes32 _guid, MessagingFee calldata _fee) external payable nonReentrant {
        FailedMessage memory failedMessage = failedMessages[_guid];
        if (failedMessage.refundOFT == address(0)) {
            revert InvalidSendParam(failedMessage.refundSendParam);
        }

        delete failedMessages[_guid];

        _send(
            failedMessage.refundOFT,
            failedMessage.refundSendParam,
            _fee,
            failedMessage.msgValue,
            EXECUTOR
        );

        emit Refunded(_guid, failedMessage.refundOFT);
    }

    /// @notice Retry failed message to original destination. Caller must quote fee off-chain before calling.
    function retry(bytes32 _guid, MessagingFee calldata _fee) external payable nonReentrant {
        FailedMessage memory failedMessage = failedMessages[_guid];
        if (failedMessage.oft == address(0)) {
            revert InvalidSendParam(failedMessage.sendParam);
        }

        delete failedMessages[_guid];

        _send(
            failedMessage.oft,
            failedMessage.sendParam,
            _fee,
            failedMessage.msgValue,
            tx.origin
        );

        emit Retried(_guid, failedMessage.oft);
    }

    function _send(
        address _oft,
        SendParam memory _sendParam,
        MessagingFee memory _fee,
        uint256 _prePaidValue,
        address _refundTo
    ) internal {
        uint256 msgValue = msg.value + _prePaidValue;

        uint256 required = _sendParam.amountLD + _fee.nativeFee;
        if (msgValue < required) revert InsufficientValue(required, msgValue);

        IOFT(_oft).send{ value: required }( // Send exactly what's needed, not excess, as sending excess would trigger a revert for NativeOFTAdapter
            _sendParam,
            _fee,
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
