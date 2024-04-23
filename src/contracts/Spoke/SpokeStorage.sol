// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

contract SpokeStorage{

    enum RelayerType {
        Standard,
        Generic
    }

    struct ForeignChain{
        RelayerType relayerType;
        uint16 chainId;
        bytes32 foreignChainAddress;
    }

    struct State{
        uint16 chainId;
        address meuToken;

        uint256 messageGasLimit;
        uint256 transferGasLimit;

        uint256 round;
        bool roundStarted;

        uint32 stakePercentage;
        uint32 entryFee;
        uint32 minInvestment;
        
        address tokenBridge;
        address wormhole;
        address wormholeRelayer;

        uint16 hubChainId;
        address hubContractAddress;

        uint8 wormholeFinality;
        uint32 feePrecision;
        uint32 relayerFeePercent;

        mapping (uint256 => uint256) roundEnds;
        mapping (uint256 => uint256) roundInvestmentEnds;

        mapping(uint16 => bytes32) registeredForeignEmitters;
        mapping(uint16 => RelayerType) chainRelayerType;
    }
}

contract SpokeState {
    SpokeStorage.State _state;
}