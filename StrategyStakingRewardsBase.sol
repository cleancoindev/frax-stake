pragma solidity ^0.6.7;

import "./StrategyBase.sol";

// Base contract for SNX Staking rewards contract interfaces

abstract contract StrategyStakingRewardsBase is StrategyBase {
    address public rewards;
    uint256 lastTimeMigrated = 0;

    // **** Getters ****
    constructor(
        address _rewards,
        address _want,
        address _strategist
    )
        public
        StrategyBase(_want, _strategist)
    {
        rewards = _rewards;
    }

    function balanceOfPool() public override view returns (uint256) {
        return IStakingRewards(rewards).balanceOf(address(this));
    }

    function getHarvestable() external override view returns (uint256) {
        return IStakingRewards(rewards).earned(address(this));
    }

    // **** Setters ****

    function deposit() public override {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(rewards, 0);
            IERC20(want).safeApprove(rewards, _want);
            IStakingRewards(rewards).stake(_want);
        }
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        IStakingRewards(rewards).withdraw(_amount);
        return _amount;
    }

    // **** Admin functions ****

    function salvage(address recipient, address token, uint256 amount) public onlyOwner {
        require(token != want, "cannot salvage");
        IERC20(token).safeTransfer(recipient, amount);
    }

    function migrate(address newStakingContract) external onlyOwner {
        lastTimeMigrated = now;
        //Collect all rewards from the old staking contract and convert to LP
        harvest();
        //Withdraw all tokens from the old staking contract
        _withdrawSome(balanceOfPool());
        //Set staking contract to the new address
        rewards = newStakingContract;
        //Test depositing 1 token into the new staking contract to make sure it's a valid staking contract
        testDeposit();
        //Send all LP tokens back to the jar for users to manually restake (this is so they can confirm the new address is legit)
        uint256 _want = IERC20(want).balanceOf(address(this));
        if(_want > 0) {
            IERC20(want).safeTransfer(jar, _want);
        }
    }

    function testDeposit() internal {
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            IERC20(want).safeApprove(rewards, 0);
            IERC20(want).safeApprove(rewards, 1);
            IStakingRewards(rewards).stake(1);
        }
    }

    function getLastTimeMigrated() public view returns (uint256) {
        return lastTimeMigrated;
    }
}
