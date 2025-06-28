// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "@chainlink/contracts/src/v0.8/dev/vrf/VRFConsumerBaseV2Plus.sol";
import "@chainlink/contracts/src/v0.8/dev/vrf/libraries/VRFV2PlusClient.sol";
import "./interfaces/IPredictionMarket.sol";

contract PredictionMarket is 
    IPredictionMarket, 
    ReentrancyGuard, 
    AutomationCompatibleInterface,
    VRFConsumerBaseV2Plus 
{
    using SafeERC20 for IERC20;

    // Structs
    struct Market {
        string assetName;           // e.g., "ETH"
        string baseAsset;           // e.g., "USD" 
        uint256 targetPrice;        // Target price in base asset (scaled by 8 decimals)
        uint256 resolutionTime;     // When market resolves
        bool resolved;              // Whether market has been resolved
        bool outcome;               // True if price was HIGHER, false if LOWER
        uint256 finalPrice;         // Final price when resolved
        uint256 totalPool;          // Total amount bet
        uint256 totalHigherBets;    // Total bets on HIGHER
        uint256 totalLowerBets;     // Total bets on LOWER
        uint256 treasuryFee;        // Fee taken by treasury (2%)
        uint256 randomBonusPool;    // Pool for random winner (2%)
        address randomWinner;       // Address of random winner
        bool randomWinnerSelected;  // Whether random winner has been selected
        uint256 automationFee;      // ETH paid for automation
        bool automationRegistered;  // Whether upkeep is registered
    }

    struct Bet {
        address user;
        uint256 amount;
        bool isHigher;              // True for HIGHER, false for LOWER
        bool claimed;
        uint256 payout;             // Calculated payout after resolution
    }

    // State variables
    IERC20 public immutable bettingToken;
    AggregatorV3Interface public immutable priceFeed;
    address public immutable treasury;
    address public factory;
    
    // VRF variables
    IVRFCoordinatorV2Plus public immutable vrfCoordinator;
    uint256 public immutable subscriptionId;
    bytes32 public immutable keyHash;
    uint32 public constant CALLBACK_GAS_LIMIT = 100000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;
    
    Market public market;
    Bet[] public bets;
    mapping(address => uint256[]) public userBets;
    mapping(address => uint256) public userTotalBets;
    mapping(uint256 => uint256) private vrfRequestToBetIndex; // VRF request ID to bet selection
    
    // Events
    event BetPlaced(address indexed user, uint256 amount, bool isHigher, uint256 betIndex);
    event MarketResolved(bool outcome, uint256 finalPrice, uint256 timestamp);
    event PayoutCalculated(address indexed user, uint256 betIndex, uint256 payout);
    event PayoutClaimed(address indexed user, uint256 betIndex, uint256 amount);
    event RandomWinnerSelected(address indexed winner, uint256 bonusAmount);
    event AutomationRequested(uint256 indexed upkeepId);
    event AutomationUpkeepPerformed(uint256 currentTime, uint256 scheduledTime, uint256 delay);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call");
        _;
    }

    modifier marketNotResolved() {
        require(!market.resolved, "Market already resolved");
        _;
    }

    modifier marketResolved() {
        require(market.resolved, "Market not resolved yet");
        _;
    }

    constructor(
        string memory _assetName,
        string memory _baseAsset,
        uint256 _targetPrice,
        uint256 _resolutionTime,
        address _bettingToken,
        address _priceFeed,
        address _treasury,
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        require(_resolutionTime > block.timestamp, "Resolution time must be in future");
        require(_targetPrice > 0, "Target price must be greater than 0");
        require(_treasury != address(0), "Treasury cannot be zero address");

        market = Market({
            assetName: _assetName,
            baseAsset: _baseAsset,
            targetPrice: _targetPrice,
            resolutionTime: _resolutionTime,
            resolved: false,
            outcome: false,
            finalPrice: 0,
            totalPool: 0,
            totalHigherBets: 0,
            totalLowerBets: 0,
            treasuryFee: 0,
            randomBonusPool: 0,
            randomWinner: address(0),
            randomWinnerSelected: false,
            automationFee: 0,
            automationRegistered: false
        });

        bettingToken = IERC20(_bettingToken);
        priceFeed = AggregatorV3Interface(_priceFeed);
        treasury = _treasury;
        factory = msg.sender;
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
    }

    function placeBet(uint256 _amount, bool _isHigher) 
        external 
        nonReentrant 
        marketNotResolved 
    {
        require(_amount > 0, "Amount must be greater than 0");
        require(block.timestamp < market.resolutionTime, "Betting period has ended");

        // Transfer tokens from user
        bettingToken.safeTransferFrom(msg.sender, address(this), _amount);

        // Create bet
        uint256 betIndex = bets.length;
        bets.push(Bet({
            user: msg.sender,
            amount: _amount,
            isHigher: _isHigher,
            claimed: false,
            payout: 0
        }));

        // Update user mappings
        userBets[msg.sender].push(betIndex);
        userTotalBets[msg.sender] += _amount;

        // Update market totals
        market.totalPool += _amount;
        if (_isHigher) {
            market.totalHigherBets += _amount;
        } else {
            market.totalLowerBets += _amount;
        }

        emit BetPlaced(msg.sender, _amount, _isHigher, betIndex);
    }

    // Chainlink Automation - Check if upkeep is needed (ejecutar exactamente en timestamp)
    function checkUpkeep(bytes calldata) 
        external 
        view 
        override 
        returns (bool upkeepNeeded, bytes memory performData) 
    {
        // ⚡ EJECUTAR EXACTAMENTE cuando llegue el timestamp configurado
        upkeepNeeded = (
            block.timestamp >= market.resolutionTime && 
            !market.resolved &&
            market.totalPool > 0
        );
        
        // Incluir timestamp actual para verificación y logging
        performData = abi.encode(block.timestamp, market.resolutionTime);
    }

    // Chainlink Automation - Perform upkeep (resolve market automáticamente)
    function performUpkeep(bytes calldata performData) external override {
        (uint256 currentTime, uint256 scheduledTime) = abi.decode(performData, (uint256, uint256));
        
        // Verificar que estamos ejecutando en el momento correcto
        require(
            currentTime >= scheduledTime && 
            !market.resolved &&
            market.totalPool > 0,
            "Upkeep not needed"
        );
        
        _resolveMarket();
        
        // Emitir evento con información de timing
        emit AutomationUpkeepPerformed(currentTime, scheduledTime, currentTime - scheduledTime);
    }

    // Manual resolution for interface compliance and backup
    function resolveMarket() external override {
        require(msg.sender == factory, "Only factory can resolve");
        require(!market.resolved, "Market already resolved");
        require(block.timestamp >= market.resolutionTime, "Market not ready for resolution");
        
        _resolveMarket();
    }

    function _resolveMarket() internal {
        // Get historical price at resolution time, not current price
        uint256 historicalPrice = _getHistoricalPrice(market.resolutionTime);
        
        market.finalPrice = historicalPrice;
        market.outcome = historicalPrice > market.targetPrice; // true = HIGHER, false = LOWER
        market.resolved = true;

        // Calculate fees
        market.treasuryFee = (market.totalPool * 2) / 100; // 2%
        market.randomBonusPool = (market.totalPool * 2) / 100; // 2%

        // Calculate payouts for all bets
        _calculatePayouts();

        // Select random winner for bonus
        if (bets.length > 0) {
            _requestRandomWinner();
        }

        emit MarketResolved(market.outcome, historicalPrice, block.timestamp);
    }

    function _getHistoricalPrice(uint256 targetTimestamp) internal view returns (uint256) {
        // First, try to get the latest round
        (, int256 latestPrice, , uint256 latestUpdatedAt, uint80 latestRoundId) = priceFeed.latestRoundData();
        require(latestPrice > 0, "Invalid latest price from oracle");
        
        // If the latest update is close to our target time (within 15 minutes), use it
        if (latestUpdatedAt <= targetTimestamp + 900) { // 15 minutes tolerance
            return uint256(latestPrice);
        }
        
        // Otherwise, we need to search backwards for historical data
        uint80 roundId = latestRoundId;
        uint256 bestPrice = uint256(latestPrice);
        uint256 bestTimeDiff = latestUpdatedAt > targetTimestamp ? 
            latestUpdatedAt - targetTimestamp : 
            targetTimestamp - latestUpdatedAt;
        
        // Search backwards up to 10 rounds to find closest historical price
        for (uint256 i = 0; i < 10 && roundId > 0; i++) {
            roundId--;
            
            // Use low-level call to avoid revert on invalid rounds
            (bool success, bytes memory data) = address(priceFeed).staticcall(
                abi.encodeWithSignature("getRoundData(uint80)", roundId)
            );
            
            if (success && data.length >= 160) { // 5 * 32 bytes expected
                (, int256 price, , uint256 updatedAt, ) = abi.decode(data, (uint80, int256, uint256, uint256, uint80));
                
                if (price > 0) {
                    uint256 timeDiff = updatedAt > targetTimestamp ? 
                        updatedAt - targetTimestamp : 
                        targetTimestamp - updatedAt;
                    
                    // If this round is closer to our target time, use it
                    if (timeDiff < bestTimeDiff) {
                        bestPrice = uint256(price);
                        bestTimeDiff = timeDiff;
                    }
                    
                    // If we found a round that's before our target time and within 1 hour, use it
                    if (updatedAt <= targetTimestamp && timeDiff <= 3600) {
                        break;
                    }
                }
            }
        }
        
        // Ensure the best price we found is not too old (max 2 hours from target)
        require(bestTimeDiff <= 7200, "No recent enough price data found");
        
        return bestPrice;
    }

    function _calculatePayouts() internal {
        uint256 winningPool = market.outcome ? market.totalHigherBets : market.totalLowerBets;
        uint256 losingPool = market.outcome ? market.totalLowerBets : market.totalHigherBets;
        
        if (winningPool == 0) {
            // No winners, everyone gets refunded
            for (uint256 i = 0; i < bets.length; i++) {
                bets[i].payout = bets[i].amount;
                emit PayoutCalculated(bets[i].user, i, bets[i].amount);
            }
            return;
        }

        // Distribute losing pool to winners after fees
        uint256 distributionPool = losingPool - market.treasuryFee - market.randomBonusPool;
        
        for (uint256 i = 0; i < bets.length; i++) {
            Bet storage bet = bets[i];
            
            if (bet.isHigher == market.outcome) {
                // Winner: gets original bet + proportional share of losing pool
                uint256 share = (bet.amount * distributionPool) / winningPool;
                bet.payout = bet.amount + share;
            } else {
                // Loser: gets nothing
                bet.payout = 0;
            }
            
            emit PayoutCalculated(bet.user, i, bet.payout);
        }
    }

    function _requestRandomWinner() internal {
        if (bets.length == 0) return;
        
        // Try to request random number from VRF
        try vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        ) returns (uint256 requestId) {
            vrfRequestToBetIndex[requestId] = 0; // Will be used to identify this request
        } catch {
            // If VRF request fails, use fallback method to select random winner
            _selectRandomWinnerFallback();
        }
    }

    function _selectRandomWinnerFallback() internal {
        if (bets.length == 0) return;
        
        // Use block hash and timestamp for pseudo-randomness as fallback
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao, // Updated from block.difficulty
            blockhash(block.number - 1),
            market.totalPool,
            bets.length
        )));
        
        uint256 randomIndex = seed % bets.length;
        market.randomWinner = bets[randomIndex].user;
        market.randomWinnerSelected = true;
        
        emit RandomWinnerSelected(market.randomWinner, market.randomBonusPool);
    }

    // VRF callback - selects random winner
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        require(market.resolved, "Market not resolved");
        require(!market.randomWinnerSelected, "Random winner already selected");
        
        uint256 randomIndex = randomWords[0] % bets.length;
        market.randomWinner = bets[randomIndex].user;
        market.randomWinnerSelected = true;
        
        emit RandomWinnerSelected(market.randomWinner, market.randomBonusPool);
    }

    function claimPayout(uint256 _betIndex) external nonReentrant marketResolved {
        require(_betIndex < bets.length, "Invalid bet index");
        
        Bet storage bet = bets[_betIndex];
        require(bet.user == msg.sender, "Not your bet");
        require(!bet.claimed, "Already claimed");
        require(bet.payout > 0, "No payout available");

        bet.claimed = true;
        
        // Transfer payout
        bettingToken.safeTransfer(msg.sender, bet.payout);
        
        emit PayoutClaimed(msg.sender, _betIndex, bet.payout);
    }

    function claimBonusReward() external nonReentrant marketResolved {
        require(market.randomWinnerSelected, "Random winner not selected yet");
        require(msg.sender == market.randomWinner, "You are not the random winner");
        require(market.randomBonusPool > 0, "No bonus available");
        
        uint256 bonus = market.randomBonusPool;
        market.randomBonusPool = 0;
        
        bettingToken.safeTransfer(msg.sender, bonus);
        
        emit PayoutClaimed(msg.sender, type(uint256).max, bonus); // Use max uint as identifier for bonus
    }

    function collectTreasuryFees() external {
        require(msg.sender == treasury || msg.sender == factory, "Not authorized");
        require(market.resolved, "Market not resolved");
        require(market.treasuryFee > 0, "No fees to collect");
        
        uint256 fees = market.treasuryFee;
        market.treasuryFee = 0;
        
        bettingToken.safeTransfer(treasury, fees);
    }

    // Deposit ETH for automation
    function depositAutomationFee() external payable {
        require(msg.value > 0, "Must send ETH");
        market.automationFee += msg.value;
    }

    // Withdraw unused automation fee (only callable by factory)
    function withdrawAutomationFee() external {
        require(msg.sender == factory, "Only factory authorized");
        require(market.resolved, "Market not resolved");
        
        uint256 amount = market.automationFee;
        if (amount > 0) {
            market.automationFee = 0;
            payable(msg.sender).transfer(amount);
        }
    }

    // Set automation registration status (only callable by factory)
    function setAutomationRegistered(uint256 upkeepId) external onlyFactory {
        market.automationRegistered = true;
        emit AutomationRequested(upkeepId);
    }

    // View functions
    function getMarketInfo() external view returns (
        string memory assetName,
        string memory baseAsset,
        uint256 targetPrice,
        uint256 resolutionTime,
        bool resolved,
        bool outcome,
        uint256 finalPrice,
        uint256 totalPool,
        uint256 totalHigherBets,
        uint256 totalLowerBets
    ) {
        return (
            market.assetName,
            market.baseAsset,
            market.targetPrice,
            market.resolutionTime,
            market.resolved,
            market.outcome,
            market.finalPrice,
            market.totalPool,
            market.totalHigherBets,
            market.totalLowerBets
        );
    }

    function getUserBetCount(address _user) external view returns (uint256) {
        return userBets[_user].length;
    }

    function getUserBet(address _user, uint256 _index) external view returns (
        uint256 amount,
        bool isHigher,
        bool claimed,
        uint256 payout
    ) {
        require(_index < userBets[_user].length, "Invalid index");
        uint256 betIndex = userBets[_user][_index];
        Bet storage bet = bets[betIndex];
        
        return (bet.amount, bet.isHigher, bet.claimed, bet.payout);
    }

    function getBetCount() external view returns (uint256) {
        return bets.length;
    }

    function canUserClaim(address _user, uint256 _betIndex) external view returns (bool) {
        if (!market.resolved || _betIndex >= bets.length) return false;
        
        Bet storage bet = bets[_betIndex];
        return (bet.user == _user && !bet.claimed && bet.payout > 0);
    }

    function canClaimBonus(address _user) external view returns (bool) {
        return (
            market.resolved && 
            market.randomWinnerSelected && 
            _user == market.randomWinner && 
            market.randomBonusPool > 0
        );
    }

    function getCurrentPrice() external view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    function getRandomWinner() external view returns (address) {
        return market.randomWinner;
    }

    function isRandomWinnerSelected() external view returns (bool) {
        return market.randomWinnerSelected;
    }

    // Emergency functions
    function emergencyResolve() external {
        require(msg.sender == factory, "Only factory can emergency resolve");
        require(!market.resolved, "Already resolved");
        require(block.timestamp > market.resolutionTime + 24 hours, "Too early for emergency resolve");
        
        _resolveMarket();
    }

    // Allow contract to receive ETH for automation fees
    receive() external payable {
        market.automationFee += msg.value;
    }

    // Manual function to select random winner if VRF fails
    function selectRandomWinnerManually() external {
        require(msg.sender == factory, "Only factory can call");
        require(market.resolved, "Market not resolved");
        require(!market.randomWinnerSelected, "Random winner already selected");
        require(bets.length > 0, "No bets to select from");
        
        _selectRandomWinnerFallback();
    }
}
