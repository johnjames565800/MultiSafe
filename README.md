# 🔐 MultiSafe - Multisig Wallet Manager

A secure multisignature wallet smart contract built on Stacks blockchain using Clarity. Create and manage treasury accounts that require multiple signatures for transactions.

## ✨ Features

- 🏦 **Create Multisig Wallets**: Set up wallets with multiple owners and custom signature thresholds
- 💰 **Secure Deposits**: Add STX tokens to wallet treasuries
- 📝 **Transaction Proposals**: Propose transactions with memo descriptions
- ✅ **Multi-signature Approval**: Require multiple confirmations before execution
- 🔍 **Transparent Tracking**: View wallet and transaction details

## 🚀 Quick Start

### Creating a Wallet

```clarity
(contract-call? .MultiSafe create-wallet 
  (list 'SP1... 'SP2... 'SP3...) ;; owner addresses
  u2) ;; threshold (2 out of 3 signatures required)
```

### Depositing Funds

```clarity
(contract-call? .MultiSafe deposit-amount u1 u1000000) ;; wallet-id, amount in microSTX
```

### Proposing a Transaction

```clarity
(contract-call? .MultiSafe propose-transaction 
  u1 ;; wallet-id
  'SP1ABC... ;; recipient
  u500000 ;; amount
  "Payment for services") ;; memo
```

### Confirming a Transaction

```clarity
(contract-call? .MultiSafe confirm-transaction u1) ;; transaction-id
```

### Executing a Transaction

```clarity
(contract-call? .MultiSafe execute-transaction u1) ;; transaction-id
```

## 📖 Core Functions

### Public Functions

| Function | Description |
|----------|-------------|
| `create-wallet` | Create a new multisig wallet with owners and threshold |
| `deposit` | Deposit all available STX to a wallet |
| `deposit-amount` | Deposit specific amount of STX to a wallet |
| `propose-transaction` | Create a new transaction proposal |
| `confirm-transaction` | Confirm a pending transaction |
| `execute-transaction` | Execute a fully confirmed transaction |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-wallet` | Get wallet details by ID |
| `get-transaction` | Get transaction details by ID |
| `is-wallet-owner` | Check if address is wallet owner |
| `has-confirmed-transaction` | Check if owner confirmed transaction |
| `get-wallet-count` | Get total number of wallets |
| `get-transaction-count` | Get total number of transactions |
| `get-wallet-balance` | Get wallet balance by ID |

## 🛡️ Security Features

- ✅ Owner validation for all wallet operations
- ✅ Duplicate owner prevention
- ✅ Threshold validation (must be > 0 and <= owner count)
- ✅ Double confirmation prevention
- ✅ Balance verification before execution
- ✅ Transaction execution state tracking

## 🔧 Error Codes

| Code | Description |
|------|-------------|
| u100 | Not authorized |
| u101 | Wallet not found |
| u102 | Invalid threshold |
| u103 | Duplicate owner |
| u104 | Transaction not found |
| u105 | Already confirmed |
| u106 | Insufficient confirmations |
| u107 | Transaction already executed |
| u108 | Invalid amount |
| u109 | Insufficient balance |

## 💡 Usage Examples

### 3-of-5 Treasury Wallet
Perfect for DAOs or organizations requiring majority approval:
```clarity
(contract-call? .MultiSafe create-wallet 
  (list 'SP1... 'SP2... 'SP3... 'SP4... 'SP5...) 
  u3)
```

### 2-of-2 Joint Account
Ideal for partnerships requiring unanimous approval:
```clarity
(contract-call? .MultiSafe create-wallet 
  (list 'SP1... 'SP2...) 
  u2)
```

## 🏗️ Development

Built with Clarinet framework for Stacks blockchain. Deploy to testnet or mainnet using standard Clarinet deployment procedures.

## 📄 License

MIT License - feel free to use and modify for your projects!

---

*Secure your treasury with MultiSafe - where multiple signatures mean maximum security* 🔒


