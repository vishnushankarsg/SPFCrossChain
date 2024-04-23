// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./SpfHubSpokeStructs.sol";

contract HubSpokeMessages is SpfHubSpokeStructs {
    using BytesLib for bytes;

    // Encode Crosschain Transfer Payload
    function encodeRegisterPayload(RegisterPayload memory _payload) internal pure returns(bytes memory){
        return abi.encode(uint16(_payload.chainId), bytes32(_payload.originContract), bytes32(_payload.tokenAddress), bytes32(_payload.creator), uint256(_payload.tokenAmount));
    }

    function encodeReanalyzePayload(ReanalyzePayload memory _payload) internal pure returns(bytes memory){
        return abi.encode(uint16(_payload.chainId), bytes32(_payload.originContract), bytes32(_payload.tokenAddress));
    }

    function encodeInvestPayload(InvestPayload memory _payload) internal pure returns(bytes memory){
        return abi.encode(uint256(_payload.round), uint256(_payload.amount));
    }

    function encodeWinnersPayload(WinnersPayload memory _payload) internal pure returns(bytes memory){
        return abi.encode(uint256(_payload.round), uint8(_payload.totalWinners), WinnerToken[](_payload.winners));
    }


    //Encode Crosschain Messages payload
    function encodeScorePayload(ScorePayload memory _payload) internal pure returns(bytes memory){
        return abi.encode(bytes32(_payload.tokenAddress), uint32(_payload.score), string(_payload.analyzeReportIpfs));
    }

    function encodeClaimPayload(ClaimPayload memory _payload) internal pure returns(bytes memory){
        return abi.encode(uint256(_payload.round), bytes32(_payload.winnerToken), bytes32(_payload.recepientAccount), uint256(_payload.userInvested));
    }

    function encodeRoundPayload(RoundPayload memory _payload) internal pure returns(bytes memory){
        return abi.encode(bool(_payload.roundStarted), uint256(_payload.roundEnds));
    }

    //Decode Crosschain Transfer payload
    function decodeRegisterPayload(bytes memory serialized) internal pure returns(RegisterPayload memory _payload){

        (uint16 chainId_, bytes32 originContract_, bytes32 tokenAddress_, bytes32 creator_, uint256 tokenAmount_) = abi.decode(
            serialized,
            (uint16, bytes32, bytes32, bytes32, uint256)
        );

        _payload.chainId = chainId_;
        _payload.originContract = originContract_;
        _payload.tokenAddress = tokenAddress_;
        _payload.creator = creator_;
        _payload.tokenAmount = tokenAmount_;
    }

    function decodeReanalyzePayload(bytes memory serialized) internal pure returns(ReanalyzePayload memory payload){

        (uint8 chainId_, bytes32 originContract_, bytes32 tokenAddress_) = abi.decode(
            serialized,
            (uint8, bytes32, bytes32)
        );

        payload.chainId = chainId_;
        payload.originContract = originContract_;
        payload.tokenAddress = tokenAddress_;
    }

    function decodeInvestPayload(bytes memory serialized) internal pure returns(InvestPayload memory payload){

        (uint256 round_, uint256 amount_) = abi.decode(
            serialized,
            
            (uint256, uint256)
        );
        payload.round = round_;
        payload.amount = amount_;
    }

    function decodeWinnersPayload(bytes memory serialized) internal pure returns(WinnersPayload memory payload){

        (uint256 round_, uint8 totalWinners_, WinnerToken[] memory winners_) = abi.decode(
            serialized,
            (uint256, uint8, WinnerToken[])
        );

        payload.round = round_;
        payload.totalWinners = totalWinners_;
        payload.winners = winners_;
    }

    //Decode Crosschain Messages payload
    function decodeScorePayload(bytes memory serialized) internal pure returns(ScorePayload memory payload){

        (bytes32 tokenAddress_, uint32 score_, string memory analyzeReportIpfs_) = abi.decode(
            serialized,
            (bytes32, uint32, string)
        );

        payload.tokenAddress = tokenAddress_;
        payload.score = score_;
        payload.analyzeReportIpfs = analyzeReportIpfs_;
    }

    function decodeClaimPayload(bytes memory serialized) internal pure returns(ClaimPayload memory payload){

        (uint256 round_, bytes32 winnerToken_, bytes32 recepient_, uint256 userInvested_ ) = abi.decode(
            serialized,
            (uint256, bytes32, bytes32, uint256)
        );

        payload.round = round_;
        payload.winnerToken = winnerToken_;
        payload.recepientAccount = recepient_;
        payload.userInvested = userInvested_;
    }

    function decodeRoundPayload(bytes memory serialize) internal pure returns(RoundPayload memory payload){

        (bool roundStarted_, uint256 roundEnds_) = abi.decode(
            serialize,
            (bool, uint256)
        );

        payload.roundStarted = roundStarted_;
        payload.roundEnds = roundEnds_;
    }
}