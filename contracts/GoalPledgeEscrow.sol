// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

contract GoalPledgeEscrow {
    struct Goal {
        address owner;
        uint128 amount;
        uint64 deadline;
        bool completed;
        uint64 createdAt;
        bool claimed;
    }

    event GoalCreated(uint256 indexed goalId, address indexed owner, uint256 amount, uint64 deadline);
    event GoalCompleted(uint256 indexed goalId);
    event StakeClaimed(uint256 indexed goalId, address indexed owner, uint256 amount);
    event StakeForfeited(uint256 indexed goalId, address indexed treasury, uint256 amount);

    IERC20 public immutable usdc;
    address public treasury;
    uint64 public minDeadlineBuffer;

    uint256 public nextGoalId;
    mapping(uint256 => Goal) public goals;
    mapping(address => uint256[]) public userGoalIds;

    address private _owner;

    modifier onlyOwner() {
        require(msg.sender == _owner, "NOT_OWNER");
        _;
    }

    constructor(address usdcAddress, address treasuryAddress, uint64 minBufferSeconds) {
        require(usdcAddress != address(0), "USDC_ZERO");
        require(treasuryAddress != address(0), "TREASURY_ZERO");
        usdc = IERC20(usdcAddress);
        treasury = treasuryAddress;
        minDeadlineBuffer = minBufferSeconds;
        _owner = msg.sender;
    }

    function owner() external view returns (address) { return _owner; }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "TREASURY_ZERO");
        treasury = newTreasury;
    }

    function setMinDeadlineBuffer(uint64 newBuffer) external onlyOwner {
        minDeadlineBuffer = newBuffer;
    }

    function createGoal(uint256 amount, uint64 deadline) external returns (uint256 goalId) {
        require(amount > 0, "AMOUNT_ZERO");
        require(deadline > block.timestamp + minDeadlineBuffer, "DEADLINE_SOON");

        // Pull USDC from sender
        require(usdc.transferFrom(msg.sender, address(this), amount), "TRANSFER_FROM_FAILED");

        goalId = ++nextGoalId;
        goals[goalId] = Goal({
            owner: msg.sender,
            amount: uint128(amount),
            deadline: deadline,
            completed: false,
            createdAt: uint64(block.timestamp),
            claimed: false
        });
        userGoalIds[msg.sender].push(goalId);

        emit GoalCreated(goalId, msg.sender, amount, deadline);
    }

    function markComplete(uint256 goalId) external {
        Goal storage g = goals[goalId];
        require(g.owner == msg.sender, "NOT_GOAL_OWNER");
        require(!g.completed, "ALREADY_COMPLETED");
        require(block.timestamp <= g.deadline, "PAST_DEADLINE");
        g.completed = true;
        emit GoalCompleted(goalId);
    }

    function claim(uint256 goalId, address to) external {
        Goal storage g = goals[goalId];
        require(g.owner == msg.sender, "NOT_GOAL_OWNER");
        require(!g.claimed, "ALREADY_CLAIMED");
        require(g.completed, "NOT_COMPLETED");
        g.claimed = true;
        require(usdc.transfer(to, g.amount), "TRANSFER_FAILED");
        emit StakeClaimed(goalId, msg.sender, g.amount);
    }

    function forfeit(uint256 goalId) external {
        Goal storage g = goals[goalId];
        require(!g.claimed, "ALREADY_CLAIMED");
        require(block.timestamp > g.deadline, "NOT_PAST_DEADLINE");
        require(!g.completed, "ALREADY_COMPLETED");
        g.claimed = true;
        require(usdc.transfer(treasury, g.amount), "TRANSFER_FAILED");
        emit StakeForfeited(goalId, treasury, g.amount);
    }

    function getUserGoals(address user) external view returns (uint256[] memory) {
        return userGoalIds[user];
    }

    function getGoal(uint256 goalId) external view returns (Goal memory) {
        return goals[goalId];
    }
}


