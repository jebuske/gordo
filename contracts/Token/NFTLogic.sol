// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../NFT/INFT721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTLogic is Ownable {
  INFT721 public ruffleNft;

  /// @notice add erc721 token to the contract for the next lottery
  function setRuffleNFTAddress(INFT721 _nft) external onlyOwner {
    ruffleNft = INFT721(_nft);
    //emit SetERC721(_nft);
  }

  /// @notice get the lottery multiplier of the nft
  /// @param tokenId the token for which to get the multiplier
  function getLotteryMultiplier(uint256 tokenId)
    internal
    view
    returns (uint256)
  {
    return ruffleNft.getLotteryMultiplier(tokenId);
  }

  /// @notice get the on buy multiplier
  /// @param tokenId the token for which to get the multiplier
  function getOnBuyMultiplier(uint256 tokenId) internal view returns (uint256) {
    return ruffleNft.getOnBuyMultiplier(tokenId);
  }

  /// @notice get the buy amount multiplier
  /// @param tokenId the token for which to get the multiplier
  function getFreeTokens(uint256 tokenId) internal view returns (uint256) {
    return ruffleNft.getFreeTokens(tokenId);
  }

  /// @notice get if token has big sell entry for free
  /// @param tokenId the token for which to get the multiplier
  function getBigSellEntries(uint256 tokenId) internal view returns (bool) {
    return ruffleNft.getBigSellEntries(tokenId);
  }

  /// @notice fetch if the nft gives a tax reducer
  /// @param tokenId the token for which to get the multiplier
  function getTaxReducer(uint256 tokenId) internal view returns (uint256) {
    return ruffleNft.getTaxReducer(tokenId);
  }

  /// @notice fetch if you get a free sell by holding the nft
  /// @param tokenId the token for which to get the free sell
  function getFreeSell(uint256 tokenId) internal view returns (bool) {
    return ruffleNft.getFreeSell(tokenId);
  }

  ///@notice get the burn lottery entries of the nft
  /// @param tokenId the token for which to get the burn entries
  function getBurnEntries(uint256 tokenId) internal view returns (uint256) {
    return ruffleNft.getBurnEntries(tokenId);
  }
}
