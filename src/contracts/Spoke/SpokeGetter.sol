// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "./SpokeSetter.sol";
import "./SpokeStorage.sol";

contract SpokeGetter is SpokeSetter, SpokeState{

    function wormhole() public view returns (IWormhole) {
        return IWormhole(_state.wormhole);
    }

    function tokenBridge() public view returns (ITokenBridge) {
        return ITokenBridge(payable(_state.tokenBridge));
    }

    function wormholeRelayer() public view returns(IWormholeRelayer){
        return IWormholeRelayer(payable(_state.wormholeRelayer));
    }

    function getChainId() public view returns (uint16){
        return _state.chainId;
    }

    function getMeuToken() public view returns(address){
        return _state.meuToken;
    }

    function getMessageGasLimit() public view returns(uint256){
        return _state.messageGasLimit;
    }

    function getTransferGasLimit() public view returns(uint256){
        return _state.transferGasLimit;
    }

    function getRound() public view returns (uint256){
        return _state.round;
    }

    function getEntryFee() public view returns(uint256){
        return _state.entryFee;
    }

    function getMinimumInvestment() public view returns(uint256){
        return _state.minInvestment;
    }

    function getRelayerType(uint16 chainId) public view returns(SpokeStorage.RelayerType){
        return _state.chainRelayerType[chainId];
    }

    function getRoundFinaltime(uint256 _round) public view returns(uint256){
        require(_state.roundStarted == true, "round not started");
        return _state.roundEnds[round];
    }

    function getInvestmentFinaltime(uint256 _round) public view returns(uint256){
        require(_state.roundStarted == true, "round not started");
        return _state.roundInvestmentEnds[_round];
    }

    function getRegisteredForeignEmitter(uint16 chainId) public view returns(bytes32){
        return _state.registeredForeignEmitter[chainId];
    }
}

