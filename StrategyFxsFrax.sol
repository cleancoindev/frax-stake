// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./StrategyStakingRewardsBase.sol";
import "./IStakingRewards.sol";

abstract contract StrategyFraxFarmBase is StrategyStakingRewardsBase {

    // Token addresses for MATIC
    address public fxs = 0x3e121107F6F22DA4911079845a470757aF4e1A1b;
    address public frax = 0x104592a158490a9228070E0A8e5343B499e125D0;
    address public quick = 0x831753DD7087CaC61aB5644b308642cc1c33Dc13;
    
    uint256 public keepFXS = 200; //2% dev fee
    uint256 public constant keepFXSmax = 10000;

    // Uniswap swap paths
    address[] public frax_fxs_path;
    address[] public quick_frax_path;

    constructor(
        address _rewards,
        address _want,
        address _strategist
    )
        public
        StrategyStakingRewardsBase(
            _rewards,
            _want,
            _strategist
        )
    {
        frax_fxs_path = new address[](2);
        frax_fxs_path[0] = frax;
        frax_fxs_path[1] = fxs;

        quick_frax_path = new address[](2);
        quick_frax_path[0] = quick;
        quick_frax_path[1] = frax;
    }

    // **** State Mutations ****

    function harvest() public override {
        //prevent unauthorized smart contracts from calling harvest()
        require(msg.sender == tx.origin || msg.sender == owner() || msg.sender == strategist, "not authorized");
        
        // Collects QUICK tokens
        IStakingRewards(rewards).getReward();

        //Swap QUICK for Frax
        uint256 _quickBalance = IERC20(quick).balanceOf(address(this));
        if (_quickBalance > 0) {
            _swapUniswapWithPath(quick_frax_path, _quickBalance);
        }
        
        //Swap 1/2 of Frax for FXS
        uint256 _fraxBalance = IERC20(frax).balanceOf(address(this));
        if (_fraxBalance > 0) {
            _swapUniswapWithPath(frax_fxs_path, _fraxBalance.div(2));
        }
        
        // Add liquidity for FXS/FRAX
        uint256 _frax = IERC20(frax).balanceOf(address(this));
        uint256 _fxs = IERC20(fxs).balanceOf(address(this));
        if (_frax > 0 && _fxs > 0) {
            IERC20(frax).safeApprove(currentRouter, 0);
            IERC20(frax).safeApprove(currentRouter, _frax);
            IERC20(fxs).safeApprove(currentRouter, 0);
            IERC20(fxs).safeApprove(currentRouter, _fxs);

            IUniswapRouterV2(currentRouter).addLiquidity(
                frax,
                fxs,
                _frax,
                _fxs,
                0,
                0,
                address(this),
                now + 60
            );

            // Donates DUST
            IERC20(frax).safeTransfer(
                strategist,
                IERC20(frax).balanceOf(address(this))
            );
            IERC20(fxs).safeTransfer(
                strategist,
                IERC20(fxs).balanceOf(address(this))
            );
        }

        //Send performance fee to strategist
        uint256 _want = IERC20(want).balanceOf(address(this));
        if (_want > 0) {
            uint256 performanceFee = _want.mul(keepFXS).div(keepFXSmax);
            IERC20(want).safeTransfer(
                strategist,
                performanceFee
            );
        }

        // Stake the LP tokens
        _distributePerformanceFeesAndDeposit();
    }
}

contract StrategyFxsFrax is StrategyFraxFarmBase {
    // Token addresses
    address public FXS_FRAX_QUICKSWAP_STAKING_CONTRACT = 0x71Fe8138C81d7a0cd7e463c8C7Ff524085A411ab;
    address public FXS_FRAX_MATIC_LP = 0x4756FF6A714AB0a2c69a566E548B59c72eB26725;

    constructor(address _strategist)
        public
        StrategyFraxFarmBase(
            FXS_FRAX_QUICKSWAP_STAKING_CONTRACT,
            FXS_FRAX_MATIC_LP,
            _strategist
        )
    {}

    // **** Views ****

    function getName() external override pure returns (string memory) {
        return "StrategyFxsFraxMatic2";
    }
}
