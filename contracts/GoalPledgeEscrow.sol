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
        string description;
    }

    struct Challenge {
        address creator;
        string description;
        uint128 entryFee;      // USDC stake amount
        uint64 startTime;
        uint64 deadline;
        uint256 totalParticipants;
        uint256 winners;       // number of winners
        bool resolved;
        string goal;           // description of the goal
    }

    struct ChallengeParticipant {
        address user;
        uint128 stake;
        bool completed;
        bool claimed;
    }

    event GoalCreated(uint256 indexed goalId, address indexed owner, uint256 amount, uint64 deadline, string description);
    event GoalCompleted(uint256 indexed goalId);
    event StakeClaimed(uint256 indexed goalId, address indexed owner, uint256 amount);
    event StakeForfeited(uint256 indexed goalId, address indexed recipient, uint256 amount);
    event BeneficiarySet(address indexed user, address indexed beneficiary);
    event BeneficiaryCleared(address indexed user);
    
    // Challenge Events
    event ChallengeCreated(uint256 indexed challengeId, address indexed creator, string description, uint128 entryFee, uint64 startTime, uint64 deadline, string goal);
    event ChallengeJoined(uint256 indexed challengeId, address indexed participant, uint128 stake);
    event ChallengeGoalCompleted(uint256 indexed challengeId, address indexed participant);
    event ChallengeResolved(uint256 indexed challengeId, uint256 winners, uint256 totalPayout);
    event ChallengeWinningsClaimed(uint256 indexed challengeId, address indexed winner, uint256 amount);

    IERC20 public immutable usdc;
    address public treasury;
    uint64 public minDeadlineBuffer;

    uint256 public nextGoalId;
    mapping(uint256 => Goal) public goals;
    mapping(address => uint256[]) public userGoalIds;
    mapping(address => address) public userBeneficiaries;
    
    // Challenge storage
    uint256 public nextChallengeId;
    mapping(uint256 => Challenge) public challenges;
    mapping(uint256 => ChallengeParticipant[]) public challengeParticipants;
    mapping(address => uint256[]) public userChallenges;
    mapping(uint256 => mapping(address => uint256)) public userChallengeIndex;

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

    function setBeneficiary(address beneficiary) external {
        require(beneficiary != address(0), "BENEFICIARY_ZERO");
        userBeneficiaries[msg.sender] = beneficiary;
        emit BeneficiarySet(msg.sender, beneficiary);
    }

    function clearBeneficiary() external {
        delete userBeneficiaries[msg.sender];
        emit BeneficiaryCleared(msg.sender);
    }

    function getBeneficiary(address user) external view returns (address) {
        address beneficiary = userBeneficiaries[user];
        return beneficiary != address(0) ? beneficiary : treasury;
    }

    function createGoal(uint256 amount, uint64 deadline, string calldata description) external returns (uint256 goalId) {
        require(amount > 0, "AMOUNT_ZERO");
        require(deadline > block.timestamp + minDeadlineBuffer, "DEADLINE_SOON");
        require(bytes(description).length > 0, "DESCRIPTION_EMPTY");

        // Pull USDC from sender
        require(usdc.transferFrom(msg.sender, address(this), amount), "TRANSFER_FROM_FAILED");

        goalId = ++nextGoalId;
        goals[goalId] = Goal({
            owner: msg.sender,
            amount: uint128(amount),
            deadline: deadline,
            completed: false,
            createdAt: uint64(block.timestamp),
            claimed: false,
            description: description
        });
        userGoalIds[msg.sender].push(goalId);

        emit GoalCreated(goalId, msg.sender, amount, deadline, description);
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
        
        // Use user's beneficiary if set, otherwise use treasury
        address recipient = userBeneficiaries[g.owner] != address(0) 
            ? userBeneficiaries[g.owner] 
            : treasury;
        
        require(usdc.transfer(recipient, g.amount), "TRANSFER_FAILED");
        emit StakeForfeited(goalId, recipient, g.amount);
    }

    // Challenge Functions
    function createChallenge(
        string calldata description,
        uint128 entryFee,
        uint64 startTime,
        uint64 deadline,
        string calldata goal
    ) external returns (uint256 challengeId) {
        require(entryFee > 0, "ENTRY_FEE_ZERO");
        require(startTime > block.timestamp, "START_TIME_PAST");
        require(deadline > startTime + minDeadlineBuffer, "DEADLINE_TOO_SOON");
        require(bytes(description).length > 0, "DESCRIPTION_EMPTY");
        require(bytes(goal).length > 0, "GOAL_EMPTY");

        challengeId = ++nextChallengeId;
        challenges[challengeId] = Challenge({
            creator: msg.sender,
            description: description,
            entryFee: entryFee,
            startTime: startTime,
            deadline: deadline,
            totalParticipants: 0,
            winners: 0,
            resolved: false,
            goal: goal
        });

        emit ChallengeCreated(challengeId, msg.sender, description, entryFee, startTime, deadline, goal);
    }

    function joinChallenge(uint256 challengeId) external {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.creator != address(0), "CHALLENGE_NOT_EXISTS");
        require(block.timestamp < challenge.startTime, "CHALLENGE_STARTED");
        require(userChallengeIndex[challengeId][msg.sender] == 0, "ALREADY_JOINED");

        // Pull USDC from sender
        require(usdc.transferFrom(msg.sender, address(this), challenge.entryFee), "TRANSFER_FROM_FAILED");

        // Add participant
        challengeParticipants[challengeId].push(ChallengeParticipant({
            user: msg.sender,
            stake: challenge.entryFee,
            completed: false,
            claimed: false
        }));

        // Update mappings
        uint256 participantIndex = challengeParticipants[challengeId].length;
        userChallengeIndex[challengeId][msg.sender] = participantIndex;
        userChallenges[msg.sender].push(challengeId);
        challenge.totalParticipants++;

        emit ChallengeJoined(challengeId, msg.sender, challenge.entryFee);
    }

    function markChallengeComplete(uint256 challengeId) external {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.creator != address(0), "CHALLENGE_NOT_EXISTS");
        require(block.timestamp >= challenge.startTime, "CHALLENGE_NOT_STARTED");
        require(block.timestamp <= challenge.deadline, "PAST_DEADLINE");
        require(!challenge.resolved, "CHALLENGE_RESOLVED");

        uint256 participantIndex = userChallengeIndex[challengeId][msg.sender];
        require(participantIndex > 0, "NOT_PARTICIPANT");

        ChallengeParticipant storage participant = challengeParticipants[challengeId][participantIndex - 1];
        require(participant.user == msg.sender, "INVALID_PARTICIPANT");
        require(!participant.completed, "ALREADY_COMPLETED");

        participant.completed = true;
        emit ChallengeGoalCompleted(challengeId, msg.sender);
    }

    function resolveChallenge(uint256 challengeId) external {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.creator != address(0), "CHALLENGE_NOT_EXISTS");
        require(block.timestamp > challenge.deadline, "NOT_PAST_DEADLINE");
        require(!challenge.resolved, "ALREADY_RESOLVED");

        // Count winners
        uint256 winnerCount = 0;
        ChallengeParticipant[] storage participants = challengeParticipants[challengeId];
        
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].completed) {
                winnerCount++;
            }
        }

        challenge.winners = winnerCount;
        challenge.resolved = true;

        uint256 totalPayout = challenge.totalParticipants * challenge.entryFee;
        
        // If no winners, send all to treasury
        if (winnerCount == 0) {
            require(usdc.transfer(treasury, totalPayout), "TRANSFER_FAILED");
            emit ChallengeResolved(challengeId, 0, totalPayout);
            return;
        }

        emit ChallengeResolved(challengeId, winnerCount, totalPayout);
    }

    function claimChallengeWinnings(uint256 challengeId) external {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.resolved, "NOT_RESOLVED");
        require(challenge.winners > 0, "NO_WINNERS");

        uint256 participantIndex = userChallengeIndex[challengeId][msg.sender];
        require(participantIndex > 0, "NOT_PARTICIPANT");

        ChallengeParticipant storage participant = challengeParticipants[challengeId][participantIndex - 1];
        require(participant.user == msg.sender, "INVALID_PARTICIPANT");
        require(participant.completed, "NOT_WINNER");
        require(!participant.claimed, "ALREADY_CLAIMED");

        participant.claimed = true;

        // Calculate winnings: original stake + share of losers' stakes
        uint256 totalPool = challenge.totalParticipants * challenge.entryFee;
        uint256 winnersPool = challenge.winners * challenge.entryFee;
        uint256 losersPool = totalPool - winnersPool;
        uint256 sharePerWinner = losersPool / challenge.winners;
        uint256 totalWinnings = challenge.entryFee + sharePerWinner;

        require(usdc.transfer(msg.sender, totalWinnings), "TRANSFER_FAILED");
        emit ChallengeWinningsClaimed(challengeId, msg.sender, totalWinnings);
    }

    // Getter Functions
    function getUserGoals(address user) external view returns (uint256[] memory) {
        return userGoalIds[user];
    }

    function getGoal(uint256 goalId) external view returns (Goal memory) {
        return goals[goalId];
    }

    function getUserChallenges(address user) external view returns (uint256[] memory) {
        return userChallenges[user];
    }

    function getChallenge(uint256 challengeId) external view returns (Challenge memory) {
        return challenges[challengeId];
    }

    function getChallengeParticipants(uint256 challengeId) external view returns (ChallengeParticipant[] memory) {
        return challengeParticipants[challengeId];
    }

    function getChallengeParticipant(uint256 challengeId, address user) external view returns (ChallengeParticipant memory) {
        uint256 participantIndex = userChallengeIndex[challengeId][user];
        require(participantIndex > 0, "NOT_PARTICIPANT");
        return challengeParticipants[challengeId][participantIndex - 1];
    }
}


