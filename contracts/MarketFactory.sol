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
    uint16 public treasuryFee = 200; // 2% in basis points (100 = 1%)
    uint16 public constant MAX_TREASURY_FEE = 1000; // 10% maximum
    uint16 public constant MIN_TREASURY_FEE = 50; // 0.5% minimum

    // ETH/LINK pools for automation funding
    uint256 public ethBalance;
    uint256 public linkBalance;

    // Collected fees
    uint256 public collectedFees;

    event MarketCreated(address indexed market, address indexed creator, string assetName, string baseAsset, uint256 targetPrice, uint256 resolutionTime, address priceFeed);

    event MarketFunded(address indexed market, uint256 ethAmount, uint256 linkAmount);

    event AutomationRegistered(address indexed market, uint256 indexed upkeepId);

    event TreasuryFeeUpdated(uint16 oldFee, uint16 newFee);
    event FeesCollected(address indexed token, uint256 amount);
    event FundsDeposited(address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed token, uint256 amount);

    modifier validTreasuryFee(uint256 _fee) {
        require(_fee >= MIN_TREASURY_FEE && _fee <= MAX_TREASURY_FEE, "Invalid treasury fee");
        _;
    }

    constructor(address _bettingToken, address _linkToken, address _vrfCoordinator, bytes32 _keyHash, uint256 _subscriptionId, address _automationRegistrar) {
        bettingToken = _bettingToken;
        linkToken = _linkToken;
        vrfCoordinator = _vrfCoordinator;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        automationRegistrar = _automationRegistrar;
    }

    function depositETH() external payable onlyOwner {
        require(msg.value > 0, "Must send ETH");
        ethBalance += msg.value;
        emit FundsDeposited(address(0), msg.value);
    }

    function depositLINK(uint256 amount) external onlyOwner {
        require(amount > 0, "Must deposit LINK");
        IERC20(linkToken).transferFrom(msg.sender, address(this), amount);
        linkBalance += amount;
        emit FundsDeposited(linkToken, amount);
    }

    function setTreasuryFee(uint16 _treasuryFee) external onlyOwner validTreasuryFee(_treasuryFee) {
        uint16 oldFee = treasuryFee;
        treasuryFee = _treasuryFee;
        emit TreasuryFeeUpdated(oldFee, _treasuryFee);
    }

    function createMarket(address _priceFeed, string memory _assetName, string memory _baseAsset, uint256 _targetPrice, uint256 _resolutionTime) external returns (address) {
        require(_resolutionTime > block.timestamp, "Resolution time must be in the future");

        require(_priceFeed != address(0), "Invalid price feed");

        require(bytes(_assetName).length > 0, "Asset name required");

        require(bytes(_baseAsset).length > 0, "Base asset required");

        require(_targetPrice > 0, "Target price must be greater than 0");

        // Check price feed is actually callable
        try AggregatorV3Interface(_priceFeed).latestRoundData() returns (uint80, int256 price, uint256, uint256 updatedAt, uint80) {
            require(price > 0, "Invalid price data");
            require(updatedAt > 0, "Price data not updated");
            require(block.timestamp - updatedAt <= 3600, "Price data too stale");
        } catch {
            revert("Price feed is not accessible or invalid");
        }

        require(ethBalance >= MIN_ETH_FUNDING, "Factory needs more ETH funding for automation");

        require(linkBalance >= MIN_LINK_FUNDING, "Factory needs more LINK funding for VRF");

        PredictionMarket market = new PredictionMarket(
            _assetName,
            _baseAsset,
            _targetPrice,
            _resolutionTime,
            bettingToken,
            _priceFeed,
            vrfCoordinator,
            subscriptionId,
            keyHash,
            treasuryFee
        );

        _registerMarketForAutomation(payable(address(market)));

        markets.push(address(market));

        emit MarketCreated(address(market), msg.sender, _assetName, _baseAsset, _targetPrice, _resolutionTime, _priceFeed);

        return address(market);
    }

    function _registerMarketForAutomation(address payable marketAddress) internal {
        require(automationRegistrar != address(0), "Automation registrar not configured");

        require(linkBalance >= AUTOMATION_FUNDING, "Insufficient LINK balance for automation");

        IAutomationRegistrar.RegistrationParams memory params = IAutomationRegistrar.RegistrationParams({
            name: string(abi.encodePacked("PredictionMarket-", toHexString(marketAddress))),
            encryptedEmail: "",
            upkeepContract: marketAddress,
            gasLimit: uint32(AUTOMATION_GAS_LIMIT),
            adminAddress: address(this),
            triggerType: 0,
            checkData: "",
            triggerConfig: "",
            offchainConfig: "",
            amount: uint96(AUTOMATION_FUNDING)
        });

        IERC20(linkToken).approve(automationRegistrar, AUTOMATION_FUNDING);

        uint256 upkeepId = IAutomationRegistrar(automationRegistrar).registerUpkeep(params);
        linkBalance -= AUTOMATION_FUNDING;

        PredictionMarket(marketAddress).setAutomationRegistered(upkeepId);

        emit AutomationRegistered(marketAddress, upkeepId);
    }

    function collectFees(uint256 amount) external {
        require(isMarketValid(msg.sender), "Only valid markets can collect fees");
        require(amount > 0, "No fees to collect");

        collectedFees += amount;

        emit FeesCollected(bettingToken, amount);
    }

    function isMarketValid(address market) public view returns (bool) {
        for (uint256 i = 0; i < markets.length; i++) {
            if (markets[i] == market) {
                return true;
            }
        }
        return false;
    }

    function withdrawFees(uint256 amount) external onlyOwner {
        require(amount <= collectedFees, "Insufficient fees collected");
        require(amount > 0, "Amount must be greater than 0");

        collectedFees -= amount;
        IERC20(bettingToken).transfer(owner(), amount);

        emit FundsWithdrawn(bettingToken, amount);
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= ethBalance, "Insufficient ETH balance");
        require(amount > 0, "Amount must be greater than 0");

        ethBalance -= amount;
        payable(owner()).transfer(amount);

        emit FundsWithdrawn(address(0), amount);
    }

    function withdrawLINK(uint256 amount) external onlyOwner {
        require(amount <= linkBalance, "Insufficient LINK balance");
        require(amount > 0, "Amount must be greater than 0");

        linkBalance -= amount;
        IERC20(linkToken).transfer(owner(), amount);

        emit FundsWithdrawn(linkToken, amount);
    }

    function resolveMarket(address payable marketAddress) external {
        require(isMarketValid(marketAddress), "Invalid market address");

        PredictionMarket market = PredictionMarket(marketAddress);

        market.resolveMarket();
        //TODO: GIVE THE RESOLVER A REWARD
    }

    function selectRandomWinnerForMarket(address payable marketAddress) external onlyOwner {
        require(isMarketValid(marketAddress), "Invalid market address");

        PredictionMarket market = PredictionMarket(marketAddress);
        market.selectRandomWinnerManually();
    }

    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            buffer[i * 2] = _HEX_SYMBOLS[uint8(bytes20(addr)[i]) >> 4];
            buffer[i * 2 + 1] = _HEX_SYMBOLS[uint8(bytes20(addr)[i]) & 0x0f];
        }
        return string(buffer);
    }

    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    function getTreasuryFee() external view returns (uint256) {
        return treasuryFee;
    }

    function getBalances() external view returns (uint256 _ethBalance, uint256 _linkBalance, uint256 _collectedFees) {
        return (ethBalance, linkBalance, collectedFees);
    }

    function getTreasuryFeePercent() external view returns (string memory) {
        return _getTreasuryFeePercent();
    }

    function _getTreasuryFeePercent() internal view returns (string memory) {
        uint16 percent = uint16(treasuryFee / 100);
        uint16 decimal = uint16(treasuryFee % 100);

        if (decimal == 0) {
            return string(abi.encodePacked(_uintToString(percent), "%"));
        } else {
            return string(abi.encodePacked(_uintToString(percent), ".", _uintToString(decimal), "%"));
        }
    }

    function _uintToString(uint16 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint16 temp = value;
        uint16 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint16(value % 10)));
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

    receive() external payable {
        ethBalance += msg.value;
    }
}
