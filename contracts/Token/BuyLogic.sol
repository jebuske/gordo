// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract BuyLogic is Ownable {
  using SafeMath for uint256;
  using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;

  bool public buyWinnersActive = false;
  bool public nftWinnersActive = false;
  bool public bigSellWinner;
  uint256 internal _secretNumber;
  uint256 public biggestBuy;
  uint256 public bigSellParticipants;
  uint256 public bigSellToWin;
  uint256 public buyParticipants;
  uint256 public chanceBuyLottery;
  uint256 public chanceToWinLastBuy;
  uint256 public chanceSellWinner;
  uint256 public lastAmountWon;
  uint256 public lastTimeStamp;
  uint256 public minimumBuyToWin = 500_000 ether;
  uint256 public totalBuyOrdersOverPeriod;
  uint256 public totalTokensWon;
  uint256 public totalWinners;
  bytes32 public TREE_KEY_LARGE_SELL;
  bytes32 public TREE_KEY_BUY_WINNERS;
  address[] public bigBuyers;
  address public biggestBuyer;
  address public lastBuyWinner;

  mapping(address => uint256) public amountWonOnBuy;
  mapping(address => bool) public isBiggestBuyer;
  mapping(address => bool) internal _whitelistedServices;

  SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

  /// @notice Writes the biggest buyer to an array of biggest buy winners
  function addBiggestBuyer() external onlyWhitelistedServices {
    require(block.timestamp > lastTimeStamp + 7 days);
    bigBuyers.push(biggestBuyer);
    isBiggestBuyer[biggestBuyer] = true;
    lastTimeStamp = block.timestamp;
  }

  /// @notice Add your NFT with free Big Sell Entry to the contract to participate in the lottery
  /// @param _tokenId The nftId you want to add
  function addBigSellNft(uint256 _tokenId) external {
    require(nft721.ownerOf(_tokenId) == address(msg.sender));
    require(bigSellWinner, "big sell winner not activated");
    require(bigSellParticipants < 20, "already 20 participants");
    bool freeBigSellChance = nft721.getBigSellEntries(_tokenId);
    if (freeBigSellChance) {
      bigSellParticipants.push(msg.sender);
      nft721.approve(address(this), tokenId);
      nft721.safeTransferFrom(msg.sender, address(0), _tokenId);
      nft721.burn(_tokenId);
    }
  }

  /// @notice Adds an address to the buy winner array
  /// @param user the address of the user
  function _addToBuyLottery(address user) internal {
    chanceBuyLottery = 10; //default is 10
    if (nftWinnersActive) {
      uint256 nftBalanceUser = ruffleNft.balanceOf(user);
      if (nftBalanceUser != 0) {
        uint256 tokenId = ruffleNft.tokenofOwnerByIndex(user, 0);
        uint256 multiplier = getLotteryMultiplier(tokenId);
        if (multiplier != 0) {
          chanceBuyLottery = multiplier;
        }
      }
    }
    bool notEntered = chanceOf(user, TREE_KEY_BUY_WINNERS) == 0;
    if (notEntered) {
      setSortitionSumTree(user, TREE_KEY_BUY_WINNERS, chanceBuyLottery);
      buyParticipants += 1;
    }
    //put this in keepers instead of in buy order tx
    /*if (bigSellParticipants == 25) {
            startBuyLottery(totalBuyOrdersOverPeriod.div(25));
        }*/
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
    emit logSetBuyWinnersActive(_buyWinnersActive);
  }

  /// @notice Enables the possibility to win on buy
  function setNFTWinnersActive(bool _nftWinnersActive) external onlyOwner {
    require(
      nftWinnersActive != _nftWinnersActive,
      "New value is the same as current value"
    );
    nftWinnersActive = _nftWinnersActive;
    emit logSetBuyWinnersActive(_nftWinnersActive);
  }

  /// @notice Change the minimum buy size to be elgible to win
  /// @param _minimumBuyToWin The new cooldown in seconds
  function setMinimumBuyToWin(uint256 _minimumBuyToWin) external onlyOwner {
    uint256 _oldMinBuy = minimumBuyToWin;
    minimumBuyToWin = _minimumBuyToWin;
    emit logSetMinBuyToWin(_oldMinBuy, _minimumBuyToWin);
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
    emit logSetChanceToWinLastBuy(_oldChanceToWin, _chanceToWinLastBuy);
  }
}
