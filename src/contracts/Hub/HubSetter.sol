// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./HubStorage.sol";
contract HubSetter is HubState {

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

    function setWinnersMax(uint32 winnersMax_) internal{
        _state.nWinnersMax = winnersMax_;
    }

    function setQualifiedMin(uint32 qualifiedMin_) internal{
        _state.nQualifiedMin = qualifiedMin_;
    }

    function setIntervalDays(uint32 intervalDays_) internal{
        _state.intervalDays = intervalDays_;
    }

    function setStakePercentage(uint32 stakePercentage_) internal{
        _state.stakePercentage = stakePercentage_;
    }

    function setEntryFee(uint32 entryFee_) internal{
        _state.entryFee = entryFee_;
    }

    function setMinInvestment(uint32 amount_) internal{
        _state.minInvestment = amount_;
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

    function setWormholeFinality(uint8 finality_) internal{
        _state.wormholeFinality = finality_;
    }

    function setRoundInfo(uint256 round_, uint256 timestamp_) internal {
        uint256 interval = _state.intervalDays * 1 days;
        _state.roundEnds[round_] = timestamp_ + interval;
        _state.roundInvestmentEnds[round_] = _state.roundEnds[round_] - 30 minutes;
    }

    function setSpokeEmitter(uint16 chainId_, bytes32 emitter_) internal{
        _state.registeredSpokeEmitter[chainId_] = emitter_;
    }

    function setSpoke(HubStorage.RelayerType relayerType_, uint16 chainId_, bytes32 spokeContracts_) internal{
        HubStorage.SpokeChain memory s = HubStorage.SpokeChain(
            relayerType_,
            chainId_,
            spokeContracts_
        );
        _state.chainRelayerType[chainId_] = relayerType_;
        _state.registeredSpoke.push(s);
        setSpokeEmitter(chainId_, spokeContracts_);
    }

}
