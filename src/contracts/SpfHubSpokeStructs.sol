// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract SpfHubSpokeStructs {

    enum Action{
        Round,
        Score,
        Claim,
        Register,
        Invest,
        Reanalyze,
        Winners
    }

    struct RegisterPayload{
        uint16 chainId;
        uint256 round;
        bytes32 originContract;
        bytes32 tokenAddress;
        bytes32 creator;
        uint256 tokenAmount;
    }

    struct ReanalyzePayload{
        uint16 chainId;
        bytes32 originContract;
        bytes32 tokenAddress;
    }

    struct InvestPayload{
        uint256 round;
        uint256 amount;
    }

    struct WinnerToken{
        uint16 chainId;
        bytes32 originContract;
        bytes32 tokenAddress;
    }

    struct WinnersPayload{
        uint256 round;
        uint8 totalWinners;
        WinnerToken[] winners;
    }

    struct ScorePayload{ //only message
        bytes32 tokenAddress;
        uint32 score;
        string analyzeReportIpfs;
    }

    struct ClaimPayload{ //only message
        uint256 round;
        bytes32 winnerToken;
        bytes32 recepientAccount; 
        uint256 userInvested;      
    }

    struct RoundPayload{ //only message
        bool roundStarted;
        uint256 roundEnds;
    }

    struct Project{
        uint256 round;
        uint16 chainId;
        bytes32 originContract;
        bytes32 tokenAddress;
        bytes32 creator;
        uint256 tokenAmount;
        uint32 score;
        string analyzeReportIpfs;
    }

}