// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

contract HubStorage {

    enum RelayerType{
        Standard,
        Generic
    }

    struct SpokeChain{
        RelayerType relayerType;
        uint16 chainId;
        bytes32 spokeAddress;
    }
    struct State{
        uint16 chainId;
        address meuToken;

        uint256 messageGasLimit;
        uint256 transferGasLimit;

        uint256 round;
        bool roundStarted;
        uint8 roundNQualified;
        
        uint32 nWinnersMax;
        uint32 nQualifiedMin;
        uint32 intervalDays;

        uint32 stakePercentage;
        uint256 entryFee;
        uint256 minInvestment;

        address tokenBridge;
        address wormhole;
        address wormholeRelayer;

        uint8 wormholeFinality;

        mapping (uint256 => uint256) roundEnds;
        mapping (uint256 => uint256) roundInvestmentEnds;

        mapping(uint16 => bytes32) registeredSpokeEmitter;
        mapping(uint16 => RelayerType) chainRelayerType;
        SpokeChain[] registeredSpoke;
    }
}

contract HubState {
    HubStorage.State _state;
}