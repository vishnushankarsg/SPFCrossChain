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
import "./HubSetter.sol";
import "./HubGetter.sol";
import "./HubStorage.sol";
// import "./IPositionNFT.sol";

contract SPFHub is IWormholeReceiver, SpfHubSpokeStructs, SpfHubSpokeMessages, SpfHubSpokeUtils, HubState, HubGetter, HubSetter, AccessControl {
    using BytesLib for bytes;
    using SafeERC20 for IERC20;

    bytes32 constant HUB_ADMIN = keccak256("HUB_ADMIN");
    bytes32 constant HUB_ACCESS_ROLE = keccak256("HUB_ACCESS_ROLE");
    bytes32 constant HUB_SERVICE_ROLE = keccak256("HUB_SERVICE_ROLE");

    Project[] pools;
    Project[] sortScore;
    
    address[] private founders;
    mapping(uint256 => WinnerToken[]) public roundWinners;
    mapping(uint256 => mapping(address => WinnerToken)) winnerInfo;
    mapping(uint256 => mapping(address => bool)) public projectIsWinner;

    mapping(uint256 => mapping(address => uint256)) private userTotalInvested;
    mapping(uint256 => mapping(address => bool)) private isUserInvested;
    mapping(uint256 => mapping(address => mapping(address => bool))) public userClaimedToken; 

    mapping(uint256 => uint256) private totalMeuInPool;
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


    modifier needsUpdate() {
        require(
            pools.length >= 20 ||
                (roundStarted &&
                    block.timestamp >
                    roundStartTimestamp + SPFOptions.IntervalDays * 1 days),
            "Too early"
        );
        _;
    }

    constructor(
        uint16 _chainId,
        address _metaunit,
        address _contractAdmin,
        address _contractAccessor,
        address _service,
        address[] memory _founders,
        uint32 _winnersMax,
        uint32 _qualifiedMin,
        uint32 _intervalDays,
        uint32 _stakePercent,
        uint32 _entryFee,
        uint32 _minInvestment,
        address _tokenBridge,
        address _wormhole,
        address _wormholeRelayer,
        uint256 _messageGasLimit,
        uint256 _transferGasLimit,
        uint8 _wormholeFinality
    ) {
        metaunit = IERC20(_metaunit);
        founders = _founders;

        _setRoleAdmin(HUB_ADMIN, DEFAULT_ADMIN_ROLE);
        _grantRole(HUB_ADMIN, _contractAdmin);
        _grantRole(HUB_ACCESS_ROLE, _contractAccessor);
        _grantRole(HUB_SERVICE_ROLE, _service);

        setChainId(_chainId);
        setWinnersMax(_winnersMax);
        setQualifiedMin(_qualifiedMin);
        setInternalDays(_intervalDays);
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

        if (_action == Action.Register){
            require(additionalMessages.length == 2, "Expected 2 additional VAA keys for token transfers");

            RegisterPayload rp = decodeRegisterPaylaod(_payload);

            Project memory pool = Project(
                getRound(),
                rp.chainId,
                rp.originContract,
                rp.tokenAddress,
                rp.creator,
                rp.tokenAmount,
                0,
                ""
            );

            IWormhole.VM memory parsedVM = wormhole().parseVM(additionalMessages[0]);
            ITokenBridge.Transfer memory transfer = tokenBridge().parseTransfer(parsedVM.payload);
            tokenBridge().completeTransfer(additionalMessages[0]);

            address wrappedTokenAddress = transfer.tokenChain == wormhole().chainId() ? fromCrossChainFormat(transfer.tokenAddress) : tokenBridge().wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
        
            uint256 decimals = getDecimals(wrappedTokenAddress);
            uint256 finalAmount = normalizeAmount(transfer.amount, decimals);
            
            IERC20(wrappedTokenAddress).transfer(address(this), finalAmount); // Metaunit

            pools.push(pool);

            emit poolCreated(
                getRound(),
                rp.chainId,
                fromCrossChainFormat(rp.tokenAddress),
                rp.tokenAmount,
                _state.entryPrice
            );
        }
        if(_action == Action.Reanalyze){
            require(additionalMessages.length == 2, "Expected 2 additional VAA keys for token transfers");

            ReanalyzePayload rp = decodeReanalyzePayload(_payload);

            totalMeuInPool[rp.round] += _state.entryFee;
            
            IWormhole.VM memory parsedVM = wormhole().parseVM(additionalMessages[0]);
            ITokenBridge.Transfer memory transfer = tokenBridge().parseTransfer(parsedVM.payload);
            tokenBridge().completeTransfer(additionalMessages[0]);

            address wrappedTokenAddress = transfer.tokenChain == wormhole().chainId() ? fromCrossChainFormat(transfer.tokenAddress) : tokenBridge().wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
        
            uint256 decimals = getDecimals(wrappedTokenAddress);
            uint256 finalAmount = normalizeAmount(transfer.amount, decimals);
            
            IERC20(wrappedTokenAddress).transfer(address(this), finalAmount); // Metaunit

            emit reAnalize(getRound(), toCrossChainFormat(rp.tokenAddress), getEntryFee());
        }

        if (_action == Action.Invest){
            require(additionalMessages.length == 2, "Expected 2 additional VAA keys for token transfers");

            InvestPayload ip = decodeInvestPayload(_payload);
            
            totalMeuInPool[ip.round] += ip.amount;
            totalInvestedInPool[ip.round] += ip.amount;
            
            IWormhole.VM memory parsedVM = wormhole().parseVM(additionalMessages[0]);
            ITokenBridge.Transfer memory transfer = tokenBridge().parseTransfer(parsedVM.payload);
            tokenBridge().completeTransfer(additionalMessages[0]);

            address wrappedTokenAddress = transfer.tokenChain == wormhole().chainId() ? fromCrossChainFormat(transfer.tokenAddress) : tokenBridge().wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
        
            uint256 decimals = getDecimals(wrappedTokenAddress);
            uint256 finalAmount = normalizeAmount(transfer.amount, decimals);
            
            IERC20(wrappedTokenAddress).transfer(address(this), finalAmount); // Metaunit

        }

        if (_action == Action.Claim){

            ClaimPayload cp = decodeClaimPayload(_payload);

            IERC20 winner_token = toCrossChainFormat(cp.winnerToken);

            uint256 finalAmounnt = (projectRegistered[cp.round][winner_token].amount * ((cp.userInvested * 1000) / totalInvestedInPool[cp.round])) / 1000;

            winner_token.safeTransfer(winner_token, fromCrossChainFormat(cp.recepientAccount), finalAmount);

        }
    }


    function fetchLocalAddressFromTransferMessage(
        bytes memory payload
    ) public view returns (address localAddress) {
        // parse the source token address and chainId
        bytes32 sourceAddress = payload.toBytes32(33);
        uint16 tokenChain = payload.toUint16(65);

        // Fetch the wrapped address from the token bridge if the token
        // is not from this chain.
        if (tokenChain != chainId()) {
            // identify wormhole token bridge wrapper
            localAddress = tokenBridge().wrappedAsset(tokenChain, sourceAddress);
            require(localAddress != address(0), "token not attested");
        } else {
            // return the encoded address if the token is native to this chain
            localAddress = toCrossChainFormat(sourceAddress);
        }
    }


    function redeemTransferWithPayload(bytes memory encodedTransferMessage) public{
        (
            IWormhole.VM memory wormholeMessage,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedTransferMessage);

        // confirm that the Wormhole core contract verified the message
        require(valid, reason);

        // verify that this message was emitted by a registered spoke emitter
        require(verifyEmitter(wormholeMessage), "unknown emitter");

        (uint8 action_, bytes _payload) = abi.decode(
            wormholeMessage.payload,
            (uint8, bytes)
        );

        Action _action = Action(uint8(action_));

        if (_action == Action.Register){

            RegisterPayload rp = decodeRegisterPaylaod(_payload);

            Project memory pool = Project(
                getRound(),
                rp.chainId,
                rp.originContract,
                rp.tokenAddress,
                rp.creator,
                rp.tokenAmount,
                0,
                ""
            );

            address localTokenAddress = fetchLocalAddressFromTransferMessage(
            wormholeMessage.payload
            );

            uint256 balanceBefore = getBalance(localTokenAddress);

            bytes memory transferPayload = tokenBridge().completeTransfer(encodedTransferMessage);
            
            uint256 amountTransferred = getBalance(localTokenAddress) - balanceBefore;
            
            SafeERC20.safeTransfer(
                IERC20(localTokenAddress),
                address(this),
                amountTransferred
            );
            
            pools.push(pool);

            emit poolCreated(
                getRound(),
                rp.chainId,
                fromCrossChainFormat(rp.tokenAddress),
                rp.tokenAmount,
                _state.entryPrice
            );
        }
        if(_action == Action.Reanalyze){

            ReanalyzePayload rp = decodeReanalyzePayload(_payload);

            totalMeuInPool[rp.round] += _state.entryFee;
            
            address localTokenAddress = fetchLocalAddressFromTransferMessage(
            wormholeMessage.payload
            );

            uint256 balanceBefore = getBalance(localTokenAddress);

            bytes memory transferPayload = tokenBridge().completeTransfer(encodedTransferMessage);
            
            uint256 amountTransferred = getBalance(localTokenAddress) - balanceBefore;
            
            SafeERC20.safeTransfer(
                IERC20(localTokenAddress),
                address(this),
                amountTransferred
            );
            // Metaunit

            emit reAnalize(getRound(), toCrossChainFormat(rp.tokenAddress), getEntryFee());
        }

        if (_action == Action.Invest){

            InvestPayload ip = decodeInvestPayload(_payload);
            
            totalMeuInPool[ip.round] += ip.amount;
            totalInvestedInPool[ip.round] += ip.amount;
            
            address localTokenAddress = fetchLocalAddressFromTransferMessage(
            wormholeMessage.payload
            );

            uint256 balanceBefore = getBalance(localTokenAddress);

            bytes memory transferPayload = tokenBridge().completeTransfer(encodedTransferMessage);
            
            uint256 amountTransferred = getBalance(localTokenAddress) - balanceBefore;
            
            SafeERC20.safeTransfer(
                IERC20(localTokenAddress),
                address(this),
                amountTransferred
            );

        }

        if (_action == Action.Claim){
            ClaimPayload cp = decodeClaimPayload(_payload);

            IERC20 winner_token = toCrossChainFormat(cp.winnerToken);

            uint256 finalAmounnt = (projectRegistered[cp.round][winner_token].amount * ((cp.userInvested * 1000) / totalInvestedInPool[cp.round])) / 1000;

            winner_token.safeTransfer(winner_token, fromCrossChainFormat(cp.recepientAccount), finalAmount);
        }
    }

    function createPool(address _tokenAddress) public {
        require(!_state.roundStarted || _state.roundEnds > block.timestamp, "Previous round not resolve yet");

        IERC20 token = IERC20(_tokenAddress);
        uint256 _stake_amount = (token.totalSupply() * _state.stakePercentage) / 100;
        
        token.safeTransferFrom(msg.sender, address(this), _stake_amount);
        metaunit.transferFrom(msg.sender, address(this), _state.entryFee);

        totalMeuInPool[getRound()] += _state.entryFee;
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
        
        pools.push(pool);
        projectRegistered[getRound()][_tokenAddress] = pool;

        emit poolCreated(
            getRound(),
            getChainId(),
            _tokenAddress,
            _stake_amount,
            _state.entryPrice
        );
    }

    function reAnalyze(uint256 _round, address _tokenAddress) external {
        require(deposits[_round][msg.sender][_tokenAddress] > 0, "Project not created Pool in this round");
        metaunit.transferFrom(msg.sender, address(this), _state.entryFee);
        totalMeuInPool[getRound()] += _state.entryFee;
        emit reAnalize(_round, _tokenAddress, _state.entryFee);
    }

    function projectWithdraw(address _tokenAddress, uint256 _round) public {
        require(_round < getRound(), "Round is active");
        require(!projectIsWinner[_round][_tokenAddress], "You won this round");
        require(deposits[_round][msg.sender][_tokenAddress] > 0, "you are not participated");

        uint256 amount = deposits[_round][msg.sender][_token_address];
        deposits[_round][msg.sender][_token_address] = 0;
        IERC20(_token_address).transferFrom(address(this), msg.sender, amount);

        emit projectWithdrawn(msg.sender, _token_address, amount);
    }

    function invest(uint256 _amount) public {
        require(_amount >= _state.minInvestment, "Amount too small");
        if(getRoundStarted()){
            require(block.timestamp < _state.roundInvestmentEnds[getRound()],"The investment time is ended");
        }
        metaunit.transferFrom(msg.sender, address(this), _amount);

        userTotalInvested[getRound()][msg.sender] += _amount;
        isUserInvested[getRound()][msg.sender] = true;
        totalMeuInPool[getRound()] += _amount;
        totalInvestedInPool[getRound()] += _amount;
        emit invested(getRound(), getChainId(), address(this), msg.sender, _amount);
    }

    function userClaimToken(uint256 _round, address _winnerToken, bytes32 recepient) public payable{
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
            HubStorage.RelayerType relayerType = getRelayerType(winnerInfo[_round][_winnerToken].chainId);

            ClaimPayload aapInfo = new ClaimPayload(
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

    function score(
        uint32 _score,
        bool _is_qualified,
        address _token_address,
        string memory _ipfs
    ) public payable onlyRole(SERVICE_ROLE) {

        bytes32 _tokenAddess = toCrossChainFormat(_token_address);
        if (_is_qualified == true) {
            _state.roundNQualified++;
            if(_state.roundNQualified > 0 && _state.roundNQualified < 2) {
                _state.roundStarted = true;
                setRoundInfo(getRound(), block.timestamp);

                HubStorage.SpokeChain rs = registeredSpoke;
                uint256 roundEnds = block.timestamp + (_state.intervalDays * 1 days);
                for (uint i = 0; i < rs.length; i++) {
                    HubStorage.RelayerType rt = rs[i].relayerType;
                    RoundPayload roundP = new RoundPayload(
                        true,
                        roundEnds
                    );
                    bytes encodeRP = encodeRoundPayload(roundP);
                    bytes parsedRP = parsedActionEncode(Action.Round, encodeRP);

                    sendCrossChainMessage(
                        rt[i].relayerType,
                        rt[i].chainId,
                        rt[i].spokeAddress,
                        parsedRP
                    );
                }
            }
        }
        for (uint i = 0; i < pools.length; i++) {
            if (_tokenAddress == pools[i].tokenAddress) {
                pools[i].score = _score;
                pools[i].analyzeReportIpfs = _ipfs;
            }
        }
        
    }

    

    function resolve() public payable onlyService needsUpdate {
        sortHighScorer();
        if(_state.roundNQualified < 4){
            WinnerToken memory wt = new WinnerToken(
                    sortScore[0].chainId,
                    sortScore[0].originContract,
                    sortScore[0].tokenAddress
                );
            roundWinners[getRound()][0].push(wt);
            roundWinners[getRound()][0] = sortScore[0];
            projectIsWinner[getRound()][fromCrossChainFormat(roundWinners[getRound()][0].tokenAddress)] = true;
        } else if(_state.roundNQualified > 3){
            for (uint8 i = 0; i < 3; i++){
                WinnerToken memory wt = new WinnerToken(
                    sortScore[i].chainId,
                    sortScore[i].originContract,
                    sortScore[i].tokenAddress
                );
                roundWinners[getRound()][i].push(wt);
                projectIsWinner[getRound()][fromCrossChainFormat(roundWinners[getRound()][i].tokenAddress)] = true;
            }
        }

        for(uint i = 0; i < roundWinners[getRound()].length; i++){

            uint256 distAmount = totalMeuInPool[getRound()] / roundWinners[getRound()].length;
            winnerChainId[getRound()][toCrossChainFormat(roundWinners[getRound()][i].tokenAddress)] = roundWinners[getRound()][i].chainId;

            _distributeMetaunit(roundWinners[getRound()][i], distAmount);
        }

        WinnersPayload wsp = new WinnersPayload(
            getRound(),
            roundWinners[getRound()].length(),
            roundWinners[getRound()]
        );

        bytes winnersInfo = encodeWinnersPayload(wsp);

        bytes parcedPayload = parcedActionEncode(Action.Winners, winnersInfo);

        HubStorage.SpokeChain[] memory rs = _state.registeredSpoke;

        for(uint i = 0; i < rs.length; i++){
            sendCrossChainMessage(rs[i].relayerType, rs[i].chainId, rs[i].spokeAddress, parcedPayload);
        }
        
        _state.round++;
        _state.roundStarted = false;
        
        delete pools;
        delete sortScore;

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

    function addSpokeChain(HubStorage.RelayerType _relayerType, uint16 _chainId, address _spokeContract) external onlyRole(HUB_ADMIN, HUB_ACCESS_ROLE){
        setSpoke(_relayerType, _chainId, toCrossChainFormat(_spokeContract));
        _state.registeredSpokeEmitter[_chainId] = toCrossChainFormat(_spokeContract);
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

    function sendCrossChainMessage(HubStorage.RelayerType relayerType, uint16 targetChain, address targetAddress, bytes payload) internal {
        if(relayerType == HubStorage.RelayerType.Standart){
            uint cost = quoteMessageFee(targetChain);
            require(msg.value == cost);
            wormholeRelayer().sendPayloadToEvm{value: cost}(
                targetChain,
                targetAddress,
                payload,
                0,
                getMessageGasLimit()
            );
        }else if(relayerType == HubStorage.RelayerType.Generic){
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
        (deliveryCost,) = _wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, getTransferGasLimit());
        cost = deliveryCost + wormhole().messageFee();
    }

    function sendCrossChainTransfer(HubStorage.RelayerType relayerType, uint16 targetChain, address targetAddress, bytes payload, address token, uint256 amount) internal {
        if(relayerType == HubStorage.RelayerType.Standard){
            uint cost = quoteEvmTransferFee(targetChain);
            require(msg.value == cost);

            IERC20(token).transferFrom(msg.sender, address(this), amount);
            IERC20(token).approve(address(tokenBridge()), amount);

            uint64 sequence = tokenBridge().transferTokens{value: wormhole.messageFee()}(
                token, amount, targetChain, toWormholeFormat(targetAddress), 0, 0
            );

            VaaKey[] memory additionalMessages = new VaaKey[](1);
            additionalMessages[0] = VaaKey({
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
                additionalMessages
            );

        } else if(relayerType == HubStorage.RelayerType.Generic){
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

    function sortHighScorer() internal {
        Project[] memory tempScore = pools;

        for (uint i = 0; i < tempScore.length - 1; i++) {
            for (uint j = 0; j < tempScore.length - i - 1; j++) {
                if (tempScore[j].score < tempScore[j + 1].score) {
                    (tempScore[j], tempScore[j + 1]) = (
                        tempScore[j + 1],
                        tempScore[j]
                    );
                }
            }
        }

        for (uint i = 0; i < tempScore.length; i++) {
            sortScore.push(tempScore[i]);
        }
    }

    function _distributeMetaunit(uint256 _winner, uint256 _amount) internal {
        Pool memory winner_pool = sortScore[_winner];

        uint256 founder_amount = (_amount * 2) / (10 * founders.length);

        for (uint256 i; i < founders.length; i++) {
            metaunit.transfer(founders[i], founder_amount);
        }

        uint256 finalAmount = _amount - founder_amount;

        if(winner_pool.chainId == getChainId()){
            metaunit.transfer(fromCrossChainFormat(winner_pool.creator), finalAmount);
        }else {
            HubStorage.RelayerType _rType = getRelayerType(winner_pool.chainId);
            
            bytes encodePayload = abi.encode(winner_pool.creator);
            sendCrossChainTransfer(
                rType,
                winner_pool.chainId, // project chainid
                targetAddress, // project origin contract
                finalPayload, // winner payload
                getMeuToken(), //metaunit token address
                finalAmount //metaunits
            );
        }
        emit resolved(round - 1, sortScore[_winner]);
    }

    function verifyEmitter(IWormhole.VM memory vm) internal view returns(bool){
        return getRegisteredSpokeEmitter(vm.emitterChainId) == vm.emitterAddress;
    }

}
