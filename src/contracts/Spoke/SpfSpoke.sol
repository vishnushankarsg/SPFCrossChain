// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import "lib/wormhole-solidity-sdk/src/interfaces/IWormholeRelayer.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormholeReceiver.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/ITokenBridge.sol";
import "lib/wormhole-solidity-sdk/src/interfaces/IWormhole.sol";

import "../../libraries/external/BytesLib.sol";
import "../SpfHubSpokeStructs.sol";
import "../SpfHubSpokeMessages.sol";
import "../SpfHubSpokeUtils.sol";
import "./SpokeSetter.sol";
import "./SpokeGetter.sol";
import "./SpokeStorage.sol";

contract SpfSpoke is IWormholeReceiver, SpfHubSpokeStructs, SpfHubSpokeMessages, SpfHubSpokeUtils, SpokeState, SpokeGetter, SpokeSetter, AccessControl{
    using BytesLib for bytes;
    using SafeERC20 for IERC20;

    bytes32 constant SPOKE_ADMIN = keccak256("SPOKE_ADMIN");
    bytes32 constant SPOKE_ACCESS_ROLE = keccak256("SPOKE_ACCESS_ROLE");

    mapping(uint256 => WinnerToken[3]) public roundWinners;
    mapping(uint256 => mapping(address => WinnerToken)) winnerInfo;
    mapping(uint256 => mapping(address => bool)) public projectIsWinner;
    mapping(uint256 => mapping(address => ScorePayload)) public projectScoreInfo;

    mapping(uint256 => mapping(address => uint256)) private userTotalInvested;
    mapping(uint256 => mapping(address => bool)) private isUserInvested;
    mapping(uint256 => mapping(address => mapping(address => bool))) public userClaimedToken; 

    mapping(uint256 => uint256) private totalInvestedInPool;

    mapping(uint256 => mapping(address => mapping(address => uint256))) private deposits;
    mapping(uint256 => mapping(address => Project)) private projectRegistered;

    IERC20 metaunit;

    event poolCreated(uint256 round, uint16 chainId, address tokenAddress, uint256 tokenStaked, uint256 entryPrice);

    event projectWithdraw(address creator, address token, uint256 amount);

    event invested(uint256 round, uint16 chainId, address originContract, address investor, uint256 amount);

    event genericMessage(uint16 chainId, address targetAddress, uint64 messageSequence);

    event genericTransfer(uint16 chainId, address targetAddress, address token, uint256 amount, uint64 sequence);

    event reAnalize(uint256 round, address tokenAddress, uint256 fee);

    constructor(
        uint16 _chainId,
        address _metaUnit,
        address _contractAdmin,
        address _contractAccessor,
        uint32 _stakePercent,
        uint32 _entryFee,
        uint32 _minInvestment,
        address _tokenBridge,
        address _wormhole,
        address _wormholeRelayer,
        address _hubContract,
        uint16 _hubChainId,
        uint256 _messageGasLimit,
        uint256 _transferGasLimit,
        uint8 _wormholeFinality
    ) {
        metaUnit = IERC20(_metaUnit);
        
        _setRoleAdmin(SPOKE_ADMIN, DEFAULT_ADMIN_ROLE);
        _grantRole(SPOKE_ADMIN, _contractAdmin);
        _grantRole(SPOKE_ACCESS_ROLE, _contractAccessor);

        setChainId(_chainId);
        setMeuToken(_metaUnit);
        setStakePercentage(_stakePercent);
        setEntryFee(_entryFee);
        setMinInvestment(_minInvestment);
        setGasLimit(_messageGasLimit, _transferGasLimit);

        setWormhole(_wormhole);
        setTokenBridge(_tokenBridge);
        setWormholeRelayer(_wormholeRelayer);
        setWormholeFinality(_wormholeFinality);

        setRound(1);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages, // additionalMessages
        bytes32,
        uint16 sourceChain,
        bytes32
    ) public payable override{
        require(msg.sender == _state.wormholeRelayer, "Only relayer allowed");

        (uint8 action_, bytes _payload) = abi.decode(
            payload,
            (uint8, bytes)
        );

        Action _action = Action(uint8(action_));

        if (_action == Action.Claim){

            ClaimPayload cp = decodeClaimPayload(_payload);

            IERC20 winner_token = toCrossChainFormat(cp.winnerToken);

            uint256 finalAmounnt = (projectRegistered[cp.round][winner_token].amount * ((cp.userInvested * 1000) / totalInvestedInPool[cp.round])) / 1000;

            winner_token.safeTransfer(winner_token, fromCrossChainFormat(cp.recepientAccount), finalAmount);
        }

        if(_action == Action.Round){
            RoundPayload cp = decodeRoundPayload(_payload);

            _state.roundStarted = cp.roundStarted;
            setRoundInfo(getRound(), cp.roundEnds);
        }

        if(_action == Action.Score){
            ScorePayload sp = decodeScorePayload(_payload);

            address projectAddress = fromCrossChainFormat(sp.tokenAddress);

            projectScoreInfo[getRound()][projectAddress] = _payload;

        }

        if(_action == Action.Winners){
            WinnersPayload wsp = decodeWinnersPayload(_payload);
            roundWinners[wsp.round] = wsp.winners;

            for(uint i = 0; i < wsp.winners.length; i++){
                address tokenAddress = fromCrossChainFormat(wsp.winners[i].tokenAddress);
                if(tokenAddress == fromCrossChainFormat(projectRegistered[wsp.round][tokenAddress].tokenAddress)){
                    winnerInfo[wsp.round][tokenAddress] = wsp.winners[i];
                    projectIsWinner[wsp.round][tokenAddress] = true;
                }
            }

            _state.round++;
            _state.roundStarted = false;

        }
    }

    function receiveMessage(bytes memory encodedMessage) public {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (
            IWormhole.VM memory wormholeMessage,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedMessage);

        // confirm that the Wormhole core contract verified the message
        require(valid, reason);

        // verify that this message was emitted by a registered foreign emitter
        require(verifyEmitter(wormholeMessage), "unknown emitter");

        (uint8 action_, bytes _payload) = abi.decode(
            wormholeMessage.payload,
            (uint8, bytes)
        );

        Action _action = Action(uint8(action_));

        if (_action == Action.Claim){

            ClaimPayload cp = decodeClaimPayload(_payload);

            IERC20 winner_token = toCrossChainFormat(cp.winnerToken);

            uint256 finalAmounnt = (projectRegistered[cp.round][winner_token].amount * ((cp.userInvested * 1000) / totalInvestedInPool[cp.round])) / 1000;

            winner_token.safeTransfer(winner_token, fromCrossChainFormat(cp.recepientAccount), finalAmount);
        }

        if(_action == Action.Round){
            RoundPayload cp = decodeRoundPayload(_payload);

            _state.roundStarted = cp.roundStarted;
            setRoundInfo(getRound(), cp.roundEnds);
        }

        if(_action == Action.Score){
            ScorePayload sp = decodeScorePayload(_payload);

            address projectAddress = fromCrossChainFormat(sp.tokenAddress);

            projectScoreInfo[getRound()][projectAddress] = _payload;

        }

        if(_action == Action.Winners){
            WinnersPayload wsp = decodeWinnersPayload(_payload);
            roundWinners[wsp.round] = wsp.winners;

            for(uint i = 0; i < wsp.winners.length; i++){
                address tokenAddress = fromCrossChainFormat(wsp.winners[i].tokenAddress);
                if(tokenAddress == fromCrossChainFormat(projectRegistered[wsp.round][tokenAddress].tokenAddress)){
                    winnerInfo[wsp.round][tokenAddress] = wsp.winners[i];
                    projectIsWinner[wsp.round][tokenAddress] = true;
                }
            }

            _state.round++;
            _state.roundStarted = false;

        }



    }

    function createPool(address _tokenAddress) public payable {
        IERC20 token = IERC20(_tokenAddress);
        uint256 _stake_amount = (token.totalSupply() * _state.stakePercentage) / 100;
        
        token.safeTransferFrom(msg.sender, address(this), _stake_amount);

        deposits[getRound()][msg.sender][_tokenAddress] = _stake_amount;

        Project memory pool = Project(
            getRound(),
            getChainId(),
            toCrossChainFormat(address(this)),
            toCrossChainFormat(_tokenAddress),
            toCrossChainFormat(msg.sender),
            _stake_amount,
            0,
            ""
        );

        projectRegistered[getRound()][_tokenAddress] = pool;

        RegisterPayload memory rp = new RegisterPayload(
            getChainId(),
            getRound(),
            toCrossChainFormat(address(this)),
            toCrossChainFormat(_tokenAddress),
            toCrossChainFormat(msg.sender),
            _stake_amount
        );

        bytes encodePayload = encodeRegisterPayload(rp);
        bytes _parsedPayload = parsedActionEncode(Action.Register, encodePayload);

        SpokeStorage.RelayerType _relayerType = chainRelayerType[getChainId()];

        sendCrossChainTransfer(
            _relayerType, 
            getHubChainId(), 
            getHubContract(),
            _parsedPayload,
            getMeuToken(),
            getEntryFee()
        );

        emit poolCreated(
            getRound(),
            getChainId(),
            _tokenAddress,
            _stake_amount,
            _state.entryPrice
        );
    }

    function reAnalyze(uint256 _round, address _tokenAddress ) external {
        require(deposits[_round][msg.sender][_tokenAddress] > 0, "Project not createdPool this round");

        ReanalyzePayload rap = new ReanalyzePayload(
            getChainId(),
            toCrossChainFormat(address(this)),
            toCrossChainFormat(_tokenAddress)
        );

        bytes encodePayload = encodeReAnalizePayload(rap);
        bytes parsePaylaod = parsedActionEncode(Action.Reanalyze, encodePayload);

        SpokeStorage.RelayerType _relayerType = chainRelayerType[getChainId()];

        sendCrossChainTransfer(
            _relayerType, 
            getHubChainId(), 
            getHubContract(),
            _parsedPayload,
            getMeuToken(),
            getEntryFee()
        );

        emit reAnalize(_round, _tokenAddress, _state.entryFee);
    }

    function projectWithdraw(address _tokenAddress, uint256 _round) public {
        require(_round < getRound(), "Round is active");
        require(!projectIsWinner[_round][_tokenAddress], "You won this round");
        require(deposits[_round][msg.sender][_tokenAddress] > 0, "you are not the participant");

        uint256 amount = deposits[_round][msg.sender][_token_address];
        deposits[_round][msg.sender][_token_address] = 0;
        IERC20(_token_address).transferFrom(address(this), msg.sender, amount);

        emit projectWithdrawn(msg.sender, _token_address, amount);
    }

    function invest(uint256 _amount) public {
        require(_amount >= _state.minInvestment, "Amount too small");
        if(getRoundStarted()){
            require(block.timestamp > _state.roundInvestmentEnds[getRound()],"The investment time is ended");
        }
        InvestPayload ip = new InvestPayload(
            getRound(),
            _amount
        );

        bytes encodePayload = encodeInvestPayload(ip);

        bytes parsedPayload = parcedActionEncode(Action.Invest, encodePayload);
        
        sendCrossChainTransfer(
            SpokeStorage.RelayerType.Standard,
            _state.hubChainId,
            toCrossChainFormat(_state.hubContractAddress),
            parsedPayload, 
            getMeuToken(),
            _amount 
        );

        userTotalInvested[getRound()][msg.sender] += _amount;
        isUserInvested[getRound()][msg.sender] = true;
        emit invested(getRound(), getChainId(), address(this), msg.sender, _amount);
    }

    function userClaimToken(uint256 _round, address _winnerToken, bytes32 _recepient) public payable{
        require(_state.roundEnds[_round] < block.timestamp, "Round is Active");
        require(!userClaimedToken[_round][msg.sender][_winnerToken],"claimed");
        require(isUserInvested[_round][msg.sender], "Not invested");
        if(
            _winnerToken == projectRegistered[_round][_winnerToken].fromCrossChainFormat(tokenAddress) && getChainId() == projectRegistered[_round][_winnerToken].chainId
        ){
            IERC20 winner_token = _winnerToken;
            uint256 claimAmount = (projectRegistered[_round][_winnerToken].amount *
                    ((userTotalInvested[_round][msg.sender] * 1000) / totalInvestedInPool[_round])) / 1000;

            uint256 finalAmount = claimAmount / roundWinners[_round].length();
            winner_token.safeTransfer(_winnerToken, recepient, finalAmount);

            userClaimedToken[_round][msg.sender][_winnerToken] = true;
        }else {
            SpokeStorage.RelayerType relayerType = getRelayerType(winnerInfo[_round][_winnerToken].chainId);

            ClaimPayload claimInfo = new ClaimPayload(
                _round,
                toCrossChainFormat(_winnerToken),
                _recepient,
                userTotalInvested[_round][msg.sender]
            );

            bytes encodeClaim = encodeClaimPayload(claimInfo);
            bytes parsedPayload = parcedActionEncode(Action.Claim, encodeClaim);
            sendCrossChainMessage(
                relayerType, 
                winnerInfo[_round][_winnerToken].chainId,
                toCrossChainFormat(winnerInfo[_round][_winnerToken].originContract),
                parsedPayload
            );
            userClaimedToken[_round][msg.sender][_winnerToken] = true;
        }
    }

    function changeBaseStruct
    (
        uint32 _winnersMax,
        uint32 _minQualified,
        uint32 _intervalDays, 
        uint32 _stakePercent, 
        uint256 _entryFee, 
        uint256 _minInvestment,
        uint256 _messageGasLimit,
        uint256 _transferGasLimit
    ) external onlyRole(HUB_ADMIN, HUB_ACCESS_ROLE) {
        require(!getRoundStarted(), "Round Started");
        setWinnersMax(_winnersMax);
        setQualifiedMin(_minQualified);
        setIntervalDays(_intervalDays);
        setStakePercentage(_stakePercent);
        setEntryFee(_entryFee);
        setMinInvestment(_minInvestment);
        setGasLimit(_messageGasLimit, _transferGasLimit);
    }

    function addForeignChain(SpokeStorage.RelayerType _relayerType, uint16 _chainId, address _foreignContract) external onlyRole(HUB_ADMIN, HUB_ACCESS_ROLE){
        setForeign(_relayerType, _chainId, toCrossChainFormat(_foreignContract));
    }
    
    // Internal functions

    function quoteMessageFee(
        uint16 targetChain
    ) internal returns (uint256 cost) {
        (cost, ) = wormholeRelayer().quoteEVMDeliveryPrice(
            targetChain,
            0,
            getMessageGasLimit()
        );
    }

    function sendCrossChainMessage(SpokeStorage.RelayerType relayerType, uint16 targetChain, address targetAddress, bytes payload) internal {
        if(relayerType == SpokeStorage.RelayerType.Standart){
            uint cost = quoteMessageFee(targetChain);
            require(msg.value == cost);
            wormholeRelayer().sendPayloadToEvm{value: cost}(
                targetChain,
                targetAddress,
                payload,
                0,
                getMessageGasLimit()
            );
        }else if(relayerType == SpokeStorage.RelayerType.Generic){
            uint wormholeFee = wormhole().messageFee();

            uint64 messageSequence = wormhole().publishMessage{value: wormholeFee}(
            0,
            _entryInfo,
            wormholeFinality()
            );
            emit genericMessage(targetChain, targetAddress, messageSequence);
        }  
    }

    function quoteEvmTransferFee(
        uint16 targetChain
    ) internal returns (uint256 cost) {
        uint256 transferCost;
        (deliveryCost,) = wormholeRelayer().quoteEVMDeliveryPrice(targetChain, 0, getTransferGasLimit());
        cost = deliveryCost + wormhole().messageFee();
    }

    function sendCrossChainTransfer(SpokeStorage.RelayerType relayerType, uint16 targetChain, address targetAddress, bytes payload, address token, uint256 amount) internal {
        if(relayerType == SpokeStorage.RelayerType.Standard){
            uint cost = quoteEvmTransferFee(targetChain);
            require(msg.value == cost);

            IERC20(token).transferFrom(msg.sender, address(this), amount);
            IERC20(token).approve(address(tokenBridge()), amount);

            uint64 sequence = tokenBridge().transferTokens{value: wormhole().messageFee()}(
                token, amount, targetChain, toWormholeFormat(targetAddress), 0, 0
            );

            VaaKey[] memory additionalVaas = new VaaKey[](1);
            additionalVaas[0] = VaaKey({
                emitterAddress: toWormholeFormat(address(tokenBridge())),
                sequence: sequence,
                chainId: wormhole().chainId()
            });

            wormholeRelayer().sendVaasToEvm{value: cost - wormhole().messageFee()}(
                targetChain,
                targetAddress,
                payload,
                0, // no receiver value needed since we're just passing a message + wrapped token
                getTransferGasLimit(),
                additionalVaas
            );

        } else if(relayerType == SpokeStorage.RelayerType.Generic){
            require(
                normalizeAmount(amount, getDecimals(token)) > 0,
                "normalized amount must be > 0"
            );
            uint256 wormholeFee = wormhole().messageFee();
            require(msg.value == wormholeFee, "insufficient value");

            IERC20(token).transferFrom(msg.sender, address(this), amount);
            IERC20(token).approve(address(tokenBridge()), amount);

            uint64 sequence = tokenAddress().transferTokensWithPayload{value: wormholeFee}(
                token,
                amount,
                targetChain,
                toCrossChainFormat(targetAddress),
                0,
                payload
            );
            emit genericTransfer(targetChain, targetAddress, token, amount, sequence);
        }
    }
    
    function verifyEmitter(IWormhole.VM memory vm) internal view returns(bool){
        return getRegisteredForeignEmitter(vm.emitterChainId) == vm.emitterAddress;
    }

}