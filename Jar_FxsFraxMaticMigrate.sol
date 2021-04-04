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

//The audited FXS/FRAX vault contract, with the ability to restake user funds 12 hours after a migration added back to the contract
contract FxsFraxJarMigrate is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public token;
    address public strategy;
    mapping (address => uint256) private lastTimeStaked;
    mapping (address => uint256) private lastTimeRestaked;

    constructor(IStrategy _strategy)
        public
        ERC20(
            string(abi.encodePacked("FxsFrax_vault2")),
            string(abi.encodePacked("vFxsFrax2"))
        )
    {
        require(address(_strategy) != address(0));
        _setupDecimals(ERC20(_strategy.want()).decimals());
        token = IERC20(_strategy.want());
        strategy = address(_strategy);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool)
    {
        require(recipient != address(this));
        return super.transfer(recipient, amount);
    }

    function balance() public view returns (uint256) {
        return
            token.balanceOf(address(this)).add(
                IStrategy(strategy).balanceOf()
            );
    }

    //Restakes all funds in the jar after the vault migrates
    //Can only be called 12 hrs after the migration was executed, which allows users to verify that the vault migrated to the correct contract
    //The timelock cannot be initiated before the migration, which addresses issue 3.3 in the audit
    function restakeAll() public onlyOwner {
        uint256 lastTimeMigrated = IStrategy(strategy).getLastTimeMigrated();
        require(lastTimeMigrated + 12 hours < now, "Need to wait 12 hrs before migrating user funds");

        uint256 _bal = token.balanceOf(address(this));
        token.safeTransfer(strategy, _bal);
        IStrategy(strategy).deposit();
    }

    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        require(msg.sender == tx.origin, "no contracts");
        lastTimeStaked[msg.sender] = now;

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

    //Migrating returns all staked funds to the jar, call restake() to restake your tokens
    //The website UI will say that a migration has happened recently and a link to the new staking contract will appear for users to review
    function restake() public {
        uint256 lastTimeMigrated = IStrategy(strategy).getLastTimeMigrated();
        //Don't allow stakers to call this function if they staked after the migration, because that would allow the new staker to move other people's funds
        require(lastTimeStaked[msg.sender] < lastTimeMigrated, "Staked after the migration");
        //Prevent users from repeatedly calling this function to deposit other people's funds
        require(lastTimeRestaked[msg.sender] < lastTimeMigrated, "User already restaked");

        lastTimeRestaked[msg.sender] = now;
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

    //Website UI will hide the restake button for a user if they staked after the migration
    function getLastTimeStaked(address _address) public view returns (uint256) {
        return lastTimeStaked[_address];
    }
}
