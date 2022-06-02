import "./SortitionSumTreeFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721Receiver.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../TOKEN/NFTLogic.sol";

contract Lottery is Ownable, VRFConsumerBaseV2, IERC721Receiver, NFTLogic {
  using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  mapping(address => bool) internal _whitelistedServices;
  mapping(address => uint256) public timeStaked;
  address[] public stakers;
  IERC721 public nft721;
  uint256 public nftId;
  IERC20 public customToken;
  IERC20 public ruffle;

  address payable[] public selectedWinners;
  address[] public lastWinners;
  uint256[] public winningNumbers;
  uint256 public jackpot;
  uint256 public lastJackpot;
  uint256 public totalEthPaid;
  uint256 public totalWinnersPaid;
  uint256[] public percentageOfJackpot = [75, 18, 7];
  mapping(address => uint256) public amountWonByUser;

  enum Status {
    NotStarted,
    Started,
    WinnersSelected,
    WinnerPaid
  }
  Status public status;

  enum LotteryType {
    NotStarted,
    Ethereum,
    Token,
    NFT721
  }
  LotteryType public lotteryType;

  //Staking
  uint256 public totalStaked;
  mapping(address => uint256) public balanceOf;
  bool public stakingEnabled;

  //Variables used for the sortitionsumtrees
  bytes32 private constant TREE_KEY = keccak256("Lotto");
  uint256 private constant MAX_TREE_LEAVES = 5;

  // Ticket-weighted odds
  SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

  // Chainlink
  VRFCoordinatorV2Interface COORDINATOR;
  LinkTokenInterface LINKTOKEN;
  uint64 s_subscriptionId;

  // Mainnet coordinator. 0x271682DEB8C4E0901D1a1550aD2e64D568E69909
  // see https://docs.chain.link/docs/vrf-contracts/#configurations
  address constant vrfCoordinator = 0x271682DEB8C4E0901D1a1550aD2e64D568E69909;

  // Mainnet LINK token contract. 0x514910771af9ca656af840dff83e8264ecf986ca
  // see https://docs.chain.link/docs/vrf-contracts/#configurations
  address constant link = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

  // 200 gwei Key Hash lane for chainlink mainnet
  // see https://docs.chain.link/docs/vrf-contracts/#configurations
  bytes32 constant keyHash =
    0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef;

  uint32 constant callbackGasLimit = 500000;
  uint16 constant requestConfirmations = 3;

  // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
  uint32 numWords = 3;

  uint256[] public s_randomWords;
  uint256 public s_requestId;
  address s_owner;

  event AddWhitelistedService(address newWhitelistedAddress);
  event RemoveWhitelistedService(address removedWhitelistedAddress);
  event SetCustomToken(IERC20 tokenAddress);
  event SetRuffleInuToken(IERC20 ruffleInuTokenAddress);
  event Staked(address indexed account, uint256 amount);
  event Unstaked(address indexed account, uint256 amount);
  event SetERC721(IERC721 nft);
  event SetPercentageOfJackpot(
    uint256[] newJackpotPercentages,
    uint256 newNumWords
  );
  event UpdateSubscription(
    uint256 oldSubscriptionId,
    uint256 newSubscriptionId
  );
  event EthLotteryStarted(uint256 jackpot, uint256 numberOfWinners);
  event TokenLotteryStarted(uint256 jackpot, uint256 numberOfWinners);
  event NFTLotteryStarted(uint256 nftId);
  event PayWinnersEth(address[] winners);
  event PayWinnersTokens(address[] winners);
  event PayWinnerNFT(address[] winners);
  event SetStakingEnabled(bool stakingEnabled);

  constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    LINKTOKEN = LinkTokenInterface(link);
    sortitionSumTrees.createTree(TREE_KEY, MAX_TREE_LEAVES);
    s_owner = msg.sender;
    s_subscriptionId = subscriptionId;
    addWhitelistedService(msg.sender);
  }

  modifier onlyWhitelistedServices() {
    require(
      _whitelistedServices[msg.sender] == true,
      "onlyWhitelistedServices can perform this action"
    );
    _;
  }

  modifier lotteryNotStarted() {
    require(
      status == Status.NotStarted || status == Status.WinnerPaid,
      "lottery has already started"
    );
    require(
      lotteryType == LotteryType.NotStarted,
      "the previous winner has to be paid before starting a new lottery"
    );
    _;
  }

  modifier winnerPayable() {
    require(status == Status.WinnersSelected, "the winner is not yet selected");
    _;
  }

  //Receive function
  receive() external payable {}

  /// @notice Add new service that can call payWinnersEth and startEthLottery.
  /// @param _service New service to add
  function addWhitelistedService(address _service) public onlyOwner {
    require(
      _whitelistedServices[_service] != true,
      "TaskTreasury: addWhitelistedService: whitelisted"
    );
    _whitelistedServices[_service] = true;
    emit AddWhitelistedService(_service);
  }

  /// @notice add nft multiplier
  function nftMultiplier(uint256 _tokenId) external {
    require(nft721.ownerOf(_tokenId) == address(msg.sender));
    uint256 multiplier = getLotteryMultiplier(_tokenId);
    uint256 _newValue = balanceOf[msg.sender].mul(multiplier);
    sortitionSumTrees.set(
      TREE_KEY,
      _newValue,
      bytes32(uint256(uint160(address(msg.sender))))
    );
  }

  /// @notice Remove old service that can call startEthLottery and payWinnersEth
  /// @param _service Old service to remove
  function removeWhitelistedService(address _service) external onlyOwner {
    require(
      _whitelistedServices[_service] == true,
      "addWhitelistedService: !whitelisted"
    );
    _whitelistedServices[_service] = false;
    emit RemoveWhitelistedService(_service);
  }

  /// @notice a function to cancel the current lottery in case the chainlink vrf fails
  /// @dev only call this when the chainlink vrf fails

  function cancelLottery() external onlyOwner {
    require(
      status == Status.Started || status == Status.WinnersSelected,
      "you can only cancel a lottery if one has been started or if something goes wrong after selection"
    );
    jackpot = 0;
    setStakingEnabled(true);
    status = Status.WinnerPaid;
    lotteryType = LotteryType.NotStarted;
    delete selectedWinners;
  }

  /// @notice draw the winning addresses from the Sum Tree
  function draw() external onlyOwner {
    require(status == Status.Started, "lottery has not yen been started");
    for (uint256 i = 0; i < s_randomWords.length; i++) {
      uint256 winningNumber = s_randomWords[i] % totalStaked;
      selectedWinners.push(
        payable(
          address(
            uint160(uint256(sortitionSumTrees.draw(TREE_KEY, winningNumber)))
          )
        )
      );
      winningNumbers.push(winningNumber);
    }
    status = Status.WinnersSelected;
  }

  /// @notice function needed to receive erc721 tokens in the contract
  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) external pure override returns (bytes4) {
    return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
  }

  /// @notice pay the winners of the lottery
  function payWinnersTokens() external onlyOwner winnerPayable {
    require(
      lotteryType == LotteryType.Token,
      "the lottery that has been drawn is not a custom lottery"
    );

    delete lastWinners;
    for (uint256 i = 0; i < selectedWinners.length; i++) {
      uint256 _amountWon = jackpot.mul(percentageOfJackpot[i]).div(100);
      customToken.safeTransfer(selectedWinners[i], _amountWon);
      lastWinners.push(selectedWinners[i]);
      amountWonByUser[selectedWinners[i]] += _amountWon;
    }
    lastJackpot = jackpot;
    totalWinnersPaid += selectedWinners.length;
    delete selectedWinners;
    jackpot = 0;
    setStakingEnabled(true);
    status = Status.WinnerPaid;
    lotteryType = LotteryType.NotStarted;
    emit PayWinnersTokens(lastWinners);
  }

  /// @notice pay the winners of the lottery
  function payWinnersEth() external onlyWhitelistedServices winnerPayable {
    require(
      lotteryType == LotteryType.Ethereum,
      "the lottery that has been drawn is not an eth lottery"
    );

    delete lastWinners;
    for (uint256 i = 0; i < selectedWinners.length; i++) {
      uint256 _amountWon = jackpot.mul(percentageOfJackpot[i]).div(100);
      selectedWinners[i].transfer(_amountWon);
      lastWinners.push(selectedWinners[i]);
      amountWonByUser[selectedWinners[i]] += _amountWon;
    }
    lastJackpot = jackpot;
    totalEthPaid += jackpot;
    totalWinnersPaid += selectedWinners.length;
    delete selectedWinners;
    jackpot = 0;
    setStakingEnabled(true);
    status = Status.WinnerPaid;
    lotteryType = LotteryType.NotStarted;
    emit PayWinnersEth(lastWinners);
  }

  /// @notice pay the winners of the lottery
  function payWinnersERC721() external onlyOwner winnerPayable {
    require(
      lotteryType == LotteryType.NFT721,
      "the lottery that has been drawn is not a ERC721 lottery"
    );

    delete lastWinners;
    nft721.safeTransferFrom(address(this), selectedWinners[0], nftId);
    lastWinners.push(selectedWinners[0]);
    totalWinnersPaid += 1;
    delete selectedWinners;
    setStakingEnabled(true);
    status = Status.WinnerPaid;
    lotteryType = LotteryType.NotStarted;
    emit PayWinnerNFT(lastWinners);
  }

  /// @notice a function to add a custom token for a custom token lottery
  /// @param customTokenAddress the address of the custom token that we want to add to the contract
  function setCustomToken(IERC20 customTokenAddress) external onlyOwner {
    customToken = IERC20(customTokenAddress);

    emit SetCustomToken(customTokenAddress);
  }

  /// @notice a function to set the address of the ruffle token
  /// @param ruffleAddress is the address of the ruffle token
  function setRuffleInuToken(IERC20 ruffleAddress) external onlyOwner {
    ruffle = IERC20(ruffleAddress);
    emit SetRuffleInuToken(ruffleAddress);
  }

  /// @notice add erc721 token to the contract for the next lottery
  function setERC721(IERC721 _nft) external onlyOwner {
    nft721 = IERC721(_nft);
    emit SetERC721(_nft);
  }

  /// @notice a function to set the jackpot distribution
  /// @param percentages an array of the percentage distribution
  function setPercentageOfJackpot(uint256[] memory percentages)
    external
    onlyOwner
  {
    require(
      status == Status.NotStarted || status == Status.WinnerPaid,
      "you can only change the jackpot percentages if the lottery is not running"
    );
    delete percentageOfJackpot;
    uint256 _totalSum = 0;
    for (uint256 i; i < percentages.length; i++) {
      percentageOfJackpot.push(percentages[i]);
      _totalSum = _totalSum.add(percentages[i]);
    }
    require(_totalSum == 100, "the sum of the percentages has to be 100");
    numWords = uint32(percentages.length);
    emit SetPercentageOfJackpot(percentages, numWords);
  }

  /// @notice Stakes tokens. NOTE: Staking and unstaking not possible during lottery draw
  /// @param amount Amount to stake and lock
  function stake(uint256 amount) external {
    require(stakingEnabled, "staking is not open");
    if (balanceOf[msg.sender] == 0) {
      sortitionSumTrees.set(
        TREE_KEY,
        amount,
        bytes32(uint256(uint160(address(msg.sender))))
      );
      stakers.push(msg.sender);
      timeStaked[msg.sender] = block.timestamp;
    } else {
      uint256 _newValue = balanceOf[msg.sender].add(amount);
      sortitionSumTrees.set(
        TREE_KEY,
        _newValue,
        bytes32(uint256(uint160(address(msg.sender))))
      );
    }
    ruffle.safeTransferFrom(msg.sender, address(this), amount);
    balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);
    totalStaked = totalStaked.add(amount);
    emit Staked(msg.sender, amount);
  }

  /// @notice Start a new lottery
  /// @param _amount in tokens to add to this lottery
  function startTokenLottery(uint256 _amount)
    external
    onlyOwner
    lotteryNotStarted
  {
    require(
      _amount <= customToken.balanceOf(address(this)),
      "The jackpot has to be less than or equal to the tokens in the contract"
    );

    delete winningNumbers;
    delete s_randomWords;
    setStakingEnabled(false);
    requestRandomWords();
    jackpot = _amount;
    status = Status.Started;
    lotteryType = LotteryType.Token;
    emit TokenLotteryStarted(jackpot, numWords);
  }

  /// @notice Start a new lottery
  /// @param _amount The amount in eth to add to this lottery
  function startEthLottery(uint256 _amount)
    external
    onlyWhitelistedServices
    lotteryNotStarted
  {
    require(
      _amount <= address(this).balance,
      "You can maximum add all the eth in the contract balance"
    );
    delete winningNumbers;
    delete s_randomWords;
    setStakingEnabled(false);
    requestRandomWords();
    jackpot = _amount;
    status = Status.Started;
    lotteryType = LotteryType.Ethereum;
    emit EthLotteryStarted(jackpot, numWords);
  }

  /// @notice Start a new nft lottery
  /// @param _tokenId the id of the nft you want to give away in the lottery
  /// @dev set the jackpot to 1 winner [100] before calling this function
  function startERC721Lottery(uint256 _tokenId)
    external
    onlyOwner
    lotteryNotStarted
  {
    require(nft721.ownerOf(_tokenId) == address(this));
    require(
      percentageOfJackpot.length == 1,
      "jackpot has to be set to 1 winner first, percentageOfJackpot = [100]"
    );
    delete winningNumbers;
    delete s_randomWords;
    nftId = _tokenId;
    setStakingEnabled(false);
    requestRandomWords();
    status = Status.Started;
    lotteryType = LotteryType.NFT721;
    emit NFTLotteryStarted(nftId);
  }

  /// @notice Withdraws staked tokens
  /// @param _amount Amount to withdraw
  function unstake(uint256 _amount) external {
    require(stakingEnabled, "staking is not open");
    require(
      _amount <= balanceOf[msg.sender],
      "you cannot unstake more than you have staked"
    );
    uint256 _newStakingBalance = balanceOf[msg.sender].sub(_amount);
    sortitionSumTrees.set(
      TREE_KEY,
      _newStakingBalance,
      bytes32(uint256(uint160(address(msg.sender))))
    );
    balanceOf[msg.sender] = _newStakingBalance;
    totalStaked = totalStaked.sub(_amount);
    ruffle.safeTransfer(msg.sender, _amount);
    timeStaked[msg.sender] = block.timestamp;
    emit Unstaked(msg.sender, _amount);
  }

  /// @notice function to update the chainlink subscription
  /// @param subscriptionId Amount to withdraw
  function updateSubscription(uint64 subscriptionId) external {
    uint256 _oldValue = s_subscriptionId;
    s_subscriptionId = subscriptionId;
    emit UpdateSubscription(_oldValue, subscriptionId);
  }

  /// @notice Emergency withdraw only call when problems or after community vote
  /// @dev Only in emergency cases. Protected by multisig APAD
  function withdraw() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }

  /// @notice The chance a user has of winning the lottery. Tokens staked by user / total tokens staked
  /// @param account The account that we want to get the chance of winning for
  /// @return chanceOfWinning The chance a user has to win
  function chanceOf(address account)
    external
    view
    returns (uint256 chanceOfWinning)
  {
    return
      sortitionSumTrees.stakeOf(
        TREE_KEY,
        bytes32(uint256(uint160(address(account))))
      );
  }

  /// @notice get the staked ruffle balance of an address
  function getBalance(address staker) external view returns (uint256 balance) {
    return balanceOf[staker];
  }

  function getStaker(uint256 index) external view returns (address) {
    return stakers[index];
  }

  function getStakers() external view returns (uint256) {
    return stakers.length;
  }

  function getTimeStaked(address user) external view returns (uint256) {
    return block.timestamp.sub(timeStaked[user]);
  }

  /// @notice a function to set open/close staking
  function setStakingEnabled(bool _stakingEnabled)
    public
    onlyWhitelistedServices
  {
    stakingEnabled = _stakingEnabled;
    emit SetStakingEnabled(_stakingEnabled);
  }

  /// @notice Request random words from Chainlink VRF V2
  function requestRandomWords() internal {
    // Will revert if subscription is not set and funded.
    s_requestId = COORDINATOR.requestRandomWords(
      keyHash,
      s_subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      numWords
    );
  }

  /// @notice fulfill the randomwords from chainlink
  function fulfillRandomWords(
    uint256, /* requestId */
    uint256[] memory randomWords
  ) internal override {
    s_randomWords = randomWords;
    if (s_randomWords.length <= 5) {
      for (uint256 i = 0; i < s_randomWords.length; i++) {
        uint256 winningNumber = s_randomWords[i] % totalStaked;
        selectedWinners.push(
          payable(
            address(
              uint160(uint256(sortitionSumTrees.draw(TREE_KEY, winningNumber)))
            )
          )
        );
        winningNumbers.push(winningNumber);
      }
      status = Status.WinnersSelected;
    }
  }
}
//https://rinkeby.etherscan.io/address/0x6dde2c2d30a03f73e6d9c4e6c13e8908e1720b3a#code
