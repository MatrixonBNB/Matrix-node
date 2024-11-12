// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/libraries/FacetERC20.sol";
import "src/libraries/FacetOwnable.sol";
import "./FacetSwapRouterV56d.sol";
import "./FacetSwapFactoryVac5.sol";
import "solady/utils/Initializable.sol";
  
contract PresaleERC20V6f0 is FacetERC20, FacetOwnable, Initializable {
    event PresaleStarted();
    event PresaleFinalized();
    event PresaleBuy(address indexed buyer, uint256 amount);
    event PresaleSell(address indexed seller, uint256 amount);
    event TokensClaimed(address indexed user, uint256 shareAmount, uint256 tokenAmount);

    struct PresaleStorage {
        address wethAddress;
        address facetSwapRouterAddress;
        address pairAddress;
        uint256 presaleEndTime;
        uint256 presaleDuration;
        mapping(address => uint256) shares;
        uint256 totalShares;
        uint256 maxSupply;
        uint256 tokensForPresale;
    }

    function s() internal pure returns (PresaleStorage storage ps) {
        bytes32 position = keccak256("PresaleERC20.contract.storage.v1");
        assembly {
            ps.slot := position
        }
    }

    function initialize(
        string memory name,
        string memory symbol,
        address _wethAddress,
        address _facetSwapRouterAddress,
        uint256 _maxSupply,
        uint256 _presaleTokenPercentage,
        uint256 _presaleDuration
    ) public initializer {
        require(_presaleTokenPercentage <= 50, "Presale token percentage must not exceed 50");
        require(_presaleTokenPercentage > 0, "Presale token percentage must exceed 0");
        require(_wethAddress != address(0), "WETH address not set");
        
        uint8 decimals = ERC20(_wethAddress).decimals();
        _initializeERC20(name, symbol, decimals);
        _initializeOwner(msg.sender);
        
        s().wethAddress = _wethAddress;
        s().facetSwapRouterAddress = _facetSwapRouterAddress;
        s().maxSupply = _maxSupply;
        s().tokensForPresale = (_maxSupply * _presaleTokenPercentage) / 100;
        s().presaleDuration = _presaleDuration;
    }

    function buyShares(address recipient, uint256 amount) public {
        require(s().presaleEndTime > 0, "Presale has not started");
        require(block.timestamp < s().presaleEndTime, "Presale has ended");
        require(amount > 0, "Amount must be greater than 0");
        
        s().shares[recipient] += amount;
        s().totalShares += amount;
        
        ERC20(s().wethAddress).transferFrom(msg.sender, address(this), amount);
        
        emit PresaleBuy(recipient, amount);
    }

    function sellShares(uint256 amount) public {
        require(s().presaleEndTime > 0, "Presale has not started");
        require(block.timestamp < s().presaleEndTime, "Presale has ended");
        require(amount > 0, "Amount must be greater than 0");
        require(s().shares[msg.sender] >= amount, "Not enough shares");
        
        s().shares[msg.sender] -= amount;
        s().totalShares -= amount;
        
        ERC20(s().wethAddress).transfer(msg.sender, amount);
        
        emit PresaleSell(msg.sender, amount);
    }

    function claimTokens() public {
        uint256 userShares = s().shares[msg.sender];
        require(userShares > 0, "User does not own shares");
        
        if (s().pairAddress == address(0)) {
            finalize();
        }
        
        uint256 tokensPerShare = s().tokensForPresale / s().totalShares;
        uint256 tokenAmount = userShares * tokensPerShare;
        
        _mint(msg.sender, tokenAmount);
        s().shares[msg.sender] = 0;
        
        emit TokensClaimed(msg.sender, userShares, tokenAmount);
    }

    function calculateDust() internal view returns (uint256) {
        uint256 tokensPerShare = s().tokensForPresale / s().totalShares;
        uint256 totalDistributedTokens = tokensPerShare * s().totalShares;
        
        return s().tokensForPresale - totalDistributedTokens;
    }

    function finalize() public {
        require(s().pairAddress == address(0), "Already finalized");
        require(block.timestamp >= s().presaleEndTime, "Presale not finished");
        
        uint256 dust = calculateDust();
        uint256 tokensForTeam = s().maxSupply - s().tokensForPresale * 2;
        
        _mint(address(this), s().tokensForPresale + dust + tokensForTeam);
        
        _approve(address(this), s().facetSwapRouterAddress, s().tokensForPresale);
        ERC20(s().wethAddress).approve(s().facetSwapRouterAddress, s().totalShares);
        
        FacetSwapRouterV56d(s().facetSwapRouterAddress).addLiquidity(
            address(this),
            s().wethAddress,
            s().tokensForPresale,
            s().totalShares,
            0,
            0,
            address(0),
            block.timestamp
        );
        
        address factoryAddress = FacetSwapRouterV56d(s().facetSwapRouterAddress).factory();
        s().pairAddress = FacetSwapFactoryVac5(factoryAddress).getPair(address(this), s().wethAddress);
        
        emit PresaleFinalized();
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function withdrawTokens(address recipient) public onlyOwner {
        uint256 balance = balanceOf(address(this));
        require(balance > 0, "No token balance");
        
        _transfer(address(this), recipient, balance);
    }

    function startPresale() public onlyOwner {
        require(s().presaleEndTime == 0, "Already started");
        
        s().presaleEndTime = block.timestamp + s().presaleDuration;
        
        emit PresaleStarted();
    }
}
