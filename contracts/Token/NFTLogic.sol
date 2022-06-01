// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract NFTLogic {
  INFT721 public ruffleNft;

  /// @notice add erc721 token to the contract for the next lottery
  function setERC721(IERC721 _nft) external onlyOwner {
    ruffleNft = IERC721(_nft);
    emit SetERC721(_nft);
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
  function getBuyAmountMultiplier(uint256 tokenId)
    internal
    view
    returns (uint256)
  {
    return ruffleNft.getBuyAmountMultiplier(tokenId);
  }

  /// @notice get if token has big sell entry for free
  /// @param tokenId the token for which to get the multiplier
  function getBigSellEntries(uint256 tokenId) internal view returns (uint256) {
    return ruffleNft.getBigSellEntries(tokenId);
  }

  /// @notice get if token gives you right to do a free sell
  /// @param tokenId the token for which to get the multiplier
  function getTaxReducer(uint256 tokenId) internal view returns (uint256) {
    return ruffleNft.getTaxReducer(tokenId);
  }

  /// @notice get the lottery multiplier of the nft
  /// @param tokenId
  function getFreeSell(uint256 tokenId) internal view returns (uint256) {
    return ruffleNft.getFreeSell(tokenId);
  }
}
