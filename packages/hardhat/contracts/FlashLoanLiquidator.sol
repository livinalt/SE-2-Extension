// SPDX-License-Identifier: UNLICENSED
    pragma solidity ^0.8.20;

    import "./Lending.sol";
    import "./Corn.sol";
    import "./CornDEX.sol";

    contract FlashLoanLiquidator is IFlashLoanRecipient {
        Lending private immutable i_lending;
        Corn private immutable i_corn;
        CornDEX private immutable i_cornDEX;

        constructor(address _lending, address _corn, address _cornDEX) {
            i_lending = Lending(_lending);
            i_corn = Corn(_corn);
            i_cornDEX = CornDEX(_cornDEX);
        }

        function executeOperation(
            uint256 amount,
            address initiator,
            address extraParam
        ) external override returns (bool) {
            // Ensure the caller is the Lending contract
            require(msg.sender == address(i_lending), "Unauthorized caller");

            // Approve Lending contract to spend CORN for liquidation
            require(i_corn.approve(address(i_lending), amount), "CORN approval failed");

            // Liquidate the target user's position (extraParam is the borrower's address)
            i_lending.liquidate(extraParam);

            // Swap received ETH for CORN to repay flash loan
            uint256 ethBalance = address(this).balance;
            require(ethBalance > 0, "No ETH received from liquidation");

            // Perform ETH-to-CORN swap on CornDEX
            uint256 cornReceived = i_cornDEX.swap{value: ethBalance}(ethBalance);

            // Ensure enough CORN was received to repay the flash loan
            require(cornReceived >= amount, "Insufficient CORN received from swap");
            require(i_corn.balanceOf(address(this)) >= amount, "Insufficient CORN balance");

            // Transfer CORN back to Lending contract to be burned by flashLoan
            require(i_corn.transfer(address(i_lending), amount), "CORN transfer to Lending failed");

            // Send any remaining ETH to the initiator
            if (address(this).balance > 0) {
                (bool success, ) = initiator.call{value: address(this).balance}("");
                require(success, "ETH transfer to initiator failed");
            }

            return true;
        }

        // Allow contract to receive ETH from liquidation
        receive() external payable {}
    }