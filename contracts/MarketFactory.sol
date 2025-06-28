// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PredictionMarket.sol";
import "./interfaces/IAutomationRegistrar.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MarketFactory is Ownable {
    address[] public markets;
    
    // Configuration for new markets
    address public immutable bettingToken;
    address public immutable linkToken;
    address public immutable vrfCoordinator;
    bytes32 public immutable keyHash;
    uint256 public immutable subscriptionId;
    
    // Chainlink Automation configuration
    address public immutable automationRegistrar;
    uint256 public constant AUTOMATION_GAS_LIMIT = 500000; // Gas limit for automation
    uint256 public constant AUTOMATION_FUNDING = 1 ether; // 1 LINK for automation registration
    
    // Auto-funding configuration
    uint256 public constant MIN_ETH_FUNDING = 0.001 ether; // 0.001 ETH per market
    uint256 public constant MIN_LINK_FUNDING = 0.1 ether; // 0.1 LINK per market
    
    // Treasury/Factory Fee Configuration (PancakeSwap style)
    uint256 public treasuryFee = 200; // 2% in basis points (100 = 1%)
    uint256 public constant MAX_TREASURY_FEE = 1000; // 10% maximum
    uint256 public constant MIN_TREASURY_FEE = 50; // 0.5% minimum
    
    // ETH/LINK pools for automation funding
    uint256 public ethBalance;
    uint256 public linkBalance;
    
    // Collected fees
    uint256 public collectedFees;
    
    event MarketCreated(
        address indexed market,
        address indexed creator,
        string assetName,
        string baseAsset,
        uint256 targetPrice,
        uint256 resolutionTime,
        address priceFeed
    );
    
    event MarketFunded(
        address indexed market,
        uint256 ethAmount,
        uint256 linkAmount
    );
    
    event AutomationRegistered(
        address indexed market,
        uint256 indexed upkeepId
    );
    
    // Debug events
    event MarketCreationStarted(address indexed creator, string assetName, address priceFeed);
    event ValidationPassed(string step);
    event BalanceCheck(uint256 ethBalance, uint256 linkBalance);
    event PriceFeedValidation(address priceFeed, bool isValid);
    event MarketDeploymentStarted();
    event MarketDeploymentCompleted(address marketAddress);
    
    event TreasuryFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesCollected(address indexed token, uint256 amount);
    event FundsDeposited(address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed token, uint256 amount);
    
    modifier validTreasuryFee(uint256 _fee) {
        require(_fee >= MIN_TREASURY_FEE && _fee <= MAX_TREASURY_FEE, "Invalid treasury fee");
        _;
    }
    
    constructor(
        address _bettingToken,
        address _linkToken,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        address _automationRegistrar
    ) {
        bettingToken = _bettingToken;
        linkToken = _linkToken;
        vrfCoordinator = _vrfCoordinator;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        automationRegistrar = _automationRegistrar;
    }
    
    // Fund the factory with ETH for Chainlink Automation
    function depositETH() external payable onlyOwner {
        require(msg.value > 0, "Must send ETH");
        ethBalance += msg.value;
        emit FundsDeposited(address(0), msg.value); // address(0) represents ETH
    }
    
    // Fund the factory with LINK for VRF
    function depositLINK(uint256 amount) external onlyOwner {
        require(amount > 0, "Must deposit LINK");
        IERC20(linkToken).transferFrom(msg.sender, address(this), amount);
        linkBalance += amount;
        emit FundsDeposited(linkToken, amount);
    }
    
    // Update treasury fee (PancakeSwap style with limits)
    function setTreasuryFee(uint256 _treasuryFee) external onlyOwner validTreasuryFee(_treasuryFee) {
        uint256 oldFee = treasuryFee;
        treasuryFee = _treasuryFee;
        emit TreasuryFeeUpdated(oldFee, _treasuryFee);
    }
    
    function createMarket(
        address _priceFeed,
        string memory _assetName,
        string memory _baseAsset,
        uint256 _targetPrice,
        uint256 _resolutionTime
    ) external returns (address) {
        // Emit debug event to track function start
        emit MarketCreationStarted(msg.sender, _assetName, _priceFeed);
        
        // Validate resolution time
        require(_resolutionTime > block.timestamp, "Resolution time must be in the future");
        emit ValidationPassed("Resolution time");
        
        // Validate price feed
        require(_priceFeed != address(0), "Invalid price feed");
        emit ValidationPassed("Price feed address");
        
        // Validate asset name
        require(bytes(_assetName).length > 0, "Asset name required");
        emit ValidationPassed("Asset name");
        
        // Validate base asset
        require(bytes(_baseAsset).length > 0, "Base asset required");
        emit ValidationPassed("Base asset");
        
        // Validate target price
        require(_targetPrice > 0, "Target price must be greater than 0");
        emit ValidationPassed("Target price");
        
        // Check price feed is actually callable
        try AggregatorV3Interface(_priceFeed).latestRoundData() returns (
            uint80, int256, uint256, uint256, uint80
        ) {
            emit PriceFeedValidation(_priceFeed, true);
        } catch {
            emit PriceFeedValidation(_priceFeed, false);
            revert("Price feed is not accessible");
        }
        
        // Check if we have enough funds for automation
        emit BalanceCheck(ethBalance, linkBalance);
        require(ethBalance >= MIN_ETH_FUNDING, "Factory needs more ETH funding for automation");
        emit ValidationPassed("ETH balance");
        
        require(linkBalance >= MIN_LINK_FUNDING, "Factory needs more LINK funding for VRF");
        emit ValidationPassed("LINK balance");
        
        // Emit event before deployment
        emit MarketDeploymentStarted();
        
        PredictionMarket market = new PredictionMarket(
            _assetName,
            _baseAsset,
            _targetPrice,
            _resolutionTime,
            bettingToken,
            _priceFeed,
            address(this), // Treasury is the factory initially
            vrfCoordinator,
            subscriptionId,
            keyHash
        );
        
        // Auto-fund the new market with ETH and LINK
        _fundNewMarket(address(market));
        
        // Register the new market for automation
        _registerMarketForAutomation(payable(address(market)));
        
        // Emit event after successful deployment
        emit MarketDeploymentCompleted(address(market));
        
        markets.push(address(market));
        
        emit MarketCreated(
            address(market), 
            msg.sender, 
            _assetName, 
            _baseAsset, 
            _targetPrice, 
            _resolutionTime,
            _priceFeed
        );
        
        return address(market);
    }
    
    // Auto-fund new market with minimum ETH and LINK
    function _fundNewMarket(address marketAddress) internal {
        // Ensure we have enough funds
        require(linkBalance >= MIN_LINK_FUNDING, "Insufficient LINK balance for funding");
        require(ethBalance >= MIN_ETH_FUNDING, "Insufficient ETH balance for funding");
        
        // Transfer LINK to the market contract for VRF
        IERC20(linkToken).transfer(marketAddress, MIN_LINK_FUNDING);
        linkBalance -= MIN_LINK_FUNDING;
        
        // Transfer ETH to the market contract for automation
        (bool success, ) = marketAddress.call{value: MIN_ETH_FUNDING}("");
        require(success, "ETH transfer failed");
        ethBalance -= MIN_ETH_FUNDING;
        
        emit MarketFunded(marketAddress, MIN_ETH_FUNDING, MIN_LINK_FUNDING);
    }
    
    // Register the new market for automation
    function _registerMarketForAutomation(address payable marketAddress) internal {
        // Check if automation registrar is configured
        if (automationRegistrar == address(0)) {
            // If no registrar configured, skip automation registration
            // Market can still be resolved manually
            return;
        }
        
        // Check if we have enough LINK balance for automation funding
        if (linkBalance < AUTOMATION_FUNDING) {
            // If insufficient LINK, skip automation registration
            // Market can still be resolved manually
            return;
        }
        
        // Prepare registration parameters
        IAutomationRegistrar.RegistrationParams memory params = IAutomationRegistrar.RegistrationParams({
            name: string(abi.encodePacked("PredictionMarket-", toHexString(marketAddress))),
            encryptedEmail: "",
            upkeepContract: marketAddress,
            gasLimit: uint32(AUTOMATION_GAS_LIMIT),
            adminAddress: address(this), // Factory as admin
            triggerType: 0, // Time-based trigger
            checkData: "",
            triggerConfig: "",
            offchainConfig: "",
            amount: uint96(AUTOMATION_FUNDING)
        });
        
        // Approve LINK spending for the registrar
        IERC20(linkToken).approve(automationRegistrar, AUTOMATION_FUNDING);
        
        try IAutomationRegistrar(automationRegistrar).registerUpkeep(params) returns (uint256 upkeepId) {
            linkBalance -= AUTOMATION_FUNDING;
            
            // Update market automation status
            PredictionMarket(marketAddress).setAutomationRegistered(upkeepId);
            
            emit AutomationRegistered(marketAddress, upkeepId);
        } catch {
            // If automation registration fails, continue without it
            // Market can still be resolved manually
        }
    }
    
    // Called by markets when they resolve to collect fees
    function collectFees(uint256 amount) external {
        require(isMarketValid(msg.sender), "Only valid markets can collect fees");
        require(amount > 0, "No fees to collect");
        
        // The market already transferred the tokens to this contract
        // We just need to track the collected fees
        collectedFees += amount;
        
        emit FeesCollected(bettingToken, amount);
    }
    
    // Check if address is a valid market created by this factory
    function isMarketValid(address market) public view returns (bool) {
        for (uint256 i = 0; i < markets.length; i++) {
            if (markets[i] == market) {
                return true;
            }
        }
        return false;
    }
    
    // Withdraw collected fees
    function withdrawFees(uint256 amount) external onlyOwner {
        require(amount <= collectedFees, "Insufficient fees collected");
        require(amount > 0, "Amount must be greater than 0");
        
        collectedFees -= amount;
        IERC20(bettingToken).transfer(owner(), amount);
        
        emit FundsWithdrawn(bettingToken, amount);
    }
    
    // Withdraw ETH (emergency or excess)
    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= ethBalance, "Insufficient ETH balance");
        require(amount > 0, "Amount must be greater than 0");
        
        ethBalance -= amount;
        payable(owner()).transfer(amount);
        
        emit FundsWithdrawn(address(0), amount);
    }
    
    // Withdraw LINK (emergency or excess)
    function withdrawLINK(uint256 amount) external onlyOwner {
        require(amount <= linkBalance, "Insufficient LINK balance");
        require(amount > 0, "Amount must be greater than 0");
        
        linkBalance -= amount;
        IERC20(linkToken).transfer(owner(), amount);
        
        emit FundsWithdrawn(linkToken, amount);
    }
    
    // Manual resolution function - allows factory owner to resolve any market
    function resolveMarket(address payable marketAddress) external onlyOwner {
        require(isMarketValid(marketAddress), "Invalid market address");
        
        PredictionMarket market = PredictionMarket(marketAddress);
        market.resolveMarket();
    }
    
    // Function to manually select random winner if VRF fails
    function selectRandomWinnerForMarket(address payable marketAddress) external onlyOwner {
        require(isMarketValid(marketAddress), "Invalid market address");
        
        PredictionMarket market = PredictionMarket(marketAddress);
        market.selectRandomWinnerManually();
    }

    // Helper function to convert address to hex string
    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            buffer[i*2] = _HEX_SYMBOLS[uint8(bytes20(addr)[i]) >> 4];
            buffer[i*2+1] = _HEX_SYMBOLS[uint8(bytes20(addr)[i]) & 0x0f];
        }
        return string(buffer);
    }
    
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    
    // Emergency resolution function - can resolve even if automation fails
    function emergencyResolveMarket(address payable marketAddress) external onlyOwner {
        require(isMarketValid(marketAddress), "Invalid market address");
        
        PredictionMarket market = PredictionMarket(marketAddress);
        market.emergencyResolve();
    }
    
    // Fund an existing market with more ETH/LINK if needed
    function fundExistingMarket(address payable marketAddress, uint256 ethAmount, uint256 linkAmount) external onlyOwner {
        require(isMarketValid(marketAddress), "Invalid market address");
        require(ethAmount <= ethBalance, "Insufficient ETH balance");
        require(linkAmount <= linkBalance, "Insufficient LINK balance");
        
        if (linkAmount > 0) {
            IERC20(linkToken).transfer(marketAddress, linkAmount);
            linkBalance -= linkAmount;
        }
        
        if (ethAmount > 0) {
            (bool success, ) = marketAddress.call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            ethBalance -= ethAmount;
        }
        
        emit MarketFunded(marketAddress, ethAmount, linkAmount);
    }
    
    // View functions
    function getTreasuryFee() external view returns (uint256) {
        return treasuryFee;
    }
    
    function getTreasuryFeePercent() external view returns (string memory) {
        // Convert basis points to percentage string
        uint256 percent = treasuryFee / 100;
        uint256 decimal = treasuryFee % 100;
        
        if (decimal == 0) {
            return string(abi.encodePacked(uintToString(percent), "%"));
        } else {
            return string(abi.encodePacked(uintToString(percent), ".", uintToString(decimal), "%"));
        }
    }
    
    function getBalances() external view returns (uint256 _ethBalance, uint256 _linkBalance, uint256 _collectedFees) {
        return (ethBalance, linkBalance, collectedFees);
    }
    
    // Helper function to convert uint to string
    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function getMarketsCount() external view returns (uint256) {
        return markets.length;
    }
    
    function getAllMarkets() external view returns (address[] memory) {
        return markets;
    }
    
    function getMarketsByRange(uint256 start, uint256 end) external view returns (address[] memory) {
        require(start <= end && end < markets.length, "Invalid range");
        
        address[] memory result = new address[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            result[i - start] = markets[i];
        }
        
        return result;
    }
}