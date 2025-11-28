# Audit Guide - KipuBankV3

## Table of Contents
1. [Introduction](#introduction)
2. [System Architecture](#system-architecture)
3. [Critical Flows](#critical-flows)
4. [Security Checklist](#security-checklist)
5. [Recommended Tests](#recommended-tests)
6. [Gas Considerations](#gas-considerations)
7. [Privacy Considerations](#privacy-considerations)

---

## Introduction

- Audience: security auditors.
- Objective: verify the implementation of KipuBankV3.

### General Information
- **Main Contract:** `KipuBankV3_TP4.sol` (Solidity 0.8.30)
- **Test Network:** Sepolia Testnet
- **External Dependencies:** Uniswap V2, Chainlink, OpenZeppelin
- **Audit Type:** Smart contract security + Protocol integration

### Audit Scope
```
✅ KipuBankV3_TP4.sol (Main Contract)
✅ Deploy.s.sol (Deployment Script)
✅ KipuBankV3.t.sol (Test Suite)
❌ Third-party Contracts (Uniswap V2, Chainlink, OpenZeppelin)
```

---

## System Architecture

### 1. Main Components

```
┌─────────────────────────────────────┐
│     KipuBankV3 (Contract)           │
│  - Deposit/withdrawal management    │
│  - Role control (RBAC)              │
│  - Emergency pause                  │
│  - Automatic swaps                  │
└─────────────────────────────────────┘
        ↓                      ↓
    ┌───────────────┐    ┌─────────────┐
    │ Chainlink     │    │ Uniswap V2  │
    │ Price Feeds   │    │ Router      │
    └───────────────┘    └─────────────┘
        ETH/USD Price      Token Swaps
```

### 2. Data Flow - ETH Deposit

```
User → deposit() 
  ↓
Price validation (Chainlink)
  ↓
BANK_CAP_USD validation
  ↓
balance[user][ETH_TOKEN] update
  ↓
DepositSuccessful event emission
```

### 3. Data Flow - Deposit with Swap

```
User → depositAndSwapERC20(token, amount, minOut, deadline)
  ↓
Validate allowed token
  ↓
transferFrom(user, contract, amount)
  ↓
Determine swap route (TOKEN → WETH → USDC)
  ↓
getAmountsOut() - Estimate USDC to receive
  ↓
BANK_CAP_USD validation
  ↓
safeIncreaseAllowance() - Approve router
  ↓
swapExactTokensForTokens() - Execute swap
  ↓
Validate USDC received >= minOut
  ↓
Update balance[user][USDC_TOKEN]
  ↓
DepositSuccessful event emission
```

### 4. Critical State Variables

```solidity
// Balances by user and token
mapping(address => mapping(address => uint256)) public balances

// Allowed token catalog
mapping(address => TokenData) private sTokenCatalog

// Counters
uint256 private _depositCount
uint256 private _withdrawalCount
```

---

## Critical Flows

### Flow 1: Deposit ETH

**Input:**
- Native ETH

**Validations:**
- msg.value > 0
- ETH/USD price > 0
- price not stale (< 1 hour)
- price deviation <= 5%
- (current_balance + new_deposit_value) <= BANK_CAP_USD

**Effects:**
- balances[msg.sender][address(0)] += msg.value
- _depositCount++
- Event emission

**Risk Points:**
- Invalid Chainlink price
- BANK_CAP_USD could be exceeded
- Staleness not validated
- Price deviation not checked

---

### Flow 2: Deposit Token with Swap

**Input:**
- ERC20 token, amount, minOut, deadline

**Validations:**
1. tokenIn != address(0) && tokenIn != USDC_TOKEN
2. amountIn > 0
3. sTokenCatalog[tokenIn].isAllowed == true
4. token.balanceOf(user) >= amountIn
5. token.allowance(user, contract) >= amountIn
6. Valid swap route
7. getAmountsOut >= amountOutMin
8. (current_balance + usdcReceived) <= BANK_CAP_USD
9. actualAmounts[last] >= amountOutMin (final validation)
10. deadline >= block.timestamp

**External Transfers:**
1. safeTransferFrom(token, user, contract, amountIn)
2. safeIncreaseAllowance(token, router, amountIn)
3. swapExactTokensForTokens (Uniswap V2)

**Effects:**
- balances[msg.sender][USDC_TOKEN] += usdcReceived
- _depositCount++

**Risk Points:**
- Malicious token in transfer
- Front-running on Uniswap
- Stale oracle price
- Token reentrancy
- Balance overflow

---

### Flow 3: Withdraw Tokens

**Input:**
- Token, amount

**Validations:**
1. amountToWithdraw > 0
2. tokenAddress in [address(0), USDC_TOKEN]
3. amountToWithdraw <= MAX_WITHDRAWAL_PER_TX
4. balances[msg.sender][tokenAddress] >= amountToWithdraw

**External Transfers:**
1. If token == address(0): call{value: amount}
2. If token == USDC: safeTransfer(token, user, amount)

**Effects:**
- balances[msg.sender][tokenAddress] -= amountToWithdraw
- _withdrawalCount++

**Risk Points:**
- Reentrancy in ETH transfer (call)
- Non-transferable token
- Balance overflow

---

## Security Checklist

### ✅ Input Validations

- [ ] `deposit()`: msg.value > 0
- [ ] `depositAndSwapERC20()`: tokenIn != address(0) && tokenIn != USDC
- [ ] `depositAndSwapERC20()`: amountIn > 0
- [ ] `withdrawToken()`: amountToWithdraw > 0
- [ ] `withdrawToken()`: tokenAddress in allowed list
- [ ] `setEthPriceFeedAddress()`: address != address(0)

### ✅ Limit Controls

- [ ] BANK_CAP_USD never exceeded
- [ ] MAX_WITHDRAWAL_PER_TX respected
- [ ] amountOutMin protects against excessive slippage
- [ ] Deadlines in swaps

### ✅ Transfer Security

- [ ] SafeERC20 used in all ERC20 transfers
- [ ] ETH transferred with `call{value:}`
- [ ] No re-entry in withdrawToken
- [ ] Approvals are minimal and necessary

### ✅ Reentrancy Protection

- [ ] CEI (Checks-Effects-Interactions) pattern implemented
- [ ] State updates BEFORE external calls
- [ ] No unnecessary delegatecall
- [ ] ReentrancyGuard implemented (✅ ADDED)

### ✅ Access Control

- [ ] `pause()`: Only PAUSE_MANAGER_ROLE
- [ ] `unpause()`: Only PAUSE_MANAGER_ROLE
- [ ] `setEthPriceFeedAddress()`: Only CAP_MANAGER_ROLE
- [ ] `addOrUpdateToken()`: Only TOKEN_MANAGER_ROLE
- [ ] Roles correctly initialized in constructor

### ✅ Oracle Handling

- [ ] Chainlink feed validated for positive prices
- [ ] Staleness validation: ✅ IMPLEMENTED (1 hour timeout)
- [ ] Handling of 0 or negative prices
- [ ] 5% deviation check: ✅ IMPLEMENTED
- [ ] Alternative TWAP consideration

### ✅ Events

- [ ] `DepositSuccessful` emitted in deposit()
- [ ] `DepositSuccessful` emitted in depositAndSwapERC20()
- [ ] `WithdrawalSuccessful` emitted in withdrawToken()
- [ ] Correct event indexing
- [ ] Correct parameters in events

### ✅ Error Handling

- [ ] Custom errors appropriately defined
- [ ] Descriptive error messages
- [ ] No require strings (gas optimization)
- [ ] Specific errors in each case

### ✅ Gas Considerations

- [ ] `unchecked` used conservatively
- [ ] Constants marked as `constant` or `immutable`
- [ ] Optimized storage (mappings vs arrays)
- [ ] No potentially infinite loops

### ✅ Business Logic

- [ ] BANK_CAP_USD reasonable value (1M USD)
- [ ] MAX_WITHDRAWAL_PER_TX reasonable value (100 ETH)
- [ ] Correct swap route (TOKEN → WETH → USDC)
- [ ] Correct decimal conversion

---

## Recommended Tests

### Unit Tests

#### 1. Deposits
```solidity
✅ 0 ETH deposit → Fails (ZeroAmount)
✅ 1 ETH deposit → Success
✅ Deposit exceeding cap → Fails (DepositExceedsCap)
✅ Valid token deposit → Success
✅ Unallowed token deposit → Fails (TokenNotSupported)
```

#### 2. Withdrawals
```solidity
✅ 0 withdrawal → Fails (ZeroAmount)
✅ Successful ETH withdrawal → Success
✅ Withdrawal exceeding limit → Fails (ExceedsLimit)
✅ Withdrawal without balance → Fails (InsufficientBalance)
✅ Unallowed token withdrawal → Fails (TokenNotSupported)
```

#### 3. Swaps
```solidity
✅ Normal swap → Success
✅ Swap with high slippage → Fails (SlippageTooHigh)
✅ Swap with expired deadline → Fails
✅ Unallowed token swap → Fails
```

#### 4. Access Control
```solidity
✅ Change price feed as CAP_MANAGER → Success
✅ Change price feed without role → Fails
✅ Pause as PAUSE_MANAGER → Success
✅ Pause without role → Fails
✅ Add token as TOKEN_MANAGER → Success
✅ Add token without role → Fails
```

### Integration Tests

```solidity
✅ Deposit ETH → Withdraw ETH → Correct balance
✅ Deposit Token → Swap → Correct USDC balance
✅ Multiple deposits from different users → Independent balances
✅ Pause → Deposit fails → Unpause → Deposit succeeds
```

### Fuzzing

```solidity
✅ Random deposits (0 to 1000 ETH)
✅ Multiple swaps with random amounts
✅ Deposit/withdrawal combinations
```

### Gas Tests

```
Expected:
- deposit(): ~20,000-30,000 gas
- depositAndSwapERC20(): ~150,000-200,000 gas
- withdrawToken(): ~50,000-70,000 gas
```

---

## Gas Considerations

### 1. Implemented Optimizations
✅ `unchecked` in safe operations  
✅ Constants as `immutable`  
✅ Indexed events  
✅ Storage packing (implicit)  

### 2. Areas for Improvement
⚠️ ReentrancyGuard adds ~2k gas per call  
⚠️ Staleness validation adds ~2k gas  
⚠️ Multi-oracle validation would add significant gas  

### 3. Gas Estimates (Sepolia)

| Function | Gas | Approx cost (5 gwei) |
|----------|-----|----------------------|
| deposit() | 25k | $0.10 |
| depositAndSwapERC20() | 180k | $0.72 |
| withdrawToken(ETH) | 55k | $0.22 |
| withdrawToken(USDC) | 70k | $0.28 |

---

## Privacy Considerations

### 1. Visible On-Chain Information
- ✅ All deposits/withdrawals are visible
- ✅ User balances are public
- ✅ Swap transactions are transparent

### 2. Recommendations
- Use of mixer for sensitive transactions (optional)
- User data privacy depends on EOA address
- Consider Privacy-Centric Wallet for interactions

---

## Audit Report - Template

### Critical Findings
1. 🔴 [Critical] Name: Description
   - Location: line X in file Y
   - Impact: High/Medium/Low
   - Recommendation: ...

### Important Findings
1. 🟠 [Important] Name: Description
   - ...

### Observations
1. 🟡 [Observation] Name: Description
   - ...

### Summary
- **Overall Criticality:** 
- **Recommendation:** Approve / Reject / Conditional

---

## Additional Resources

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [Uniswap V2 Documentation](https://docs.uniswap.org/sdk/guides/protocol)
- [Chainlink Price Feed Docs](https://docs.chain.link/data-feeds)
- [Solidity Security Best Practices](https://solidity.readthedocs.io/en/latest/security-considerations.html)
- [Smart Contract Audit Best Practices](https://github.com/Consensys/smart-contract-best-practices)

---

**Last Updated:** 28 Nov 2025  
**Version:** 1.0  
**Prepared for:** Security Audit
