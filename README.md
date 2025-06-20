# Prediction Market Smart Contracts

Smart contracts for a decentralized cross-chain prediction market platform using Chainlink services.

## Features

- ✅ Create prediction markets for any event
- ✅ Place bets with USDC
- ✅ Automatic resolution using Chainlink Functions
- ✅ Random bonus winner selection with VRF
- ✅ Cross-chain prize claims with CCIP
- ✅ Proof of Reserves verification

## Tech Stack

- Solidity 0.8.19
- Hardhat
- TypeScript
- Chainlink Services:
  - Price Feeds
  - Functions
  - VRF v2
  - Automation
  - CCIP
  - Proof of Reserves

## Installation

```bash
npm install
```

## Configuration

1. Copy `.env.example` to `.env`
2. Fill in your private key and RPC URLs
3. Get Chainlink subscription IDs

```bash
cp .env.example .env
# Edit .env with your values
```

## Compilation

```bash
npm run build
```

## Testing

```bash
npm test
```

## Deployment

### Local Network

```bash
npx hardhat node
npm run deploy -- --network localhost
```

### Mumbai Testnet

```bash
npm run deploy -- --network mumbai
```

### Sepolia Testnet

```bash
npm run deploy -- --network sepolia
```

## Contract Addresses

### Mumbai Testnet

- MarketFactory: `0x...`
- MockUSDC: `0x...`
- ProofOfReservesGuard: `0x...`
- CCIPBridge: `0x...`
- ChainlinkFunctions: `0x...`

## Usage

### Creating a Market

```javascript
const marketFactory = await ethers.getContractAt(
  "MarketFactory",
  FACTORY_ADDRESS
);
const resolutionTime = Math.floor(Date.now() / 1000) + 86400; // 24 hours

await marketFactory.createMarket(
  "Will Bitcoin reach $100k by end of year?",
  resolutionTime
);
```

### Placing a Bet

```javascript
const market = await ethers.getContractAt("PredictionMarket", MARKET_ADDRESS);
const betAmount = ethers.utils.parseUnits("100", 6); // 100 USDC

// Approve USDC first
await usdc.approve(MARKET_ADDRESS, betAmount);

// Place YES bet
await market.placeBet(true, betAmount);
```

### Claiming Prize

```javascript
// After market resolution
await market.claimPrize();
```

## Chainlink Services Integration

### Price Feeds

Used for market resolution and dynamic odds calculation.

### Functions

Calls external APIs to get real-world data for market resolution.

### VRF (Verifiable Random Function)

Selects random bonus winners among correct predictors.

### Automation (Keepers)

Automatically resolves markets when resolution time is reached.

### CCIP (Cross-Chain Interoperability Protocol)

Enables cross-chain prize claims.

### Proof of Reserves

Verifies protocol solvency before accepting large bets.

## Security Considerations

- All contracts are ownable and upgradeable
- USDC approval required before betting
- Markets can only be resolved after resolution time
- Prize claiming is protected against double-spending
- Cross-chain messages are validated

## Development

### Add New Market Types

1. Extend `PredictionMarket.sol` with new resolution logic
2. Update `MarketFactory.sol` to support new parameters
3. Add corresponding tests

### Integration Testing

```bash
# Run with gas reporting
REPORT_GAS=true npm test

# Run specific test
npx hardhat test test/PredictionMarket.test.ts
```

### Verify Contracts

```bash
npx hardhat verify --network mumbai DEPLOYED_ADDRESS "constructor" "args"
```

## License

MIT
