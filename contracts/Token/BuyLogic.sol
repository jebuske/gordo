// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./SortitionSumTreeFactory.sol";
import "./NFTLogic.sol";

contract BuyLogic is Ownable, NFTLogic, VRFConsumerBaseV2 {
  using SafeMath for uint256;
  using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;

  bool public buyWinnersActive = false;
  bool public nftWinnersActive = false;
  bool public buyLotteryRunning = false;
  bool public bigSellLotteryRunning = false;
  bool public bigSellWinner;
  uint256 internal _secretNumber;
  uint256 public biggestBuy;
  uint256 public bigSellParticipants;
  uint256 public bigSellParticipantsToStart = 10;
  uint256 public bigSellToWin;
  uint256 public bigSellDivider = 4;
  uint256 public jackpotDivider;
  uint256 public buyParticipants;
  uint256 public buyParticipantsToStar = 25;
  uint256 public chanceBuyLottery;
  uint256 public chanceToWinLastBuy;
  uint256 public chanceSellWinner;
  uint256 public jackpot;
  uint256 public largeSell;
  uint256 public lastAmountWon;
  uint256 public lastTimeStamp;
  uint256 public constant MAX_TREE_LEAVES = 5;
  uint256 public minBuyLargeSell;
  uint256 public minimumBuyToWin = 500_000 ether;
  uint256 public nftMinBuy = 1_000_000 ether;
  uint256 public totalBuyOrdersOverPeriod;
  uint256 public totalTokensWon;
  uint256 public totalWinners;
  bytes32 public TREE_KEY_LARGE_SELL;
  bytes32 public TREE_KEY_BUY_WINNERS = 0;
  address[] public bigBuyers;
  address public biggestBuyer;
  address public lastBuyWinner;
  address public selectedWinner;
  mapping(address => bool) internal _whitelistedServices;
  mapping(address => uint256) public amountWonOnBuy;
  mapping(address => bool) public isBiggestBuyer;

  enum Status {
    NotStarted,
    Started,
    WinnersSelected,
    WinnerPaid
  }
  Status public status;
  enum LotteryType {
    BigSell,
    BuyWinner
  }
  LotteryType public lotteryType;

  SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

  //chainlink
  VRFCoordinatorV2Interface COORDINATOR;
  LinkTokenInterface LINKTOKEN;
  uint64 s_subscriptionId;
  address constant vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;
  address constant link = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709;
  bytes32 constant keyHash =
    0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;
  uint32 constant callbackGasLimit = 500000;
  uint16 constant requestConfirmations = 3;
  uint32 numWords = 1;
  uint256[] public s_randomWords;
  uint256 public s_requestId;
  address s_owner;

  event AddWhitelistedService(address service);
  event BiggestBuyerAdded(address biggestBuyer);
  event BigSellNFTEntered(address entrant, uint256 token);
  event AddedToBuyLottery(address user, uint256 chance);
  event AddedToBigSellLottery(address user, uint256 chance);
  event BuyWinnersActiveChanged(bool newValue);
  event BigSellPartToStartChanged(uint256 oldValue, uint256 newValue);
  event BuyPartToStartChanged(uint256 oldValue, uint256 newValue);
  event NFTWinnersActiveChanged(bool newValue);
  event LargeSellChanged(uint256 oldValue, uint256 newValue);
  event BigSellDividerChanged(uint256 oldValue, uint256 newValue);
  event JackpotDividerChanged(uint256 oldValue, uint256 newValue);
  event MinBuyToWinChanged(uint256 oldValue, uint256 newValue);
  event ChanceToWinLastBuyChanged(uint256 oldChance, uint256 newChance);
  event BuyLotteryStarted(uint256 jackpot);
  event BigSellLotteryStarted(uint256 jackpot);

  constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
    COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
    LINKTOKEN = LinkTokenInterface(link);
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

  modifier winnerPayable() {
    require(status == Status.WinnersSelected, "the winner is not yet selected");
    _;
  }

  modifier lotteryNotStarted() {
    require(
      status == Status.NotStarted || status == Status.WinnerPaid,
      "lottery has already started"
    );
    _;
  }

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

  /// @notice Writes the biggest buyer to an array of biggest buy winners
  function addBiggestBuyer() external onlyWhitelistedServices {
    require(block.timestamp > lastTimeStamp + 7 days);
    bigBuyers.push(biggestBuyer);
    isBiggestBuyer[biggestBuyer] = true;
    lastTimeStamp = block.timestamp;
    emit BiggestBuyerAdded(biggestBuyer);
    biggestBuyer = address(0);
    biggestBuy = 0;
  }

  //Change to value instead of BOOL??
  /// @notice Add your NFT with free Big Sell Entry to the contract to participate in the lottery
  /// @param _tokenId The nftId you want to add
  function addBigSellNft(uint256 _tokenId) external {
    require(nftWinnersActive);
    require(ruffleNft.ownerOf(_tokenId) == msg.sender);
    require(bigSellWinner, "big sell winner not activated");
    require(
      bigSellParticipants < bigSellParticipantsToStart,
      "already maximum participants"
    );
    bool freeBigSellChance = ruffleNft.getBigSellEntries(_tokenId);
    if (freeBigSellChance) {
      bigSellParticipants += 1;
      _addToBigSellLottery(msg.sender, bigSellToWin.div(bigSellDivider));
      ruffleNft.burn(_tokenId);
      emit BigSellNFTEntered(msg.sender, _tokenId);
    }
    if (bigSellParticipants == bigSellParticipantsToStart) {
      startBigSellLottery();
    }
  }

  /// @notice Adds an address to the buy winner array
  /// @param user the address of the user
  function _addToBuyLottery(address user, uint256 amount) internal {
    if (TREE_KEY_BUY_WINNERS == 0) {
      TREE_KEY_BUY_WINNERS = keccak256(
        abi.encodePacked(block.timestamp, "buy winner")
      );
      sortitionSumTrees.createTree(TREE_KEY_BUY_WINNERS, MAX_TREE_LEAVES);
    }
    chanceBuyLottery = 10; //default is 10
    if (nftWinnersActive) {
      uint256 nftBalanceUser = ruffleNft.balanceOf(user);
      if (nftBalanceUser != 0) {
        uint256 tokenId = ruffleNft.tokenOfOwnerByIndex(user, 0);
        uint256 multiplier = getLotteryMultiplier(tokenId);
        if (multiplier != 0) {
          chanceBuyLottery = multiplier;
        }
      }
    }
    bool notEntered = chanceOf(user, TREE_KEY_BUY_WINNERS) == 0;
    if (notEntered) {
      sortitionSumTrees.set(
        TREE_KEY_BUY_WINNERS,
        chanceBuyLottery,
        bytes32(uint256(uint160(address(user))))
      );
      buyParticipants += 1;
      totalBuyOrdersOverPeriod += amount;
      emit AddedToBuyLottery(user, chanceBuyLottery);
    }
    if (buyParticipants == buyParticipantsToStart) {
      startBuyLottery();
    }
  }

  function _addToBigSellLottery(address user, uint256 amount) internal {
    if (TREE_KEY_LARGE_SELL == 0) {
      TREE_KEY_LARGE_SELL = keccak256(
        abi.encodePacked(block.timestamp, "sell winner")
      );
      sortitionSumTrees.createTree(TREE_KEY_LARGE_SELL, MAX_TREE_LEAVES);
    }
    if (chanceOf(user, TREE_KEY_LARGE_SELL) == 0) {
      sortitionSumTrees.set(
        TREE_KEY_LARGE_SELL,
        amount,
        bytes32(uint256(uint160(address(user))))
      );
      emit AddedToBigSellLottery(user, amount);
      bigSellParticipants += 1;
    }
    if (bigSellParticipants == bigSellParticipantsToStart) {
      startBigSellLottery();
    }
  }

  /// @notice pay the winners of the lottery
  function payWinnersTokens() external onlyWhitelistedServices winnerPayable {
    //mintFromLiquidity(selectedWinner, jackpot);
    status = Status.WinnerPaid;
    if (lotteryType == LotteryType.BigSell) {
      TREE_KEY_LARGE_SELL = 0;
    }
    //emit PayWinnersTokens(selectedWinner);
  }

  /// @notice returns if an address is in the biggest buyer array
  function getIsBiggestBuyer(address buyer) external view returns (bool) {
    return isBiggestBuyer[buyer];
  }

  /// @notice Enables the possibility to win on buy
  function setBuyWinnersActive(bool _buyWinnersActive) external onlyOwner {
    require(
      buyWinnersActive != _buyWinnersActive,
      "New value is the same as current value"
    );
    buyWinnersActive = _buyWinnersActive;
    emit BuyWinnersActiveChanged(_buyWinnersActive);
  }

  function setBigSellParticipantsToStart(uint256 _bigSellParticipantsToStart)
    external
    onlyOwner
  {
    require(_bigSellParticipantsToStart < 40);
    require(0 < _bigSellParticipantsToStart);
    uint256 oldValue = bigSellParticipantsToStart;
    bigSellParticipantsToStart = _bigSellParticipantsToStart;
    emit BigSellPartToStartChanged(oldValue, bigSellParticipantsToStart);
  }

  function setBuyParticipantsToStart(uint256 _buyParticipantsToStart)
    external
    onlyOwner
  {
    require(_buyParticipantsToStart < 40);
    require(0 < _buyParticipantsToStart);
    uint256 oldValue = buyParticipantsToStart;
    buyParticipantsToStart = _buyParticipantsToStart;
    emit BuyPartToStartChanged(oldValue, buyParticipantsToStart);
  }

  /// @notice Enables the possibility to win on buy
  function setNFTWinnersActive(bool _nftWinnersActive) external onlyOwner {
    require(
      nftWinnersActive != _nftWinnersActive,
      "New value is the same as current value"
    );
    nftWinnersActive = _nftWinnersActive;
    emit NFTWinnersActiveChanged(_nftWinnersActive);
  }

  /// @notice sets the large sell amount
  function setLargeSell(uint256 newLargeSell) external onlyOwner {
    //increase this value before final deployment
    require(newLargeSell > 10000000000000000000000);
    uint256 oldLargeSell = largeSell;
    largeSell = newLargeSell;
    emit LargeSellChanged(oldLargeSell, newLargeSell);
  }

  /// @notice sets the large sell amount
  function setBigSellDivider(uint256 newDivider) external onlyOwner {
    //increase this value before final deployment
    require(newDivider > 1);
    require(newDivider < 10);
    uint256 oldDivider = bigSellDivider;
    bigSellDivider = newDivider;
    emit BigSellDividerChanged(oldDivider, newDivider);
  }

  /// @notice sets the large sell amount
  function setJackpotDivider(uint256 newDivider) external onlyOwner {
    //increase this value before final deployment
    require(newDivider >= 1);
    require(newDivider < 10);
    uint256 oldDivider = jackpotDivider;
    jackpotDivider = newDivider;
    emit JackpotDividerChanged(oldDivider, newDivider);
  }

  /// @notice Change the minimum buy size to be elgible to win
  /// @param _minimumBuyToWin The new cooldown in seconds
  function setMinimumBuyToWin(uint256 _minimumBuyToWin) external onlyOwner {
    uint256 _oldMinBuy = minimumBuyToWin;
    minimumBuyToWin = _minimumBuyToWin;
    emit MinBuyToWinChanged(_oldMinBuy, _minimumBuyToWin);
  }

  /// @notice Change the chance to win the amount of the last buy order (1/Chance)
  /// @param _chanceToWinLastBuy The new chance to win
  function setChanceToWinLastBuy(uint256 _chanceToWinLastBuy) public onlyOwner {
    require(
      _chanceToWinLastBuy >= 100,
      "_chanceToWinLastBuy must be greater than or equal to 100"
    );
    require(
      _chanceToWinLastBuy <= 500,
      "_chanceToWinLastBuy must be less than or equal to 500"
    );
    uint256 _oldChanceToWin = chanceToWinLastBuy;
    chanceToWinLastBuy = _chanceToWinLastBuy;
    emit ChanceToWinLastBuyChanged(_oldChanceToWin, _chanceToWinLastBuy);
  }

  /// @notice Start a new lottery
  function startBuyLottery() internal lotteryNotStarted {
    buyLotteryRunning = true;
    requestRandomWords();
    jackpot = (totalBuyOrdersOverPeriod.div(buyParticipants)).div(5); //20% of all taxes collected over the buy orders go to the lottery
    totalBuyOrdersOverPeriod = 0;
    status = Status.Started;
    lotteryType = LotteryType.BuyWinner;
    emit BuyLotteryStarted(jackpot);
  }

  /// @notice Start a new lottery
  function startBigSellLottery() internal lotteryNotStarted {
    bigSellLotteryRunning = true;
    requestRandomWords();
    jackpot = bigSellToWin.div(jackpotDivider);
    bigSellToWin = 0;
    status = Status.Started;
    lotteryType = LotteryType.BigSell;
    emit BigSellLotteryStarted(jackpot);
  }

  /// @notice fulfill the randomwords from chainlink
  function fulfillRandomWords(
    uint256, /* requestId */
    uint256[] memory randomWords
  ) internal override {
    uint256 winningNumber;
    s_randomWords = randomWords;
    if (lotteryType == LotteryType.BigSell) {
      winningNumber = s_randomWords[0] % bigSellParticipants;
      selectedWinner = payable(
        address(
          uint160(
            uint256(sortitionSumTrees.draw(TREE_KEY_LARGE_SELL, winningNumber))
          )
        )
      );
      status = Status.WinnersSelected;
      bigSellLotteryRunning = false;
    } else {
      winningNumber = s_randomWords[0] % buyParticipants;
      selectedWinner = payable(
        address(
          uint160(
            uint256(sortitionSumTrees.draw(TREE_KEY_BUY_WINNERS, winningNumber))
          )
        )
      );
    }
    status = Status.WinnersSelected;
    buyLotteryRunning = false;
    TREE_KEY_BUY_WINNERS = keccak256(
      abi.encodePacked(block.timestamp, "buywinner")
    );
  }

  /// @notice The chance a user has of winning the lottery. Tokens staked by user / total tokens staked
  /// @param account The account that we want to get the chance of winning for
  /// @return chanceOfWinning The chance a user has to win
  function chanceOf(address account, bytes32 key)
    public
    view
    returns (uint256 chanceOfWinning)
  {
    return
      sortitionSumTrees.stakeOf(
        key,
        bytes32(uint256(uint160(address(account))))
      );
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
}
