#!/usr/bin/env bash
set -e

# Insert forge-lint disable and justification before return uint256(price); in main file
sed -i "/return uint256(price);/i\\        // forge-lint: disable-next-line(unsafe-typecast)" /home/sonic/KipuBankV3_TP4/src/KipuBankV3_TP4.sol
sed -i "/forge-lint: disable-next-line(unsafe-typecast)/i\\        // casting to 'uint256' is safe because price > 0" /home/sonic/KipuBankV3_TP4/src/KipuBankV3_TP4.sol

# Repeat for the copia file
sed -i "/return uint256(price);/i\\        // forge-lint: disable-next-line(unsafe-typecast)" "/home/sonic/KipuBankV3_TP4/src/KipuBankV3_TP4 - copia.sol"
sed -i "/forge-lint: disable-next-line(unsafe-typecast)/i\\        // casting to 'uint256' is safe because price > 0" "/home/sonic/KipuBankV3_TP4/src/KipuBankV3_TP4 - copia.sol"

# Format and build using the absolute foundry binary
/home/sonic/.foundry/bin/forge fmt
/home/sonic/.foundry/bin/forge build
