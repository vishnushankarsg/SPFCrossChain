// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./SpokeStorage.sol";

contract SpokeSetter is SpokeState{

    function setChainId(uint16 chainId_) internal {
        _state.chainId = chainId_;
    }

    function setMeuToken(address token) internal{
        _state.meuToken = token;
    }

    function setGasLimit(uint256 message, uint256 transfer) internal {
        _state.messageGasLimit = message;
        _state.transferGasLimit = transfer;
    }

    function setRoundInfo(uint16 round_, uint256 timeStamp_)internal{
        _state.roundEnds[round_] = timeStamp_;
        _state.roundInvestmentEnds[round_] = timeStamp_ - 30 minutes;
    }

    function setStakePercent(uint32 percentage) internal {
        _state.stakePercentage = percentage;
    }

    function setEntryFee(uint32 entryFee_)internal{
        _state.entryFee = entryFee_;
    }

    function setMinInvestment(uint32 minInvestment_)internal{
        _state.minInvestment = minInvestment_;
    }

    function setTokenBridge(address tokenBridge_) internal{
        _state.tokenBridge = payable(tokenBridge_);
    }

    function setWormhole(address wormhole_) internal{
        _state.wormhole = payable(wormhole_);
    }

    function setWormholeRelayer(address evmRelayer_) internal{
        _state.wormholeRelayer = payable(evmRelayer_);
    }

    function setHub(SpokeStorage.RelayerType relayerType_, uint16 chainId_, address hubContract_) internal {
        _state.hubChainId = chainId_;
        _state.hubContractAddress = hubContract_;
        _state.chainRelayerType[chainId_] = relayerType_;
    }

    function setForeign(SpokeStorage.RelayerType relayerType_, uint16 chainId_, bytes32 foreignContracts_) internal{

        SpokeStorage.ForeignChain memory s = SpokeStorage.ForeignChain(
            relayerType_,
            chainId_,
            foreignContracts_
        );
        _state.registeredForeignChain.push(s);
        _state.chainRelayerType[chainId_] = relayerType_;
    }

}