// https://github.com/iearn-finance/vaults/blob/master/contracts/vaults/yVault.sol

pragma solidity ^0.6.7;

import "./IStrategy.sol";
// File: @openzeppelin/contracts/token/ERC20/ERC20.sol
import "./ERC20.sol";
// File: @openzeppelin/contracts/math/SafeMath.sol
import "./SafeMath.sol";
// File: @openzeppelin/contracts/token/ERC20/SafeERC20.sol
import './SafeERC20.sol';
// File: @openzeppelin/contracts/access/Ownable.sol
import './Ownable.sol';

contract FxsFraxJar is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;
    address public strategy;
    uint256 earnTimeLock = 0;

    constructor(IStrategy _strategy)
        public
        ERC20(
            string(abi.encodePacked("FxsFrax_vault2")),
            string(abi.encodePacked("vFxsFrax2"))
        )
    {
        _setupDecimals(ERC20(_strategy.want()).decimals());
        token = IERC20(_strategy.want());
        strategy = address(_strategy);
    }

    function balance() public view returns (uint256) {
        return
            token.balanceOf(address(this)).add(
                IStrategy(strategy).balanceOf()
            );
    }

    //Stakes all funds in the jar
    //Due to the addition of the migration function, earn() now needs a timelock
    function earn() public onlyOwner {
        if(earnTimeLock != 0 && earnTimeLock < now) {
            uint256 _bal = token.balanceOf(address(this));
            token.safeTransfer(strategy, _bal);
            IStrategy(strategy).deposit();
            earnTimeLock = 0;
        }
        else if(earnTimeLock == 0) {
            earnTimeLock = now + 1 days;
        }
    }

    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        require(msg.sender == tx.origin, "no contracts");

        uint256 _pool = balance();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        earnAmount(_amount);
    }

    //This does what earn() used to do, functionally the same for the end user since no LP tokens are stored in this contract during normal operation
    function earnAmount(uint256 _amount) internal {
        token.safeTransfer(strategy, _amount);
        IStrategy(strategy).deposit();
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) public {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint256 b = token.balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            IStrategy(strategy).withdraw(_withdraw);
            uint256 _after = token.balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        token.safeTransfer(msg.sender, r);
    }

    function getRatio() public view returns (uint256) {
        return balance().mul(1e18).div(totalSupply());
    }

    mapping(address => uint256) private lastTimeRestaked;

    //Migrating returns all staked funds to the jar, call restake() to restake your tokens
    //The website UI will say that a migration has happened recently and a link to the new staking contract will appear for users to review
    function restake() public {
        //24 hour delay in order to prevent someone from repeatedly calling it to deposit other people's funds
        require(lastTimeRestaked[msg.sender] < now, "User already restaked");
        lastTimeRestaked[msg.sender] = now + 1 days;
        //Deposit user's shares back into the strategy contract
        uint256 _shares = balanceOf(msg.sender);
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        uint256 _bal = token.balanceOf(address(this));
        if(r > _bal) {
            r = _bal;
        }
        earnAmount(r);
    }

    //Website UI will hide the restake button for a user if it's been less than 1 day since they last restaked
    function getLastTimeRestaked(address _address) public view returns (uint256) {
        return lastTimeRestaked[_address];
    }
}
