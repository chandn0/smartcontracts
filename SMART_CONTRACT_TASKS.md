# Smart Contract Tasks (Base)

## Chain & Tokens
- **Network**: Base Mainnet (chainId: 8453)
- **USDC (native on Base)**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- **Treasury**: Set an owner-controlled treasury address for forfeits

## Contract Scope
- Single escrow contract managing user goals and USDC stakes
- Non-upgradeable for v1 (keep code simple); consider proxy in v2

## Data Model
- `struct Goal { address owner; uint128 amount; uint64 deadline; bool completed; uint64 createdAt; bool claimed; }`
- Per-user indexing for efficient listing (e.g., `mapping(address => uint256[]) userGoalIds`)
- `mapping(uint256 => Goal) goals`; auto-increment `nextGoalId`

## External Integrations
- IERC20 USDC with 6 decimals
- OpenZeppelin: `SafeERC20`, `ReentrancyGuard`, `Ownable`

## Core Functions (v1)
1) `createGoal(uint256 amount, uint64 deadline)`
   - Require `amount > 0`, `deadline > block.timestamp + minBuffer`
   - Pull USDC via `transferFrom` (approve flow). Permit support optional in v1
   - Store goal; emit `GoalCreated`

2) `markComplete(uint256 goalId)`
   - Owner-only; only before `deadline`; set `completed = true`
   - Emit `GoalCompleted`

3) `claim(uint256 goalId)`
   - Only owner; require `completed == true` and `!claimed`
   - Option A: allow immediate after completion
   - Option B: require `block.timestamp >= deadline` (select one; default A)
   - Transfer USDC back to owner; set `claimed = true`; emit `StakeClaimed`

4) `forfeit(uint256 goalId)`
   - Anyone can call after `deadline` if `!completed` and `!claimed`
   - Transfer USDC to `treasury`; mark `claimed = true`; emit `StakeForfeited`

5) View helpers
   - `getUserGoals(address user)` → ids
   - `getGoal(uint256 goalId)` → Goal

## Events
- `event GoalCreated(uint256 indexed goalId, address indexed owner, uint256 amount, uint64 deadline)`
- `event GoalCompleted(uint256 indexed goalId)`
- `event StakeClaimed(uint256 indexed goalId, address indexed owner, uint256 amount)`
- `event StakeForfeited(uint256 indexed goalId, address indexed treasury, uint256 amount)`

## Access Control & Admin
- `owner` (contract owner) can update:
  - `treasury` address
  - `minBuffer` (seconds before earliest allowed deadline)
  - Pause/unpause (optional via `Pausable`)

## Safety & Invariants
- Use `nonReentrant` on state-changing functions that transfer tokens
- Validate deadlines and amounts
- Ensure single terminal action per goal (`claimed` gate)
- Handle USDC 6-decimal precision in UI and tests

## Testing (Foundry recommended)
- Create: valid/invalid amount, deadline buffer
- Complete: only owner, only before deadline
- Claim: requires completed, idempotency, token balance checks
- Forfeit: after deadline, not completed, idempotency, treasury receives
- Fuzz: timestamps around boundary conditions
- Reentrancy: attempt malicious ERC20/mock

## Deployment (Base)
- Tools: Foundry or Hardhat; verify on BaseScan
- Inputs: `USDC`, `treasury`, `minBuffer`
- Outputs: contract address; store in env for frontend

## Frontend Integration Notes
- Allowance flow for USDC (`approve` then `createGoal`)
- Display balances in 6 decimals; format consistently
- Status grouping derived from on-chain data:
  - Upcoming: `!completed && now < deadline`
  - Completed: `completed && claimed`
  - Missed (claimable by anyone to treasury): `!completed && now >= deadline`

## Milestones
1) Implement storage, events, and `createGoal`
2) Implement `markComplete`, `claim`, `forfeit` with guards
3) Unit tests covering core flows and edge cases
4) Deploy to Base, verify, set env values
5) Wire frontend flows; manual E2E on Base test wallet


